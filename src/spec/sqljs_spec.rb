SEQUEL_ADAPTER_TEST = :sqljs
DB = Sequel.connect('sqljs://database')

require_relative 'spec_helper'

describe 'An SQL.JS database' do
  before do
    @db = DB
  end

  after do
    @db.drop_table?(:fk)
    @db.use_timestamp_timezones = false
    Sequel.datetime_class = Time
  end

  it 'supports casting to Date by using the date function' do
    expect(@db.get(Sequel.cast('2012-10-20 11:12:13', Date))).to eq '2012-10-20'
  end

  it 'supports casting to Time or DateTime by using the datetime function' do
    expect(@db.get(Sequel.cast('2012-10-20', Time))).to eq '2012-10-20 00:00:00'
    expect(@db.get(Sequel.cast('2012-10-20', DateTime))).to eq '2012-10-20 00:00:00'
  end

  it 'provides the SQLite version as an integer' do
    expect(@db.sqlite_version).to be_kind_of(Integer)
  end

  it 'supports dropping noncomposite unique constraint' do
    @db.create_table(:fk) do
      primary_key :id
      String :name, null: false, unique: true
    end
    # Find name of unique index, as SQLite does not use a given constraint name
    name_constraint = @db.indexes(:fk).find do |_, properties|
      properties[:unique] == true && properties[:columns] == [:name]
    end || [:missing]
    @db.alter_table(:fk) do
      drop_constraint(name_constraint.first, type: :unique)
    end
    @db[:fk].insert(name: 'a')
    @db[:fk].insert(name: 'a')
  end

  it 'keeps composite unique constraint when changing a column default' do
    @db.create_table(:fk) do
      Bignum :id, null: false, unique: true
      Bignum :another_id, null: false
      String :name, size: 50, null: false
      String :test

      unique %i[another_id name], name: :fk_uidx
    end
    @db.alter_table(:fk) do
      set_column_default :test, 'test'
    end
    @db[:fk].insert(id: 1, another_id: 2, name: 'a')
    @db[:fk].insert(id: 2, another_id: 3, name: 'a')
    @db[:fk].insert(id: 3, another_id: 2, name: 'b')
    expect { @db[:fk].insert(id: 4, another_id: 2, name: 'a') }.to raise_error Sequel::ConstraintViolation
  end

  it 'keeps composite primary key when changing a column default' do
    @db.create_table(:fk) do
      Bignum :id, null: false, unique: true
      Bignum :another_id, null: false
      String :name, size: 50, null: false
      String :test

      primary_key %i[another_id name]
    end
    @db.alter_table(:fk) do
      set_column_default :test, 'test'
    end
    @db[:fk].insert(id: 1, another_id: 2, name: 'a')
    @db[:fk].insert(id: 2, another_id: 3, name: 'a')
    @db[:fk].insert(id: 3, another_id: 2, name: 'b')
    expect { @db[:fk].insert(id: 4, another_id: 2, name: 'a') }.to raise_error Sequel::ConstraintViolation
  end

  it 'allows setting current_timestamp_utc to keep CURRENT_* in UTC' do
    v = @db.current_timestamp_utc
    @db.current_timestamp_utc = true
    expect(Time.parse(@db.get(Sequel::CURRENT_TIMESTAMP)).strftime('%Y%m%d%H%M')).to eq Time.now.utc.strftime('%Y%m%d%H%M')
    expect(Time.parse(@db.get(Sequel::CURRENT_DATE)).strftime('%Y%m%d')).to eq Time.now.utc.strftime('%Y%m%d')
    expect(Time.parse(@db.get(Sequel::CURRENT_TIME)).strftime('%H%M')).to eq Time.now.utc.strftime('%H%M')
  ensure
    @db.current_timestamp_utc = v
  end

  it 'supports a use_timestamp_timezones setting' do
    @db.use_timestamp_timezones = true
    @db.create_table!(:fk) { Time :time }
    @db[:fk].insert(Time.now)
    expect(@db[:fk].get(Sequel.cast(:time, String))).to match(/[-+]\d\d\d\d\z/)
    @db.use_timestamp_timezones = false
    @db[:fk].delete
    @db[:fk].insert(Time.now)
    expect(@db[:fk].get(Sequel.cast(:time, String))).not_to match(/[-+]\d\d\d\d\z/)
  end

  it 'provides a list of existing tables' do
    @db.drop_table?(:fk)
    expect(@db.tables).to be_kind_of(Array)
    expect(@db.tables).not_to include(:fk)
    @db.create_table!(:fk) { String :name }
    expect(@db.tables).to include(:fk)
  end

  specify 'should support timestamps and datetimes and respect datetime_class', [:jdbc] do
    @db.create_table!(:fk) {
      timestamp :t
      datetime :d
    }
    @db.use_timestamp_timezones = true
    t1 = Time.at(1)
    @db[:fk].insert(t: t1, d: t1)
    expect(@db[:fk].map(:t)).to eq [t1]
    expect(@db[:fk].map(:d)).to eq [t1]
    Sequel.datetime_class = DateTime
    t2 = Sequel.string_to_datetime(t1.iso8601)
    expect(@db[:fk].map(:t)).to eq [t2]
    expect(@db[:fk].map(:d)).to eq [t2]
  end

  it 'supports sequential primary keys' do
    @db.create_table!(:fk) {
      primary_key :id
      text :name
    }
    @db[:fk].insert(name: 'abc')
    @db[:fk].insert(name: 'def')
    @db[:fk].insert(name: 'ghi')
    expect(@db[:fk].order(:name).all).to eq [
      { id: 1, name: 'abc' },
      { id: 2, name: 'def' },
      { id: 3, name: 'ghi' },
    ]
  end

  it 'correctlies parse the schema' do
    @db.create_table!(:fk) { timestamp :t }
    h = { generated: false, type: :datetime, allow_null: true, default: nil, ruby_default: nil, db_type: 'timestamp', primary_key: false }
    h.delete(:generated) if @db.sqlite_version < 33100
    expect(@db.schema(:fk, reload: true)).to eq [[:t, h]]
  end

  it 'handles and return BigDecimal values for numeric columns' do
    DB.create_table!(:fk) { numeric :d }
    d = DB[:fk]
    d.insert(d: BigDecimal('80.0'))
    d.insert(d: BigDecimal('NaN'))
    d.insert(d: BigDecimal('Infinity'))
    d.insert(d: BigDecimal('-Infinity'))
    ds = d.all
    expect(ds.shift).to eq(d: BigDecimal('80.0'))
    expect(ds.map { |x| x[:d].to_s }).to eq %w[NaN Infinity -Infinity]
    DB
  end

  if DB.sqlite_version >= 33100
    it 'supports creating and parsing generated columns' do
      @db.create_table!(:fk) {
        Integer :a
        Integer :b
        Integer :c, generated_always_as: (Sequel[:a] * 2) + :b + 1
        Integer :d, generated_always_as: (Sequel[:a] * 2) + :b + 2, generated_type: :stored
        Integer :e, generated_always_as: (Sequel[:a] * 2) + :b + 3, generated_type: :virtual
      }
      @db[:fk].insert(a: 100, b: 10)
      expect(@db[:fk].select_order_map(%i[a b c d e])).to eq [[100, 10, 211, 212, 213]]

      # Generated columns do not show up in schema on SQLite 3.37.0 (or maybe 3.38.0)
      expected = DB.sqlite_version >= 33700 ? [false, false] : [false, false, true, true, true]
      expect(@db.schema(:fk).map { |_, v| v[:generated] }).to eq expected
    end
  end
