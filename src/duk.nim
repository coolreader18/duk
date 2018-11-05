import macros
macro impexp(mods: varargs[untyped]): untyped =
  result = newStmtList()
  for path in mods:
    result.add(
      nnkImportStmt.newTree path,
      nnkExportStmt.newTree path[2]
    )
  
impexp(
  duk/lib,
  duk/duktape_wrapper,
  duk/duklib
)
