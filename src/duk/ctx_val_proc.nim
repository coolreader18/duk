import macros, sequtils

proc isStackPtrProc(params: NimNode): bool =
  params.len >= 3 and params[1][^2].kind == nnkIdent and
    params[2][^2].kind == nnkIdent and $params[1][^2] == "Context" and
    $params[2][^2] == "IdxT"

# Functions that are targeted by proc(ctx: Context, xxx: IdxT), but
# it doesn't make sense for the index to be a StackPtr
proc isBlacklisted(name: NimNode): bool =
  case $name
  of "new", "popN": true
  else: false

macro dukCtxPtrProc*(fn: untyped): untyped =
  fn.expectKind RoutineNodes
  result = newStmtList(fn)
  let params = fn.params
  if params.isStackPtrProc and not fn.name.isBlacklisted:
    let call = newCall(
      fn.name,
      @[
        newDotExpr(ident"val", ident"ctx"),
        newDotExpr(ident"val", ident"idx")
      ].concat mapIt(toSeq(params.children)[3..^1], it[0])
    )
    result.add newProc(
      nnkPostfix.newTree(ident"*", fn.name),
      concat(
        @[params[0], newIdentDefs(ident"val", ident"StackPtr")],
        toSeq(params.children)[3..^1]
      ),
      if fn.kind == nnkIteratorDef:
        nnkForStmt.newTree(
          ident"c",
          call,
          nnkYieldStmt.newTree ident"c"
        )
      else: call,
      fn.kind
    )