end

xdescribe 'SQLite temporary views' do
  before do
    @db = DB
    begin
      @db.drop_view(:items)
    rescue StandardError
      nil
    end
    @db.create_table!(:items) { Integer :number }
    @db[:items].insert(10)
    @db[:items].insert(20)
  end

  after do
    @db.drop_table?(:items)
  end

  it 'is supported' do
    @db.create_view(:items_view, @db[:items].where(number: 10), temp: true)
    expect(@db[:items_view].map(:number)).to eq [10]
  end
end

if DB.sqlite_version >= 30803
  describe 'SQLite VALUES support' do
    before do
      @db = DB
    end

    it 'creates a dataset using the VALUES clause via #values' do
      expect(@db.values([[1, 2], [3, 4]]).map(%i[column1 column2])).to eq [[1, 2], [3, 4]]
    end

    it 'supports VALUES with unions' do
      expect(@db.values([[1]]).union(@db.values([[3]])).map(&:values).map(&:first)).to eq [1, 3]
    end

    it 'supports VALUES in CTEs' do
      expect(@db[:a].cross_join(:b).with(:a, @db.values([[1, 2]]), args: %i[c1 c2]).with(:b, @db.values([[3, 4]]),
                                                                                         args: %i[c3 c4]).map(%i[c1 c2 c3 c4])).to eq [[1, 2, 3, 4]]
    end
  end
end

