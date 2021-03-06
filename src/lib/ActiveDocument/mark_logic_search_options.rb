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


# MarkLogicSearchOptions allow you to control exactly how the ActiveDocument::Finder#search method behaves and what additional
# information may be returned in the ActiveDocument::SearchResults object
# == Attributes
# * return_facets - if true then facet information is returned in the resultant ActiveDocument::SearchResults object. Default is true
# * value_constraints - this is a #Hash of value constraint names to their options. e.g. search_options_object.value_constraints["Region"] = {"namespace" => "http://wits.nctc.gov", "element" => "Region"}
module ActiveDocument
  class MarkLogicSearchOptions
    attr_accessor :return_facets, :value_constraints, :word_constraints, :range_constraints

    def initialize
      @return_facets = true;
      @value_constraints = Hash.new
      @word_constraints = Hash.new
      @range_constraints = Hash.new
    end


    # outputs the object in correctly formatted XML suitable for use in a search
    def to_s
      constraints = String.new
      @value_constraints.each do |key, value|
        constraints << <<-XML
        <constraint name="#{key.gsub(/\s/, '_')}">
          <value>
            <element ns="#{value["namespace"]}" name="#{value["element"]}"/>
          </value>
        </constraint>
        XML
      end

      @word_constraints.each do |key, value|
        constraints << <<-XML
        <constraint name="#{key.gsub(/\s/, '_')}">
          <word>
            <element ns="#{value["namespace"]}" name="#{value["element"]}"/>
          </word>
        </constraint>
        XML
      end

      @range_constraints.each do |key, value|
        constraints << <<-XML
        <constraint name="#{key.gsub(/\s/, '_')}">
          <range type="#{value["type"]}"
        XML
        if value.has_key?("collation")
          constraints << "collation=\"#{value["collation"]}\""
        end

        constraints << <<-XML
            >
            <element ns="#{value["namespace"]}" name="#{value["element"]}"/>
        XML

        if value.has_key?("computed_buckets")
          value["computed_buckets"].each do |computed_bucket|
            constraints << computed_bucket.to_s if computed_bucket.instance_of?(ActiveDocument::MarkLogicSearchOptions::ComputedBucket)
          end
        end
        constraints << "</range></constraint>"
      end

      value = <<-XML
      <options xmlns="http://marklogic.com/appservices/search">
      <return-facets>#{@return_facets}</return-facets>
      XML

      # add in constraints
      unless constraints.empty?
        value << constraints
      end
      # close the options node
      value << "</options>"

    end

    #end to_s

    class ComputedBucket
      attr_accessor :name, :ge, :lt, :anchor, :title

      def initialize (name, ge, lt, anchor, title)
        @name = name
        @ge = ge
        @lt = lt
        @anchor = anchor
        @title = title
      end

      def to_s
        <<-XML
          <computed-bucket name="#{@name}" ge="#{@ge}" lt="#{@lt}" anchor="#{@anchor}">#{@title}</computed-bucket>
        XML
      end
    end
  end

end