import { RubyApplication } from 'bormashino'
import rubyWasm from 'url:../tmp/ruby.wasm'

import initSqlJs from 'sql.js'
import sqlWasm from 'url:../node_modules/sql.js/dist/sql-wasm.wasm'
import { dbWrapper } from 'bormashino-sequel-sqljs-adapter'

const main = async () => {
  const SQL = await initSqlJs({ locateFile: () => sqlWasm })
  const db = new SQL.Database()
  window.database = dbWrapper(db)

  db.run('CREATE TABLE test (col1, col2);')
  // Insert two rows: (1,111) and (2,222)
  db.run('INSERT INTO test VALUES (?,?), (?,?)', [1, 111, 2, 222])
  db.run('INSERT INTO test VALUES (?,?), (?,?)', [3, 333, 4, 444])

  const vm = await RubyApplication.initVm(rubyWasm, [
    'ruby.wasm',
    '-I/stub',
    '-I/gem/lib',
    '-EUTF-8',
    '-e_=0',
  ])

  vm.printVersion()
  vm.eval(`require_relative '/src/bootstrap.rb'`)

  const currentPath = () => location.href.replace(location.origin, '')
  RubyApplication.request('get', currentPath())
  RubyApplication.mount()

  window.bormashino = RubyApplication
}

main()