if DB.adapter_scheme == :sqlite
  describe 'SQLite type conversion' do
    before do
      @db = DB
      @integer_booleans = @db.integer_booleans
      @db.integer_booleans = true
      @ds = @db[:items]
      @db.drop_table?(:items)
    end

    after do
      @db.integer_booleans = @integer_booleans
      Sequel.datetime_class = Time
      @db.drop_table?(:items)
    end

    it 'handles integers in boolean columns' do
      @db.create_table(:items) { TrueClass :a }
      @db[:items].insert(false)
      expect(@db[:items].select_map(:a)).to eq [false]
      expect(@db[:items].select_map(Sequel.expr(:a) + :a)).to eq [0]
      @db[:items].update(a: true)
      expect(@db[:items].select_map(:a)).to eq [true]
      expect(@db[:items].select_map(Sequel.expr(:a) + :a)).to eq [2]
    end

    it 'handles integers/floats/strings/decimals in numeric/decimal columns' do
      @db.create_table(:items) { Numeric :a }
      @db[:items].insert(100)
      expect(@db[:items].select_map(:a)).to eq [BigDecimal('100')]
      expect(@db[:items].get(:a)).to be_kind_of(BigDecimal)

      @db[:items].update(a: 100.1)
      expect(@db[:items].select_map(:a)).to eq [BigDecimal('100.1')]
      expect(@db[:items].get(:a)).to be_kind_of(BigDecimal)

      @db[:items].update(a: '100.1')
      expect(@db[:items].select_map(:a)).to eq [BigDecimal('100.1')]
      expect(@db[:items].get(:a)).to be_kind_of(BigDecimal)

      @db[:items].update(a: BigDecimal('100.1'))
      expect(@db[:items].select_map(:a)).to eq [BigDecimal('100.1')]
      expect(@db[:items].get(:a)).to be_kind_of(BigDecimal)
    end

    it 'handles integer/float date columns as julian date' do
      @db.create_table(:items) { Date :a }
      i = 2455979
      @db[:items].insert(i)
      expect(@db[:items].first).to eq(a: Date.jd(i))
      @db[:items].update(a: 2455979.1)
      expect(@db[:items].first).to eq(a: Date.jd(i))
    end

    it 'handles integer/float time columns as seconds' do
      @db.create_table(:items) { Time :a, only_time: true }
      @db[:items].insert(3661)
      expect(@db[:items].first).to eq(a: Sequel::SQLTime.create(1, 1, 1))
      @db[:items].update(a: 3661.000001)
      expect(@db[:items].first).to eq(a: Sequel::SQLTime.create(1, 1, 1, 1))
    end

    it 'handles integer datetime columns as unix timestamp' do
      @db.create_table(:items) { DateTime :a }
      i = 1329860756
      @db[:items].insert(i)
      expect(@db[:items].first).to eq(a: Time.at(i))
      Sequel.datetime_class = DateTime
      expect(@db[:items].first).to eq(a: DateTime.strptime(i.to_s, '%s'))
    end

    it 'handles float datetime columns as julian date' do
      @db.create_table(:items) { DateTime :a }
      i = 2455979.5
      @db[:items].insert(i)
      expect(@db[:items].first).to eq(a: Time.at(1329825600))
      Sequel.datetime_class = DateTime
      expect(@db[:items].first).to eq(a: DateTime.jd(2455979.5))
    end

    it 'handles integer/float blob columns' do
      @db.create_table(:items) { File :a }
      @db[:items].insert(1)
      expect(@db[:items].first).to eq(a: Sequel::SQL::Blob.new('1'))
      @db[:items].update(a: '1.1')
      expect(@db[:items].first).to eq(a: Sequel::SQL::Blob.new(1.1.to_s))
    end
  end
end

unless DB.adapter_scheme == :sqlite && DB.opts[:setup_regexp_function]
  describe 'An SQLite dataset' do
    before do
      @d = DB.dataset
    end

    it 'raises errors if given a regexp pattern match' do
      expect { @d.literal(Sequel.expr(:x).like(/a/)) }.to raise_error(Sequel::InvalidOperation)
      expect { @d.literal(~Sequel.expr(:x).like(/a/)) }.to raise_error(Sequel::InvalidOperation)
      expect { @d.literal(Sequel.expr(:x).like(/a/i)) }.to raise_error(Sequel::InvalidOperation)
      expect { @d.literal(~Sequel.expr(:x).like(/a/i)) }.to raise_error(Sequel::InvalidOperation)
    end
  end
end

describe 'SQLite::Dataset#delete' do
  before do
    DB.create_table! :items do
      primary_key :id
      String :name
      Float :value
    end
    @d = DB[:items]
    @d.delete # remove all records
    @d.insert(name: 'abc', value: 1.23)
    @d.insert(name: 'def', value: 4.56)
    @d.insert(name: 'ghi', value: 7.89)
  end

  after do
    DB.drop_table?(:items)
  end

  it 'returns the number of records affected when filtered' do
    expect(@d.count).to eq 3
    expect(@d.filter { value < 3 }.delete).to eq 1
    expect(@d.count).to eq 2

    expect(@d.filter { value < 3 }.delete).to eq 0
    expect(@d.count).to eq 2
  end

  it 'returns the number of records affected when unfiltered' do
    expect(@d.count).to eq 3
    expect(@d.delete).to eq 3
    expect(@d.count).to eq 0

    expect(@d.delete).to eq 0
  end
end

describe 'SQLite::Dataset#update' do
  before do
    DB.create_table! :items do
      primary_key :id
      String :name
      Float :value
    end
    @d = DB[:items]
    @d.delete # remove all records
    @d.insert(name: 'abc', value: 1.23)
    @d.insert(name: 'def', value: 4.56)
    @d.insert(name: 'ghi', value: 7.89)
  end

  it 'returns the number of records affected' do
    expect(@d.filter(name: 'abc').update(value: 2)).to eq 1

    expect(@d.update(value: 10)).to eq 3

    expect(@d.filter(name: 'xxx').update(value: 23)).to eq 0
  end
end

