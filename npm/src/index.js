export const dbWrapper = (db) => {
  return {
    db,
    exec: (sql) => {
      try {
        return db.exec(sql)
      } catch (e) {
        return { message: e.message, stack: e.stack, type: 'exception' }
      }
    },
    getRowsModified: () => {
      return db.getRowsModified()
    },
    prepareGetColumnNames: (sql) => {
      try {
        return db.prepare(sql).getColumnNames()
      } catch (e) {
        return { message: e.message, stack: e.stack, type: 'exception' }
      }
    },
  }
}
