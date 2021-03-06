#   Copyright 2010 Mark Logic, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.


require 'ActiveDocument/mark_logic_http'
require 'rubygems'
require 'nokogiri'
require 'yaml'
require 'ActiveDocument/mark_logic_query_builder'
require 'ActiveDocument/search_results'
require 'ActiveDocument/finder'
require "ActiveDocument/inheritable"

# The ActiveXML module is used as a namespace for all classes relating to the ActiveXML functionality.
# ActiveXML::Base is the class that should be extended in order to make use of this functionality in your own
# domain objects.
#
module ActiveDocument

  # Developers should extend this class to create their own domain classes
  # -------------------
  #  = Usage
  # -------------------
  # == Dynamic Finders
  # ActiveDocument::Base provides extensive methods for finding matching documents based on a variety of criteria.
  # === Find By Element
  # Accessed via find_by_ELEMENT method where Element = the name of your element. Executes a search for all documents
  # with an element ELEMENT that contains the value passed in to the method call.
  # The signature of this dynamic finder is:
  # <tt>find_by_ELEMENT(value, root [optional], element_namespace [optional], root_namespace [optional])</tt>
  #
  # Parameters details are as follows:
  # <b>Value:</b> the text to be found within the given element. This is a mandatory parameter
  # <b>Namespace:</b> The namespace in which the element being searched occurs. This is an optional element. If provided,
  # it will be used in the search and will override any default values. If no namespace if provided then the code will
  # attempt to dynamically determine the namespace. First, if the element name is contained in the namespaces hash
  # then that namespace is used. If the element name is not found then the _default_namespace_
  # is used. If there is no default namespace, then no namespace is used.
  # -------------------
  #  == Dynamic Accessors
  # In addition to the ability to access the underlying XML document (as a Nokogiri XML Document) you have the ability
  # to access the XML as attributes of your domain object via dynamic attribute accessors (eg. domain_object.element_name) The rules for using accessors
  # are as follows:
  #  1. If the element_name is a simple type (i.e. text node with no children <tt><example>text</exmample></tt>)
  #     1. If there is only one occurence of the element, return its text value
  #     2. If there are multiple occurences of the element, return a list of each text value
  #  2. If the element_name is a complex type (e.g. <tt><example><text>hi</text></example></tt>)
  #     1. If there is only one ocurence of the element then return it as a Nokoguri Element
  #     2. If there are multiple occurences of the element, return a list of Nokoguri Elements
  #
  # More complex dynamic accessors are also supported. They still adhere to the rules above, but instead of just looking
  # for an element anywhere in the document, you can be more specific. For example, domain_object.chapter.paragraph
  # will find all paragraph elements that are children of chapter elements.
  # -------------------
  class Base < Finder
    include ClassLevelInheritableAttributes
    inheritable_attributes_list :my_namespaces, :my_default_namespace, :root
    @my_namespaces = Hash.new
    @my_default_namespace = String.new
    attr_reader :document, :uri, :my_namespaces, :my_default_namespace, :root


    # create a new instance with an optional xml string to use for constructing the model
    def initialize(xml_string = "", uri = "nil")
      @document = Nokogiri::XML(xml_string) do |config|
        config.noblanks
      end
      if !xml_string.empty? then
        @root = @document.root.name
      end
      @uri = uri
    end

    def to_s
      @document.to_xml(:save_with => Nokogiri::XML::Node::SaveOptions::NO_DECLARATION)
    end

    # saves this document to the repository. If _uri_ is provided then that will be the value used for the uri.
    # If no uri was passed in then the existing value or the uri is used, unless uri is nil in which case an exception
    # will be thrown
    def save(uri = nil)
      doc_uri = (uri || @uri)
      if doc_uri then
        @@ml_http.send_xquery(@@xquery_builder.save(self, doc_uri))
      else
        raise ArgumentError, "uri must not be nil", caller
      end

    end

    # Returns the root element for this object
    def root
      @root
    end

    def [](key)
      namespace = namespace_for_element(key)
      if namespace.empty?
        @document.root.xpath("@#{key}").to_s
      else
        @document.root.xpath("@ns:#{key}", {'ns' => namespace}).to_s
      end
    end

    # enables the dynamic finders
    def method_missing(method_id, * arguments, & block)
      @@log.debug("ActiveDocument::Base at line #{__LINE__}: method called is #{method_id} with arguments #{arguments}")
      method = method_id.to_s
      if method =~ /^(\w*)$/ # methods with no '.' in them and not ending in '='
        if arguments.length > 0
          super
        end
        access_element $1
      elsif method =~ /^(\w*)=$/ && arguments.length == 1 # methods with no '.' in them and ending in '='
        set_element($1, arguments)
      else
        super
      end
    end


    class << self
      attr_reader :namespaces, :default_namespace, :root

      def namespace_for_element(element)
        namespace = nil
        if !@my_namespaces.nil? && @my_namespaces[element]
          namespace = @my_namespaces[element]
        else
          namespace = @my_default_namespace unless @my_default_namespace.nil?
        end
        namespace
      end

      def namespaces(namespace_hash)
        @my_namespaces = namespace_hash
      end

      def add_namespace(element, uri)
        @my_namespaces[element.to_s] == uri
      end

      def remove_namespace(element)
        @my_namespaces.delete element
      end

      def default_namespace(namespace)
        @my_default_namespace = namespace # todo should this just be an entry in namespaces?
      end

      def delete(uri)
        @@ml_http.send_xquery(@@xquery_builder.delete(uri))
      end

      # enables the dynamic finders
      def method_missing(method_id, * arguments, & block)
        @@log.debug("ActiveDocument::Base at line #{__LINE__}: method called is #{method_id} with arguments #{arguments}")
        method = method_id.to_s
        # identify element search methods
        if method =~ /find_by_(.*)$/ and arguments.length > 0
          value = arguments[0]
          element = $1.to_sym
          if arguments[1]
            root = arguments[1]
          else
            root = @root
          end
          if arguments[2]
            element_namespace = arguments[2]
          else
            element_namespace = namespace_for_element(element)
          end
          if arguments[3]
            root_namespace = arguments[3]
          else
            root_namespace = namespace_for_element(root)
          end
          execute_finder(element, value, root, element_namespace, root_namespace)
        else
          super
        end

      end

      # Returns an ActiveXML object representing the requested information. If no document exists at that uri then an
      # empty domain object is created and returned
      def load(uri)
        self.new(@@ml_http.send_xquery(@@xquery_builder.load(uri)), uri)
      end

      # Finds all documents of this type that contain the word anywhere in their structure
      def find_by_word(word, root=@root, namespace=@my_default_namespace)
        SearchResults.new(@@ml_http.send_xquery(@@xquery_builder.find_by_word(word, root, namespace)))
      end


    end # end inner class


    class PartialResult < self
      # todo should this contain a reference to its parent?
      def initialize(nodeset, parent)
        @document = nodeset
        @root =
                if nodeset.instance_of? Nokogiri::XML::Element then
                  nodeset.name
                else
                  nodeset[0].name
                end
        @my_namespaces = parent.class.my_namespaces
        @my_default_namespace = parent.class.my_default_namespace
      end

      # returns the number of Nodes in the underlying _NodeSet_
      def length
        @document.length
      end

      # provides access to the child nodes
      def children
        @document.children
      end

      # provides access to an indexed node
      def [](index)
        @document[index]
      end

      def text
        @document.text
      end

    end

    private
    def namespace_for_element(element)
      namespace = nil
      ns = @my_namespaces || self.class.my_namespaces
      default_ns = @my_default_namespace || self.class.my_default_namespace
      if !ns.nil? && ns[element]
        namespace = ns[element]
      else
        namespace = default_ns unless default_ns.nil?
      end
      namespace
    end

    def xpath_for_element(element)
      xpath = String.new
      xpath = "//" unless self.instance_of? PartialResult
      namespace = namespace_for_element(element)
      element = "ns:#{element}" unless namespace.nil? || namespace.empty?
      xpath << element
      return xpath, namespace
    end

    def evaluate_nodeset(result_nodeset)
      if result_nodeset.length == 1 and result_nodeset[0].children.length == 1 and result_nodeset[0].children[0].type == Nokogiri::XML::Node::TEXT_NODE
        PartialResult.new(result_nodeset[0], self)
      else
        PartialResult.new(result_nodeset, self)
      end
    end

    def set_element(element, value)
      # element.chop!
      xpath, namespace = xpath_for_element(element)
      if namespace.nil?
        node = @document.xpath(xpath)
      else
        node = @document.xpath(xpath, {'ns' => namespace})
      end
      if node[0].child.type == Nokogiri::XML::Node::TEXT_NODE
        node[0].child.content = value
      else
        raise ArgumentError, "You can't modify a complex node", caller
      end
    end

    def access_element(element)
      xpath, namespace = xpath_for_element(element)
      if namespace.nil?
        nodes = @document.xpath(xpath)
      else
        nodes = @document.xpath(xpath, {'ns' => namespace})
      end
#      PartialResult.new(nodes, self)
      evaluate_nodeset(nodes)

    end


  end

  # end class

  class ActiveDocumentException < Exception

  end

  class PersistenceException < ActiveDocumentException

  end


end # end module