describe 'SQLite::Dataset#insert_conflict' do
  before(:all) do
    DB.create_table! :ic_test do
      primary_key :id
      String :name
    end
  end

  after do
    DB[:ic_test].delete
  end

  after(:all) do
    DB.drop_table?(:ic_test)
  end

  it 'Dataset#insert_ignore and insert_constraint should ignore uniqueness violations' do
    DB[:ic_test].insert(id: 1, name: 'one')
    expect { DB[:ic_test].insert(id: 1, name: 'one') }.to raise_error Sequel::ConstraintViolation

    DB[:ic_test].insert_ignore.insert(id: 1, name: 'one')
    expect(DB[:ic_test].all).to eq([{ id: 1, name: 'one' }])

    DB[:ic_test].insert_conflict(:ignore).insert(id: 1, name: 'one')
    expect(DB[:ic_test].all).to eq([{ id: 1, name: 'one' }])
  end

  it 'Dataset#insert_constraint should handle replacement' do
    DB[:ic_test].insert(id: 1, name: 'one')

    DB[:ic_test].insert_conflict(:replace).insert(id: 1, name: 'two')
    expect(DB[:ic_test].all).to eq([{ id: 1, name: 'two' }])
  end
end

describe 'SQLite dataset' do
  before do
    DB.create_table! :test do
      primary_key :id
      String :name
      Float :value
    end
    DB.create_table! :items do
      primary_key :id
      String :name
      Float :value
    end
    @d = DB[:items]
    @d.insert(name: 'abc', value: 1.23)
    @d.insert(name: 'def', value: 4.56)
    @d.insert(name: 'ghi', value: 7.89)
  end

  after do
    DB.drop_table?(:test, :items)
  end

  it 'is able to insert from a subquery' do
    DB[:test].insert(@d)
    expect(DB[:test].count).to eq 3
    expect(DB[:test].select(:name, :value).order(:value).to_a).to eq \
      @d.select(:name, :value).order(:value).to_a
  end

  it 'supports #explain' do
    expect(DB[:test].explain).to be_kind_of(String)
  end
end

