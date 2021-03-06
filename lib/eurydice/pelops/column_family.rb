# encoding: utf-8

module Eurydice
  module Pelops
    class ColumnFamily
      include ExceptionHelpers
      include ByteHelpers
      include ConsistencyLevelHelpers
    
      attr_reader :name, :keyspace
    
      def initialize(keyspace, name)
        @keyspace, @name = keyspace, name
      end
    
      def definition(reload=false)
        thrift_exception_handler do
          @definition = nil if reload
          @definition ||= @keyspace.definition(true)[:column_families][@name]
        end
      end
    
      def exists?
        !!definition(true)
      end
    
      def create!(options={})
        thrift_exception_handler do
          @keyspace.column_family_manger.add_column_family(Cassandra::CfDef.from_h(options.merge(:keyspace => @keyspace.name, :name => @name)))
        end
      end
    
      def drop!
        thrift_exception_handler do
          @keyspace.column_family_manger.drop_column_family(@name)
        end
      end
    
      def truncate!
        thrift_exception_handler do
          @keyspace.column_family_manger.truncate_column_family(@name)
        end
      end
    
      def delete(row_key, options={})
        thrift_exception_handler do
          deletor = @keyspace.create_row_deletor
          deletor.delete_row(@name, row_key, get_cl(options))
        end
      end
    
      def delete_column(row_key, column_key, options={})
        @keyspace.batch(options) do |b|
          b.delete_column(@name, row_key, column_key)
        end
      end
    
      def delete_columns(row_key, column_keys, options={})
        @keyspace.batch(options) do |b|
          b.delete_columns(@name, row_key, column_keys)
        end
      end
    
      def update(row_key, properties, options={})
        @keyspace.batch(options) do |b|
          b.update(@name, row_key, properties, options)
        end
      end
      alias_method :insert, :update
    
      def increment(row_key, column_key, amount=1, options={})
        thrift_exception_handler do
          mutator = @keyspace.create_mutator
          mutator.write_counter_column(@name, to_pelops_bytes(row_key), to_pelops_bytes(column_key), amount)
          mutator.execute(get_cl(options))
        end
      end
      alias_method :inc, :increment
      alias_method :incr, :increment
      alias_method :increment_column, :increment
    
      def key?(row_key, options={})
        thrift_exception_handler do
          selector = @keyspace.create_selector
          predicate = Cassandra::SlicePredicate.new
          count = selector.get_column_count(@name, row_key, get_cl(options))
          count > 0
        end
      end
      alias_method :row_exists?, :key?
    
      def get(row_or_rows, options={})
        case row_or_rows
        when Array then get_multi(row_or_rows, options)
        else get_single(row_or_rows, options)
        end
      end
      alias_method :get_row, :get
      alias_method :get_rows, :get
      
      def get_column(row_key, column_key, options={})
        thrift_exception_handler do
          selector = @keyspace.create_selector
          if counter_columns?
            column = selector.get_counter_column_from_row(@name, to_pelops_bytes(row_key), to_pelops_bytes(column_key), get_cl(options))
            column.get_value
          else
            column =selector.get_column_from_row(@name, to_pelops_bytes(row_key), to_pelops_bytes(column_key), get_cl(options))
            byte_array_to_s(column.get_value)
          end
        end
      rescue NotFoundError => e
        nil
      end
      
      def each_column(row_key, options={}, &block)
        new_options = options.dup
        new_options[:from_column] = options.delete(:start_beyond) if options.key?(:start_beyond)
        new_options[:max_column_count] = options.delete(:batch_size) if options.key?(:batch_size)
        enum = ColumnEnumerator.new(self, row_key, new_options)
        if block_given?
          enum.each(&block)
        else
          enum
        end
      end
      
      def get_column_count(row_key, options={})
        thrift_exception_handler do
          selector = @keyspace.create_selector
          column_predicate = create_column_predicate(options)
          selector.get_column_count(@name, to_pelops_bytes(row_key), column_predicate, get_cl(options))
        end
      end
      
      def get_indexed(column_key, operator, value, options={})
        thrift_exception_handler do
          selector = @keyspace.create_selector
          op = Cassandra::INDEX_OPERATORS[operator]
          max_rows = options.fetch(:max_row_count, 20)
          types = options[:validations] || {}
          key_type = options[:comparator]
          raise ArgumentError, %(Unsupported index operator: "#{operator}") unless op
          index_expression = selector.class.new_index_expression(to_pelops_bytes(column_key, key_type), op, to_pelops_bytes(value, types[column_key]))
          index_clause = selector.class.new_index_clause(empty_pelops_bytes, max_rows, index_expression)
          column_predicate = create_column_predicate(options)
          rows = selector.get_indexed_columns(@name, index_clause, column_predicate, get_cl(options))
          rows_to_h(rows, options)
        end
      end
      
      def batch(options={})
        batch = Batch.new(@name, @keyspace)
        if block_given?
          yield batch
          batch.execute!(options)
        end
        nil
      end
      
    private
    
      EMPTY_STRING = ''.freeze
    
      def counter_columns?
        @is_counter_cf ||= definition[:default_validation_class] == Cassandra::MARSHAL_TYPES[:counter]
      end
    
      def get_single(row_key, options={})
        thrift_exception_handler do
          selector = @keyspace.create_selector
          column_predicate = create_column_predicate(options)
          if counter_columns?
            columns = selector.get_counter_columns_from_row(@name, to_pelops_bytes(row_key), column_predicate, get_cl(options))
          else
            columns = selector.get_columns_from_row(@name, to_pelops_bytes(row_key), column_predicate, get_cl(options))
          end
          columns_to_h(columns, options)
        end
      end
    
      def get_multi(row_keys, options={})
        thrift_exception_handler do
          selector = @keyspace.create_selector
          column_predicate = create_column_predicate(options)
          byte_row_keys = row_keys.map { |rk| to_pelops_bytes(rk) }
          if counter_columns?
            rows = selector.get_counter_columns_from_rows(@name, byte_row_keys, column_predicate, get_cl(options))
          else
            rows = selector.get_columns_from_rows(@name, byte_row_keys, column_predicate, get_cl(options))
          end
          rows_to_h(rows, options)
        end
      end
      
      def create_column_predicate(options)
        max_column_count = options.fetch(:max_column_count, java.lang.Integer::MAX_VALUE)
        reversed = options.fetch(:reversed, false)
        if options.key?(:from_column)
          raise ArgumentError, %(You can set either :columns or :from_column, but not both) if options.key?(:columns)
          options[:columns] = options[:from_column]..EMPTY_STRING
        end
        case options[:columns]
        when Range
          ::Pelops::Selector.new_columns_predicate(to_pelops_bytes(options[:columns].begin), to_pelops_bytes(options[:columns].end), reversed, max_column_count)
        when Array
          ::Pelops::Selector.new_columns_predicate(*options[:columns].map { |col| to_pelops_bytes(col) })
        else
          ::Pelops::Selector.new_columns_predicate_all(reversed, max_column_count)
        end
      end
    
      def rows_to_h(rows, options)
        rows.reduce({}) do |acc, (row_key, columns)|
          columns_h = columns_to_h(columns, options)
          acc[pelops_bytes_to_s(row_key)] = columns_h if columns_h && !columns_h.empty?
          acc
        end
      end
  
      def columns_to_h(columns, options)
        if columns.empty?
          nil
        else
          columns.reduce({}) do |acc, column|
            key, value = column_to_kv(column, options)
            acc[key] = value
            acc
          end
        end
      end
      
      def column_to_kv(column, options)
        types = options[:validations] || {}
        key_type = options[:comparator]
        key = byte_array_to_s(column.get_name, key_type)
        value = if counter_columns? 
          then column.get_value 
          else byte_array_to_s(column.get_value, types[key])
        end
        return key, value
      end
    end
  end
end
