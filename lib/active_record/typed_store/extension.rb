require 'active_record/typed_store/column'
require 'active_record/typed_store/dsl'

module ActiveRecord::TypedStore
  AR_VERSION = Gem::Version.new(ActiveRecord::VERSION::STRING)
  IS_AR_3_2 = AR_VERSION < Gem::Version.new('4.0')
  IS_AR_4_1 = AR_VERSION >= Gem::Version.new('4.1.0.beta')

  module Extension
    extend ActiveSupport::Concern

    included do
      class_attribute :typed_stores, instance_accessor: false
      class_attribute :typed_store_attributes, instance_accessor: false
    end

    module ClassMethods

      def typed_store(store_attribute, options={}, &block)
        dsl = DSL.new(&block)

        if hstore?(store_attribute)
          store_accessor(store_attribute, dsl.column_names)
        else
          store(store_attribute, options.merge(accessors: dsl.column_names))
        end

        register_typed_store_columns(store_attribute, dsl.columns)
        super(store_attribute, dsl) if defined?(super)

        dsl.column_names.each { |c| define_store_attribute_queries(store_attribute, c) }

        dsl
      end

      def define_attribute_methods
        super
        define_typed_store_attribute_methods
      end

      private

      def register_typed_store_columns(store_attribute, columns)
        self.typed_stores ||= {}
        self.typed_store_attributes ||= {}
        typed_stores[store_attribute] ||= {}
        typed_stores[store_attribute].merge!(columns.index_by(&:name))
        typed_store_attributes.merge!(columns.index_by { |c| c.name.to_s })
      end

      def define_typed_store_attribute_methods
        return unless typed_store_attributes
        typed_store_attributes.keys.each do |attribute|
          define_virtual_attribute_method(attribute)
        end
      end

      def hstore?(store_attribute)
        columns_hash[store_attribute.to_s].try(:type) == :hstore
      end

      def create_time_zone_conversion_attribute?(name, column)
        column ||= typed_store_attributes[name]
        super(name, column)
      end

      def define_store_attribute_queries(store_attribute, column_name)
        define_method("#{column_name}?") do
          query_store_attribute(store_attribute, column_name)
        end
      end

    end

    def reload(*)
      reload_stores!
      super
    end

    protected

    def write_store_attribute(store_attribute, key, value)
      column = store_column(store_attribute, key)
      if column.try(:type) == :datetime && self.class.time_zone_aware_attributes && value.respond_to?(:in_time_zone)
        value = value.in_time_zone
      end

      previous_value = read_store_attribute(store_attribute, key)
      casted_value = cast_store_attribute(store_attribute, key, value)
      attribute_will_change!(key.to_s) if casted_value != previous_value
      super(store_attribute, key, casted_value)
    end

    private

    def cast_store_attribute(store_attribute, key, value)
      column = store_column(store_attribute, key)
      column ? column.cast(value) : value
    end

    def store_column(store_attribute, key)
      store = store_columns(store_attribute)
      store && store[key]
    end

    def store_columns(store_attribute)
      self.class.typed_stores.try(:[], store_attribute)
    end

    def if_store_uninitialized(store_attribute)
      initialized = "@_#{store_attribute}_initialized"
      unless instance_variable_get(initialized)
        yield
        instance_variable_set(initialized, true)
      end
    end

    def reload_stores!
      return unless self.class.typed_stores
      self.class.typed_stores.keys.each do |store_attribute|
        instance_variable_set("@_#{store_attribute}_initialized", false)
      end
    end

    def initialize_store_attribute(store_attribute)
      store = defined?(super) ? super : send(store_attribute)
      store.tap do |store|
        if_store_uninitialized(store_attribute) do
          if columns = store_columns(store_attribute)
            initialize_store(store, columns.values)
          end
        end
      end
    end

    def initialize_store(store, columns)
      columns.each do |column|
        if store.has_key?(column.name)
          store[column.name] = column.cast(store[column.name])
        else
          store[column.name] = column.default if column.has_default?
        end
      end
      store
    end

    # heavilly inspired from ActiveRecord::Base#query_attribute
    def query_store_attribute(store_attribute, key)
      value = read_store_attribute(store_attribute, key)

      case value
      when true        then true
      when false, nil  then false
      else
        column = store_column(store_attribute, key)

        if column.number?
          !value.zero?
        else
          !value.blank?
        end
      end
    end

  end

  require 'active_record/typed_store/ar_32_fallbacks' if IS_AR_3_2
  require 'active_record/typed_store/ar_41_fallbacks' if IS_AR_4_1
  unless IS_AR_3_2
    ActiveModel::AttributeMethods::ClassMethods.send(:alias_method, :define_virtual_attribute_method, :define_attribute_method)
  end

end