describe 'A SQLite database' do
  before do
    @db = DB
    @db.create_table! :test2 do
      text :name
      integer :value
    end
  end

  after do
    @db.drop_table?(:test, :test2, :test3, :test3_backup0, :test3_backup1, :test3_backup2)
  end

  it 'supports add_column operations' do
    @db.add_column :test2, :xyz, :text

    expect(@db[:test2].columns).to eq %i[name value xyz]
    @db[:test2].insert(name: 'mmm', value: 111, xyz: '000')
    expect(@db[:test2].first).to eq(name: 'mmm', value: 111, xyz: '000')
  end

  it 'supports drop_column operations' do
    @db.drop_column :test2, :value
    expect(@db[:test2].columns).to eq [:name]
    @db[:test2].insert(name: 'mmm')
    expect(@db[:test2].first).to eq(name: 'mmm')
  end

  it 'supports drop_column operations in a transaction' do
    @db.transaction { @db.drop_column :test2, :value }
    expect(@db[:test2].columns).to eq [:name]
    @db[:test2].insert(name: 'mmm')
    expect(@db[:test2].first).to eq(name: 'mmm')
  end

  it 'keeps a composite primary key when dropping columns' do
    @db.create_table!(:test2) {
      Integer :a
      Integer :b
      Integer :c
      primary_key %i[a b]
    }
    @db.drop_column :test2, :c
    expect(@db[:test2].columns).to eq %i[a b]
    @db[:test2].insert(a: 1, b: 2)
    @db[:test2].insert(a: 2, b: 3)
    expect { @db[:test2].insert(a: 2, b: 3) }.to raise_error(Sequel::UniqueConstraintViolation)
  end

  it 'keeps column attributes when dropping a column' do
    @db.create_table! :test3 do
      primary_key :id
      text :name
      integer :value
    end

    # This lame set of additions and deletions are to test that the primary keys
    # don't get messed up when we recreate the database.
    @db[:test3].insert(name: 'foo', value: 1)
    @db[:test3].insert(name: 'foo', value: 2)
    @db[:test3].insert(name: 'foo', value: 3)
    @db[:test3].filter(id: 2).delete

    @db.drop_column :test3, :value

    expect(@db['PRAGMA table_info(?)', :test3][:id][:pk].to_i).to eq 1
    expect(@db[:test3].select(:id).all).to eq [{ id: 1 }, { id: 3 }]
  end

  it 'keeps foreign keys when dropping a column' do
    @db.create_table! :test do
      primary_key :id
      String :name
      Integer :value
    end
    @db.create_table! :test3 do
      String :name
      Integer :value
      foreign_key :test_id, :test, on_delete: :set_null, on_update: :cascade
    end

    @db[:test3].insert(name: 'abc', test_id: @db[:test].insert(name: 'foo', value: 3))
    @db[:test3].insert(name: 'def', test_id: @db[:test].insert(name: 'bar', value: 4))

    @db.drop_column :test3, :value

    @db[:test].filter(name: 'bar').delete
    expect(@db[:test3][name: 'def'][:test_id]).to be_nil

    @db[:test].filter(name: 'foo').update(id: 100)
    expect(@db[:test3][name: 'abc'][:test_id]).to eq 100
  end

  it 'supports rename_column operations' do
    @db[:test2].delete
    @db.add_column :test2, :xyz, :text
    @db[:test2].insert(name: 'mmm', value: 111, xyz: 'qqqq')

    expect(@db[:test2].columns).to eq %i[name value xyz]
    @db.rename_column :test2, :xyz, :zyx, type: :text
    expect(@db[:test2].columns).to eq %i[name value zyx]
    expect(@db[:test2].first[:zyx]).to eq 'qqqq'
    expect(@db[:test2].count).to eq 1
  end

  it 'preserves defaults when dropping or renaming columns' do
    @db.create_table! :test3 do
      String :s, default: 'a'
      Integer :i
    end

    @db[:test3].insert
    expect(@db[:test3].first[:s]).to eq 'a'
    @db[:test3].delete
    @db.drop_column :test3, :i
    @db[:test3].insert
    expect(@db[:test3].first[:s]).to eq 'a'
    @db[:test3].delete
    @db.rename_column :test3, :s, :t
    @db[:test3].insert
    expect(@db[:test3].first[:t]).to eq 'a'
    @db[:test3].delete
  end

  it 'preserves autoincrement after table modification' do
    @db.create_table!(:test2) do
      primary_key :id
      Integer :val, null: false
    end
    @db.rename_column(:test2, :val, :value)

    t = @db[:test2]
    id1 = t.insert(value: 1)
    t.delete
    id2 = t.insert(value: 1)
    expect(id2 > id1).to be true
  end

  it 'handles quoted tables when dropping or renaming columns' do
    table_name = 'T T'
    @db.drop_table?(table_name)
    @db.create_table! table_name do
      Integer :'s s'
      Integer :'i i'
    end

    @db.from(table_name).insert('s s': 1, 'i i': 2)
    expect(@db.from(table_name).all).to eq [{ 's s': 1, 'i i': 2 }]
    @db.drop_column table_name, :'i i'
    expect(@db.from(table_name).all).to eq [{ 's s': 1 }]
    @db.rename_column table_name, :'s s', :'t t'
    expect(@db.from(table_name).all).to eq [{ 't t': 1 }]
    @db.drop_table?(table_name)
  end

  it "chooses a temporary table name that isn't already used when dropping or renaming columns" do
    @db.tables.each { |t| @db.drop_table(t) if t.to_s =~ /test3/ }
    @db.create_table :test3 do
      Integer :h
      Integer :i
    end
    @db.create_table :test3_backup0 do
      Integer :j
    end
    @db.create_table :test3_backup1 do
      Integer :k
    end

    expect(@db[:test3].columns).to eq %i[h i]
    expect(@db[:test3_backup0].columns).to eq [:j]
    expect(@db[:test3_backup1].columns).to eq [:k]
    @db.drop_column(:test3, :i)
    expect(@db[:test3].columns).to eq [:h]
    expect(@db[:test3_backup0].columns).to eq [:j]
    expect(@db[:test3_backup1].columns).to eq [:k]

    @db.create_table :test3_backup2 do
      Integer :l
    end

    @db.rename_column(:test3, :h, :i)
    expect(@db[:test3].columns).to eq [:i]
    expect(@db[:test3_backup0].columns).to eq [:j]
    expect(@db[:test3_backup1].columns).to eq [:k]
    expect(@db[:test3_backup2].columns).to eq [:l]
  end

  it 'supports add_index' do
    @db.add_index :test2, :value, unique: true
    @db.add_index :test2, %i[name value]
  end

  it 'supports drop_index' do
    @db.add_index :test2, :value, unique: true
    @db.drop_index :test2, :value
  end

  it 'keeps applicable indexes when emulating schema methods' do
    @db.create_table!(:test3) {
      Integer :a
      Integer :b
    }
    @db.add_index :test3, :a
    @db.add_index :test3, :b
    @db.add_index :test3, %i[b a]
    @db.rename_column :test3, :b, :c
    expect(@db.indexes(:test3)[:test3_a_index]).to eq(unique: false, columns: [:a])
  end

  it 'has support for various #transaction modes' do
    @db.transaction(mode: :immediate) {}
    @db.transaction(mode: :exclusive) {}
    @db.transaction(mode: :deferred) {}
    @db.transaction {}

    expect(@db.transaction_mode).to be_nil
    @db.transaction_mode = :immediate
    expect(@db.transaction_mode).to eq :immediate
    @db.transaction {}
    @db.transaction(mode: :exclusive) {}
    expect { @db.transaction_mode = :invalid }.to raise_error(Sequel::Error)
    expect(@db.transaction_mode).to eq :immediate
    expect { @db.transaction(mode: :invalid) {} }.to raise_error(Sequel::Error)
  end

  it 'keeps unique constraints when copying tables' do
    @db.alter_table(:test2) { add_unique_constraint :name }
    @db.alter_table(:test2) { drop_column :value }
    @db[:test2].insert(name: 'a')
    expect { @db[:test2].insert(name: 'a') }.to raise_error(Sequel::UniqueConstraintViolation)
  end

  it 'does not ignore adding new constraints when adding not null constraints' do
    @db.alter_table :test2 do
      set_column_not_null :value
      add_constraint(:value_range1, value: 3..5)
      add_constraint(:value_range2, value: 0..9)
    end

    @db[:test2].insert(value: 4)
    expect { @db[:test2].insert(value: 1) }.to raise_error(Sequel::ConstraintViolation)
    expect { @db[:test2].insert(value: nil) }.to raise_error(Sequel::ConstraintViolation)
    expect(@db[:test2].select_order_map(:value)).to eq [4]
  end

  if DB.sqlite_version >= 30808
    it 'shows unique constraints in Database#indexes' do
      @db.alter_table(:test2) { add_unique_constraint :name }
      expect(@db.indexes(:test2).values.first[:columns]).to eq [:name]
    end
  end
