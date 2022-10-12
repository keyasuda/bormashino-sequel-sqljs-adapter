require_relative 'shared/sqljs'

module Sequel
  module Sqljs
    class Wrapper
      class Error < StandardError
      end

      def initialize(jsobject)
        @db = jsobject
      end

      def exec(sql)
        columns = @db.call(:prepareGetColumnNames, sql).to_rb
        ret = @db.call(:exec, sql).to_rb

        if ret.is_a?(Hash) && ret['type'] == 'exception'
          err = Error.new(ret['message']).tap do |e|
            e.set_backtrace(ret['stack'])
          end

          raise err
        end

        { result: ret, columns: }
      end

      def get_rows_modified
        @db.call(:getRowsModified).to_rb
      end
    end

    FALSE_VALUES = (%w'0 false f no n'.each(&:freeze) + [0]).freeze

    blob = Object.new
    def blob.call(s)
      Sequel::SQL::Blob.new(s.to_s)
    end

    boolean = Object.new
    def boolean.call(s)
      s = s.downcase if s.is_a?(String)
      !FALSE_VALUES.include?(s)
    end

    date = Object.new
    def date.call(s)
      case s
      when String
        Sequel.string_to_date(s)
      when Integer
        Date.jd(s)
      when Float
        Date.jd(s.to_i)
      else
        raise Sequel::Error, "unhandled type when converting to date: #{s.inspect} (#{s.class.inspect})"
      end
    end

    integer = Object.new
    def integer.call(s)
      s ? s.to_i : nil
    end

    float = Object.new
    def float.call(s)
      s.to_f
    end

    numeric = Object.new
    def numeric.call(s)
      s = s.to_s unless s.is_a?(String)
      begin
        BigDecimal(s)
      rescue StandardError
        s
      end
    end

    time = Object.new
    def time.call(s)
      case s
      when String
        Sequel.string_to_time(s)
      when Integer
        Sequel::SQLTime.create(s / 3600, (s % 3600) / 60, s % 60)
      when Float
        s, f = s.divmod(1)
        Sequel::SQLTime.create(s / 3600, (s % 3600) / 60, s % 60, (f * 1000000).round)
      else
        raise Sequel::Error, "unhandled type when converting to date: #{s.inspect} (#{s.class.inspect})"
      end
    end

    # Hash with string keys and callable values for converting SQLite types.
    sqlite_types = {}
    {
      %w[date] => date,
      %w[time] => time,
      %w[bit bool boolean] => boolean,
      %w[integer smallint mediumint int bigint] => integer,
      %w[numeric decimal money] => numeric,
      %w[float double real dec fixed] + ['double precision'] => float,
      %w[blob] => blob,
    }.each do |k, v|
      k.each { |n| sqlite_types[n] = v }
    end
    SQLITE_TYPES = sqlite_types

    class Database < Sequel::Database
      include ::Sequel::Sqljs::DatabaseMethods

      set_adapter_scheme :sqljs

      # Mimic the file:// uri, by having 2 preceding slashes specify a relative
      # path, and 3 preceding slashes specify an absolute path.
      def self.uri_to_options(uri) # :nodoc:
        { database: uri.host.nil? && uri.path == '/' ? nil : "#{uri.host}#{uri.path}" }
      end

      private_class_method :uri_to_options

      # The conversion procs to use for this database
      attr_reader :conversion_procs

      def initialize(opts = OPTS)
        super
        @allow_regexp = typecast_value_boolean(opts[:setup_regexp_function])
      end

      # Connect to the database. Since SQLite is a file based database,
      # available options are limited:
      #
      # :database :: database name (filename or ':memory:' or file: URI)
      # :readonly :: open database in read-only mode; useful for reading
      #              static data that you do not want to modify
      # :timeout :: how long to wait for the database to be available if it
      #             is locked, given in milliseconds (default is 5000)
      def connect(server)
        opts = server_opts(server)
        # db = ::SQLite3::Database.new(opts[:database].to_s, sqlite3_opts)
        db = Wrapper.new(JS.global[opts[:database].to_sym])

        # db.busy_timeout(typecast_value_integer(opts.fetch(:timeout, 5000)))

        # db.extended_result_codes = true

        connection_pragmas.each { |s| log_connection_yield(s, db) { db.exec(s) } }

        if typecast_value_boolean(opts[:setup_regexp_function])
          db.create_function('regexp', 2) do |func, regexp_str, string|
            func.result = Regexp.new(regexp_str).match(string) ? 1 : 0
          end
        end

        class << db
          attr_reader :prepared_statements
        end
        db.instance_variable_set(:@prepared_statements, {})

        db
      end

      # Whether this Database instance is setup to allow regexp matching.
      # True if the :setup_regexp_function option was passed when creating the Database.
      def allow_regexp?
        @allow_regexp
      end

      # Disconnect given connections from the database.
      def disconnect_connection(c)
        c.prepared_statements.each_value { |v| v.first.close }
        c.close
      end

      # Run the given SQL with the given arguments and yield each row.
      def execute(sql, opts = OPTS, &)
        _execute(:select, sql, opts, &)
      end

      # Run the given SQL with the given arguments and return the number of changed rows.
      def execute_dui(sql, opts = OPTS)
        _execute(:update, sql, opts)
      end

      # Drop any prepared statements on the connection when executing DDL.  This is because
      # prepared statements lock the table in such a way that you can't drop or alter the
      # table while a prepared statement that references it still exists.
      def execute_ddl(sql, opts = OPTS)
        synchronize(opts[:server]) do |conn|
          conn.prepared_statements.each_value { |cps, _s| cps.close }
          conn.prepared_statements.clear
          super
        end
      end

      def execute_insert(sql, opts = OPTS)
        _execute(:insert, sql, opts)
      end

      def freeze
        @conversion_procs.freeze
        super
      end

      # Handle Integer and Float arguments, since SQLite can store timestamps as integers and floats.
      def to_application_timestamp(s)
        case s
        when String
          super
        when Integer
          super(Time.zone.at(s).to_s)
        when Float
          super(DateTime.jd(s).to_s)
        else
          raise Sequel::Error, "unhandled type when converting to : #{s.inspect} (#{s.class.inspect})"
        end
      end

      private

      def adapter_initialize
        @conversion_procs = SQLITE_TYPES.dup
        @conversion_procs['datetime'] = @conversion_procs['timestamp'] = method(:to_application_timestamp)
        set_integer_booleans
      end

      # Yield an available connection.  Rescue
      # any SQLite3::Exceptions and turn them into DatabaseErrors.
      def _execute(type, sql, opts, &)
        synchronize(opts[:server]) do |conn|
          return execute_prepared_statement(conn, type, sql, opts, &) if sql.is_a?(Symbol)

          log_args = opts[:arguments]
          args = {}
          opts.fetch(:arguments, OPTS).each { |k, v| args[k] = prepared_statement_argument(v) }
          case type
          when :select
            log_connection_yield(sql, conn, log_args) do
              result = conn.exec(sql)
              # fetch table names
              tables = conn.exec("select name from sqlite_master where type='table'")[:result].first['values']
              target_table = tables.map(&:first).find { |n| sql.include?("\`#{n}\`") }
              if target_table
                types_result = conn.exec("pragma table_info('#{target_table}')")
                result[:types] = types_result[:result].first['values'].to_h { |e| [e[1], e[2]] }
              end

              yield result
            end
          when :insert
            log_connection_yield(sql, conn, log_args) { conn.exec(sql) }
            conn.exec('select last_insert_rowid()')[:result].first['values'].first.first
          when :update
            log_connection_yield(sql, conn, log_args) { conn.exec(sql) }
            conn.get_rows_modified
          end
        end
      rescue StandardError => e
        raise_error(e)
      end

      # The SQLite adapter does not need the pool to convert exceptions.
      # Also, force the max connections to 1 if a memory database is being
      # used, as otherwise each connection gets a separate database.
      def connection_pool_default_options
        o = super.dup
        # Default to only a single connection if a memory database is used,
        # because otherwise each connection will get a separate database
        o[:max_connections] = 1 if @opts[:database] == ':memory:' || blank_object?(@opts[:database])
        o
      end

      def prepared_statement_argument(arg)
        case arg
        when Date, DateTime, Time
          literal(arg)[1...-1]
        when SQL::Blob
          arg.to_blob
        when true, false
          if integer_booleans
            arg ? 1 : 0
          else
            literal(arg)[1...-1]
          end
        else
          arg
        end
      end

      # Execute a prepared statement on the database using the given name.
      def execute_prepared_statement(conn, type, name, opts, &block)
        ps = prepared_statement(name)
        sql = ps.prepared_sql
        args = opts[:arguments]
        ps_args = {}
        args.each { |k, v| ps_args[k] = prepared_statement_argument(v) }
        if cpsa = conn.prepared_statements[name]
          cps, cps_sql = cpsa
          if cps_sql != sql
            cps.close
            cps = nil
          end
        end
        unless cps
          cps = log_connection_yield("PREPARE #{name}: #{sql}", conn) { conn.prepare(sql) }
          conn.prepared_statements[name] = [cps, sql]
        end
        log_sql = String.new
        log_sql << "EXECUTE #{name}"
        if ps.log_sql
          log_sql << ' ('
          log_sql << sql
          log_sql << ')'
        end
        if block
          log_connection_yield(log_sql, conn, args) { cps.execute(ps_args, &block) }
        else
          log_connection_yield(log_sql, conn, args) { cps.execute!(ps_args) { |r| } }
          case type
          when :insert
            conn.last_insert_row_id
          when :update
            conn.changes
          end
        end
      end

      # SQLite3 raises ArgumentError in addition to SQLite3::Exception in
      # some cases, such as operations on a closed database.
      def database_error_classes
        [::Sequel::Sqljs::Wrapper::Error, ArgumentError]
      end

      def dataset_class_default
        Dataset
      end

      # Support SQLite exception codes if ruby-sqlite3 supports them.
      def sqlite_error_code(exception)
        exception.code if exception.respond_to?(:code)
      end

      def connection_execute_method
        :exec
      end
    end

    class Dataset < Sequel::Dataset
      include ::Sequel::Sqljs::DatasetMethods

      module ArgumentMapper
        include Sequel::Dataset::ArgumentMapper

        protected

        # Return a hash with the same values as the given hash,
        # but with the keys converted to strings.
        def map_to_prepared_args(hash)
          args = {}
          hash.each { |k, v| args[k.to_s.gsub('.', '__')] = v }
          args
        end

        private

        # SQLite uses a : before the name of the argument for named
        # arguments.
        def prepared_arg(k)
          LiteralString.new("#{prepared_arg_placeholder}#{k.to_s.gsub('.', '__')}")
        end
      end

      BindArgumentMethods = prepared_statements_module(:bind, ArgumentMapper)
      PreparedStatementMethods = prepared_statements_module(:prepare, BindArgumentMethods)

      # Support regexp functions if using :setup_regexp_function Database option.
      def complex_expression_sql_append(sql, op, args)
        case op
        when :~, :!~, :'~*', :'!~*'
          return super unless supports_regexp?

          case_insensitive = %i[~* !~*].include?(op)
          sql << 'NOT ' if %i[!~ !~*].include?(op)
          sql << '('
          sql << 'LOWER(' if case_insensitive
          literal_append(sql, args[0])
          sql << ')' if case_insensitive
          sql << ' REGEXP '
          sql << 'LOWER(' if case_insensitive
          literal_append(sql, args[1])
          sql << ')' if case_insensitive
          sql << ')'
        else
          super
        end
      end

      def fetch_rows(sql, &)
        execute(sql) do |result|
          columns = result[:columns].map(&:to_sym)
          type_procs =
            if types = result[:types]
              cps = db.conversion_procs
              columns.map { |n| types[n.to_s] }.map { |t| cps[base_type_name(t)] }
            end

          result[:result].each do |r|
            r['values'].map do |values|
              values.map.with_index do |v, i|
                value =
                  if type_procs && type_proc = type_procs[i]
                    type_proc.call(v)
                  else
                    v
                  end
                [columns[i].to_sym, value]
              end.to_h
            end.each(&)
          end
          self.columns = columns
        end
      end

      # Support regexp if using :setup_regexp_function Database option.
      def supports_regexp?
        db.allow_regexp?
      end

      private

      # The base type name for a given type, without any parenthetical part.
      def base_type_name(t)
        (t =~ /^(.*?)\(/ ? Regexp.last_match(1) : t).downcase if t
      end

      # Quote the string using the adapter class method.
      def literal_string_append(sql, v)
        # sql << "'" << ::SQLite3::Database.quote(v) << "'"
        sql << "'" << v.gsub(/'/, "''") << "'"
      end

      def bound_variable_modules
        [BindArgumentMethods]
      end

      def prepared_statement_modules
        [PreparedStatementMethods]
      end

      # SQLite uses a : before the name of the argument as a placeholder.
      def prepared_arg_placeholder
        ':'
      end
    end
  end
end
