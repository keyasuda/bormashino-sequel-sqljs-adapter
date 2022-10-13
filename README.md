# bormashino-sequel-sqljs-adapter

SQL.JS adapter for Sequel on browser with Bormaŝino / ruby.wasm

## Demo

https://bormashino-sequel-sqljs-adapter.vercel.app/

## Quickstart

app.js

```js
import initSqlJs from 'sql.js'
import sqlWasm from 'url:../node_modules/sql.js/dist/sql-wasm.wasm'
import { dbWrapper } from 'bormashino-sequel-sqljs-adapter'
const SQL = await initSqlJs({ locateFile: () => sqlWasm })
const db = new SQL.Database()
window.database = dbWrapper(db)
```

app.rb

```ruby
require 'sequel'
require 'bormashino_sequel_sqljs_adapter'
# sqljs://<name of dbWrapper instance under window object>
@db = Sequel.connect('sqljs://database')

@db.create_table :items do
  primary_key :id
  String :name
  Float :price
end

items = @db[:items]
```

## Release

### rubygem

```bash
$ cd gem
$ bundle exec rake build
$ gem push pkg/bormashino-sequel-sqljs-adapter-XXX.gem
```

### npm package

```bash
$ cd npm
$ npm publish
```

## License

[MIT](https://choosealicense.com/licenses/mit/)