end

if DB.sqlite_version >= 32400
  describe 'SQLite', 'INSERT ON CONFLICT' do
    before(:all) do
      @db = DB
      @db.create_table!(:ic_test) {
        Integer :a
        Integer :b
        Integer :c
        TrueClass :c_is_unique, default: false
        unique :a, name: :ic_test_a_uidx
        unique %i[b c], name: :ic_test_b_c_uidx
        index [:c], where: :c_is_unique, unique: true
      }
      @ds = @db[:ic_test]
    end

    before do
      @ds.delete
    end

    after(:all) do
      @db.drop_table?(:ic_test)
    end

    unless DB.adapter_scheme == :amalgalite
      it 'Dataset#insert_ignore and insert_conflict should ignore uniqueness violations' do
        @ds.insert(1, 2, 3, false)
        @ds.insert(10, 11, 3, true)
        expect { @ds.insert(1, 3, 4, false) }.to raise_error Sequel::UniqueConstraintViolation
        expect { @ds.insert(11, 12, 3, true) }.to raise_error Sequel::UniqueConstraintViolation
        @ds.insert_ignore.insert(1, 3, 4, false)
        @ds.insert_conflict.insert(1, 3, 4, false)
        @ds.insert_conflict.insert(11, 12, 3, true)
        @ds.insert_conflict(target: :a).insert(1, 3, 4, false)
        @ds.insert_conflict(target: :c, conflict_where: :c_is_unique).insert(11, 12, 3, true)
        expect(@ds.all).to eq [{ a: 1, b: 2, c: 3, c_is_unique: false }, { a: 10, b: 11, c: 3, c_is_unique: true }]
      end
    end

    it 'Dataset#insert_ignore and insert_conflict should work with multi_insert/import' do
      @ds.insert(1, 2, 3, false)
      @ds.insert_ignore.multi_insert([{ a: 1, b: 3, c: 4 }])
      @ds.insert_ignore.import(%i[a b c], [[1, 3, 4]])
      expect(@ds.all).to eq [{ a: 1, b: 2, c: 3, c_is_unique: false }]
      @ds.insert_conflict(target: :a, update: { b: 3 }).import(%i[a b c], [[1, 3, 4]])
      expect(@ds.all).to eq [{ a: 1, b: 3, c: 3, c_is_unique: false }]
      @ds.insert_conflict(target: :a, update: { b: 4 }).multi_insert([{ a: 1, b: 5, c: 6 }])
      expect(@ds.all).to eq [{ a: 1, b: 4, c: 3, c_is_unique: false }]
    end

    it 'Dataset#insert_conflict should handle upserts' do
      @ds.insert(1, 2, 3, false)
      @ds.insert_conflict(target: :a, update: { b: 3 }).insert(1, 3, 4, false)
      expect(@ds.all).to eq [{ a: 1, b: 3, c: 3, c_is_unique: false }]
      @ds.insert_conflict(target: %i[b c], update: { c: 5 }).insert(5, 3, 3, false)
      expect(@ds.all).to eq [{ a: 1, b: 3, c: 5, c_is_unique: false }]
      @ds.insert_conflict(target: :a, update: { b: 4 }).insert(1, 3, nil, false)
      expect(@ds.all).to eq [{ a: 1, b: 4, c: 5, c_is_unique: false }]
      @ds.insert_conflict(target: :a, update: { b: 5 }, update_where: { Sequel[:ic_test][:b] => 4 }).insert(1, 3, 4, false)
      expect(@ds.all).to eq [{ a: 1, b: 5, c: 5, c_is_unique: false }]
      @ds.insert_conflict(target: :a, update: { b: 6 }, update_where: { Sequel[:ic_test][:b] => 4 }).insert(1, 3, 4, false)
      expect(@ds.all).to eq [{ a: 1, b: 5, c: 5, c_is_unique: false }]
    end
  end
end

if DB.sqlite_version >= 33700
  describe 'SQLite STRICT tables' do
    before do
      @db = DB
    end

    after do
      @db.drop_table?(:strict_table)
    end

    xit 'supports creation via :strict option' do
      @db = DB
      @db.create_table(:strict_table, strict: true) do
        primary_key :id
        int :a
        integer :b
        real :c
        text :d
        blob :e
        any :f
      end
      ds = @db[:strict_table]
      ds.insert(id: 1, a: 2, b: 3, c: 1.2, d: 'foo', e: Sequel.blob("\0\1\2\3"), f: 'f')
      expect(ds.all).to eq [{ id: 1, a: 2, b: 3, c: 1.2, d: 'foo', e: Sequel.blob("\0\1\2\3"), f: 'f' }]
      expect { ds.insert(a: 'a') }.to raise_error Sequel::ConstraintViolation
      expect { ds.insert(b: 'a') }.to raise_error Sequel::ConstraintViolation
      expect { ds.insert(c: 'a') }.to raise_error Sequel::ConstraintViolation
      expect { ds.insert(d: Sequel.blob("\0\1\2\3")) }.to raise_error Sequel::ConstraintViolation
      expect { ds.insert(e: 1) }.to raise_error Sequel::ConstraintViolation
    end
  end
