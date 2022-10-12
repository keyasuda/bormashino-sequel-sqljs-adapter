require 'sinatra/base'

class App < Sinatra::Base
  set :protection, false

  get '/' do
    # rubocop:disable Lint/RedundantRequireStatement?
    require 'thread'
    class Thread
      @@current = {}
      def @@current.status
        'running'
      end

      def self.current
        @@current
      end
    end
    # rubocop:enable Lint/RedundantRequireStatement
    require 'sequel'
    require_relative 'sqljs'
    Sequel.single_threaded = true
    p JS.global[:database].call(:exec, 'select * from test;').to_rb
    @db = Sequel.connect('sqljs://database')
    p @db
    p @db[:test].where(col1: 1).each { |r| p r }

    @db.create_table :items do
      primary_key :id
      String :name
      Float :price
    end

    items = @db[:items]
    items.insert(name: 'abc', price: 1.01)
    items.insert(name: 'def', price: 2.32)
    items.insert(name: 'ghi', price: 4.97)

    p ret = items.where(name: 'def')
    ret.each { |r| p r }

    p items.where(name: 'def').delete
    p items.count

    require 'rspec/core'
    # ret = RSpec::Core::Runner.run(['src/spec/sqljs_spec.rb:527'])
    @err = StringIO.new('')
    @out = StringIO.new('')
    @ret = RSpec::Core::Runner.run(['src/spec/sqljs_spec.rb'], @err, @out)

    erb :index
  end
end
