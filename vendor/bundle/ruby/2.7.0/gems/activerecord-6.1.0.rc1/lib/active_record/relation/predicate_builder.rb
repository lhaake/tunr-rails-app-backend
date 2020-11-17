# frozen_string_literal: true

module ActiveRecord
  class PredicateBuilder # :nodoc:
    require "active_record/relation/predicate_builder/array_handler"
    require "active_record/relation/predicate_builder/basic_object_handler"
    require "active_record/relation/predicate_builder/range_handler"
    require "active_record/relation/predicate_builder/relation_handler"
    require "active_record/relation/predicate_builder/association_query_value"
    require "active_record/relation/predicate_builder/polymorphic_array_value"

    # No-op BaseHandler to work Mashal.load(File.read("legacy_relation.dump")).
    # TODO: Remove the constant alias once Rails 6.1 has released.
    BaseHandler = BasicObjectHandler

    def initialize(table)
      @table = table
      @handlers = []

      register_handler(BasicObject, BasicObjectHandler.new(self))
      register_handler(Range, RangeHandler.new(self))
      register_handler(Relation, RelationHandler.new)
      register_handler(Array, ArrayHandler.new(self))
      register_handler(Set, ArrayHandler.new(self))
    end

    def build_from_hash(attributes, &block)
      attributes = convert_dot_notation_to_hash(attributes)
      expand_from_hash(attributes, &block)
    end

    def self.references(attributes)
      attributes.each_with_object([]) do |(key, value), result|
        if value.is_a?(Hash)
          result << key
        elsif key.include?(".")
          result << key.split(".").first
        end
      end
    end

    # Define how a class is converted to Arel nodes when passed to +where+.
    # The handler can be any object that responds to +call+, and will be used
    # for any value that +===+ the class given. For example:
    #
    #     MyCustomDateRange = Struct.new(:start, :end)
    #     handler = proc do |column, range|
    #       Arel::Nodes::Between.new(column,
    #         Arel::Nodes::And.new([range.start, range.end])
    #       )
    #     end
    #     ActiveRecord::PredicateBuilder.new("users").register_handler(MyCustomDateRange, handler)
    def register_handler(klass, handler)
      @handlers.unshift([klass, handler])
    end

    def [](attr_name, value, operator = nil)
      build(table.arel_table[attr_name], value, operator)
    end

    def build(attribute, value, operator = nil)
      value = value.id if value.is_a?(Base)
      if operator ||= table.type(attribute.name).force_equality?(value) && :eq
        bind = build_bind_attribute(attribute.name, value)
        attribute.public_send(operator, bind)
      else
        handler_for(value).call(attribute, value)
      end
    end

    def build_bind_attribute(column_name, value)
      attr = Relation::QueryAttribute.new(column_name, value, table.type(column_name))
      Arel::Nodes::BindParam.new(attr)
    end

    def resolve_arel_attribute(table_name, column_name, &block)
      table.associated_table(table_name, &block).arel_table[column_name]
    end

    protected
      def expand_from_hash(attributes, &block)
        return ["1=0"] if attributes.empty?

        attributes.flat_map do |key, value|
          if value.is_a?(Hash) && !table.has_column?(key)
            table.associated_table(key, &block)
              .predicate_builder.expand_from_hash(value.stringify_keys)
          elsif table.associated_with?(key)
            # Find the foreign key when using queries such as:
            # Post.where(author: author)
            #
            # For polymorphic relationships, find the foreign key and type:
            # PriceEstimate.where(estimate_of: treasure)
            associated_table = table.associated_table(key)
            if associated_table.polymorphic_association?
              case value.is_a?(Array) ? value.first : value
              when Base, Relation
                value = [value] unless value.is_a?(Array)
                klass = PolymorphicArrayValue
              end
            elsif associated_table.through_association?
              next associated_table.predicate_builder.expand_from_hash(
                associated_table.join_foreign_key => value
              )
            end

            klass ||= AssociationQueryValue
            queries = klass.new(associated_table, value).queries.map! do |query|
              expand_from_hash(query)
            end

            grouping_queries(queries)
          elsif table.aggregated_with?(key)
            mapping = table.reflect_on_aggregation(key).mapping
            values = value.nil? ? [nil] : Array.wrap(value)
            if mapping.length == 1 || values.empty?
              column_name, aggr_attr = mapping.first
              values = values.map do |object|
                object.respond_to?(aggr_attr) ? object.public_send(aggr_attr) : object
              end
              self[column_name, values]
            else
              queries = values.map do |object|
                mapping.map do |field_attr, aggregate_attr|
                  self[field_attr, object.try!(aggregate_attr)]
                end
              end

              grouping_queries(queries)
            end
          else
            self[key, value]
          end
        end
      end

    private
      attr_reader :table

      def grouping_queries(queries)
        if queries.one?
          queries.first
        else
          queries.map! { |query| query.reduce(&:and) }
          queries = queries.reduce { |result, query| Arel::Nodes::Or.new(result, query) }
          Arel::Nodes::Grouping.new(queries)
        end
      end

      def convert_dot_notation_to_hash(attributes)
        dot_notation = attributes.select do |k, v|
          k.include?(".") && !v.is_a?(Hash)
        end

        dot_notation.each_key do |key|
          table_name, column_name = key.split(".")
          value = attributes.delete(key)
          attributes[table_name] ||= {}

          attributes[table_name] = attributes[table_name].merge(column_name => value)
        end

        attributes
      end

      def handler_for(object)
        @handlers.detect { |klass, _| klass === object }.last
      end
  end
end