end

if DB.sqlite_version >= 33800
  describe 'SQLite Database' do
    it 'supports operations/functions with sqlite_json_ops' do
      Sequel.extension :sqlite_json_ops
      @db = DB
      jo = Sequel.sqlite_json_op('{"a": 1 ,"b": {"c": 2, "d": {"e": 3}}}')
      ja = Sequel.sqlite_json_op('[2, 3, ["a", "b"]]')

      expect(@db.get(jo['a'])).to eq 1
      expect(@db.get(jo.get('b')['c'])).to eq 2
      expect(@db.get(jo['$.b.c'])).to eq 2
      expect(@db.get(jo['b'].get_json('$.d.e'))).to eq '3'
      expect(@db.get(jo['$.b.d'].get_json('e'))).to eq '3'
      expect(@db.get(ja[1])).to eq 3
      expect(@db.get(ja['$[2][1]'])).to eq 'b'

      expect(@db.get(ja.get_json(1))).to eq '3'
      expect(@db.get(ja.get_json('$[2][1]'))).to eq '"b"'

      expect(@db.get(jo.extract('$.a'))).to eq 1
      expect(@db.get(jo.extract('$.a', '$.b.c'))).to eq '[1,2]'
      expect(@db.get(jo.extract('$.a', '$.b.d.e'))).to eq '[1,3]'

      expect(@db.get(ja.array_length)).to eq 3
      expect(@db.get(ja.array_length('$[2]'))).to eq 2

      expect(@db.get(jo.type)).to eq 'object'
      expect(@db.get(ja.type)).to eq 'array'
      expect(@db.get(jo.typeof)).to eq 'object'
      expect(@db.get(ja.typeof)).to eq 'array'
      expect(@db.get(jo.type('$.a'))).to eq 'integer'
      expect(@db.get(ja.typeof('$[2][1]'))).to eq 'text'

      expect(@db.from(jo.each).all).to eq [
        { key: 'a', value: 1, type: 'integer', atom: 1, id: 2, parent: nil, fullkey: '$.a', path: '$' },
        { key: 'b', value: '{"c":2,"d":{"e":3}}', type: 'object', atom: nil, id: 4, parent: nil, fullkey: '$.b', path: '$' },
      ]
      expect(@db.from(jo.each('$.b')).all).to eq [
        { key: 'c', value: 2, type: 'integer', atom: 2, id: 6, parent: nil, fullkey: '$.b.c', path: '$.b' },
        { key: 'd', value: '{"e":3}', type: 'object', atom: nil, id: 8, parent: nil, fullkey: '$.b.d', path: '$.b' },
      ]
      expect(@db.from(ja.each).all).to eq [
        { key: 0, value: 2, type: 'integer', atom: 2, id: 1, parent: nil, fullkey: '$[0]', path: '$' },
        { key: 1, value: 3, type: 'integer', atom: 3, id: 2, parent: nil, fullkey: '$[1]', path: '$' },
        { key: 2, value: '["a","b"]', type: 'array', atom: nil, id: 3, parent: nil, fullkey: '$[2]', path: '$' },
      ]
      expect(@db.from(ja.each('$[2]')).all).to eq [
        { key: 0, value: 'a', type: 'text', atom: 'a', id: 4, parent: nil, fullkey: '$[2][0]', path: '$[2]' },
        { key: 1, value: 'b', type: 'text', atom: 'b', id: 5, parent: nil, fullkey: '$[2][1]', path: '$[2]' },
      ]

      expect(@db.from(jo.tree).all).to eq [
        { key: nil, value: '{"a":1,"b":{"c":2,"d":{"e":3}}}', type: 'object', atom: nil, id: 0, parent: nil, fullkey: '$', path: '$' },
        { key: 'a', value: 1, type: 'integer', atom: 1, id: 2, parent: 0, fullkey: '$.a', path: '$' },
        { key: 'b', value: '{"c":2,"d":{"e":3}}', type: 'object', atom: nil, id: 4, parent: 0, fullkey: '$.b', path: '$' },
        { key: 'c', value: 2, type: 'integer', atom: 2, id: 6, parent: 4, fullkey: '$.b.c', path: '$.b' },
        { key: 'd', value: '{"e":3}', type: 'object', atom: nil, id: 8, parent: 4, fullkey: '$.b.d', path: '$.b' },
        { key: 'e', value: 3, type: 'integer', atom: 3, id: 10, parent: 8, fullkey: '$.b.d.e', path: '$.b.d' },
      ]
      expect(@db.from(jo.tree('$.b')).all).to eq [
        { key: 'b', value: '{"c":2,"d":{"e":3}}', type: 'object', atom: nil, id: 4, parent: nil, fullkey: '$.b', path: '$' },
        { key: 'c', value: 2, type: 'integer', atom: 2, id: 6, parent: 4, fullkey: '$.b.c', path: '$.b' },
        { key: 'd', value: '{"e":3}', type: 'object', atom: nil, id: 8, parent: 4, fullkey: '$.b.d', path: '$.b' },
        { key: 'e', value: 3, type: 'integer', atom: 3, id: 10, parent: 8, fullkey: '$.b.d.e', path: '$.b.d' },
      ]
      expect(@db.from(ja.tree).all).to eq [
        { key: nil, value: '[2,3,["a","b"]]', type: 'array', atom: nil, id: 0, parent: nil, fullkey: '$', path: '$' },
        { key: 0, value: 2, type: 'integer', atom: 2, id: 1, parent: 0, fullkey: '$[0]', path: '$' },
        { key: 1, value: 3, type: 'integer', atom: 3, id: 2, parent: 0, fullkey: '$[1]', path: '$' },
        { key: 2, value: '["a","b"]', type: 'array', atom: nil, id: 3, parent: 0, fullkey: '$[2]', path: '$' },
        { key: 0, value: 'a', type: 'text', atom: 'a', id: 4, parent: 3, fullkey: '$[2][0]', path: '$[2]' },
        { key: 1, value: 'b', type: 'text', atom: 'b', id: 5, parent: 3, fullkey: '$[2][1]', path: '$[2]' },
      ]
      expect(@db.from(ja.tree('$[2]')).all).to eq [
        { key: nil, value: '["a","b"]', type: 'array', atom: nil, id: 3, parent: nil, fullkey: '$[0]', path: '$' },
        { key: 0, value: 'a', type: 'text', atom: 'a', id: 4, parent: 3, fullkey: '$[0][0]', path: '$[0]' },
        { key: 1, value: 'b', type: 'text', atom: 'b', id: 5, parent: 3, fullkey: '$[0][1]', path: '$[0]' },
      ]

      expect(@db.get(jo.json)).to eq '{"a":1,"b":{"c":2,"d":{"e":3}}}'
      expect(@db.get(ja.minify)).to eq '[2,3,["a","b"]]'

      expect(@db.get(ja.insert('$[1]', 5))).to eq '[2,3,["a","b"]]'
      expect(@db.get(ja.replace('$[1]', 5))).to eq '[2,5,["a","b"]]'
      expect(@db.get(ja.set('$[1]', 5))).to eq '[2,5,["a","b"]]'
      expect(@db.get(ja.insert('$[3]', 5))).to eq '[2,3,["a","b"],5]'
      expect(@db.get(ja.replace('$[3]', 5))).to eq '[2,3,["a","b"]]'
      expect(@db.get(ja.set('$[3]', 5))).to eq '[2,3,["a","b"],5]'
      expect(@db.get(ja.insert('$[1]', 5, '$[3]', 6))).to eq '[2,3,["a","b"],6]'
      expect(@db.get(ja.replace('$[1]', 5, '$[3]', 6))).to eq '[2,5,["a","b"]]'
      expect(@db.get(ja.set('$[1]', 5, '$[3]', 6))).to eq '[2,5,["a","b"],6]'

      expect(@db.get(jo.insert('$.f', 4))).to eq '{"a":1,"b":{"c":2,"d":{"e":3}},"f":4}'
      expect(@db.get(jo.replace('$.f', 4))).to eq '{"a":1,"b":{"c":2,"d":{"e":3}}}'
      expect(@db.get(jo.set('$.f', 4))).to eq '{"a":1,"b":{"c":2,"d":{"e":3}},"f":4}'
      expect(@db.get(jo.insert('$.a', 4))).to eq '{"a":1,"b":{"c":2,"d":{"e":3}}}'
      expect(@db.get(jo.replace('$.a', 4))).to eq '{"a":4,"b":{"c":2,"d":{"e":3}}}'
      expect(@db.get(jo.set('$.a', 4))).to eq '{"a":4,"b":{"c":2,"d":{"e":3}}}'
      expect(@db.get(jo.insert('$.f', 4, '$.a', 5))).to eq '{"a":1,"b":{"c":2,"d":{"e":3}},"f":4}'
      expect(@db.get(jo.replace('$.f', 4, '$.a', 5))).to eq '{"a":5,"b":{"c":2,"d":{"e":3}}}'
      expect(@db.get(jo.set('$.f', 4, '$.a', 5))).to eq '{"a":5,"b":{"c":2,"d":{"e":3}},"f":4}'

      expect(@db.get(jo.patch('{"e": 4, "b": 5, "a": null}'))).to eq '{"b":5,"e":4}'

      expect(@db.get(ja.remove('$[1]'))).to eq '[2,["a","b"]]'
      expect(@db.get(ja.remove('$[1]', '$[1]'))).to eq '[2]'
      expect(@db.get(jo.remove('$.a'))).to eq '{"b":{"c":2,"d":{"e":3}}}'
      expect(@db.get(jo.remove('$.a', '$.b.c'))).to eq '{"b":{"d":{"e":3}}}'

      expect(@db.get(jo.valid)).to eq 1
      expect(@db.get(ja.valid)).to eq 1
    end
  end
end
