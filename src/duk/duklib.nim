import macros, sequtils, sugar

import duktape_wrapper, consts, lib, ctx_val_proc

proc error(n: NimNode, msg: string) = error(msg, n)
proc expect(n: NimNode, cond: bool, msg: string) =
  if not cond: n.error(msg)

type
  JSString* = cstring
  JSNumber* = cdouble
  JSInt* = cint
  JSSeq* = seq[JSVal]

type DukLib* = ref object
  builder: proc(ctx: Context, idx: IdxT)
  name*: string
  
type JSType = enum
  jstString, jstNumber, jstInt, jstSeq, jstNot

proc getJSType(ty: string): JSType =
  case ty
  of "JSString": jstString
  of "JSNumber": jstNumber
  of "JSInt": jstInt
  of "JSSeq": jstSeq
  else: jstNot

proc getRequireFn(ty: JSType): NimNode = 
  case ty
  of jstString: bindSym"requireString"
  of jstNumber: bindSym"requireNumber"
  of jstInt: bindSym"requireInt"
  of jstSeq: bindSym"requireArray"
  of jstNot: newEmptyNode()

proc injectLib*(ctx: Context, idx: IdxT, lib: DukLib) {.dukCtxPtrProc.} =
  lib.builder(ctx, ctx.requireNormalizeIndex idx)
proc injectLibGlobal*(ctx: Context, lib: DukLib) =
  ctx.pushGlobalObject()
  ctx.injectLib(-1, lib)
  ctx.pop()
proc injectLibNamespace*(ctx: Context, lib: DukLib, name: string) =
  let idx = ctx.pushBareObject()
  ctx.injectLib(idx, lib)
  discard ctx.putGlobalString(name)
  
proc makePushCall(fn: NimNode, nargs: int): NimNode =
  fn.addPragma ident"cdecl"
  nnkDiscardStmt.newTree newCall(
    bindSym"pushCFunction",
    ident"ctx",
    fn,
    newIntLitNode nargs
  )

macro pushProc*(ctx: Context, fn: untyped): untyped =
  let cParams = fn.params
  let retParam = cParams[0]
  if cParams.len == 2 and cParams[1][^2].eqIdent"Context":
    retParam.expect(
      retParam.kind != nnkEmpty and retParam.eqIdent"RetT",
      "Return type for processing the raw context must be `RetT`"
    )
    return makePushCall(fn, -1)
  var params = newSeq[JSType]()
  var va: tuple[isVa: bool, ty: JSType, hasFn: bool, fn: NimNode]
  for i in 1..<cParams.len:
    let param = cParams[i]
    let parTy = param[^2]
    if parTy.kind == nnkBracketExpr:
      parTy.expect parTy[0] == ident"varargs", "Expected `varargs`"
      parTy.expect(
        param.len == 3 and i == cParams.len - 1,
        "Only one vararg can be in a parameter list, and at the end"
      )
      va.isVa = true
      case parTy.len
      of 2: va.ty = getJSType $parTy[1]
      of 3:
        va.hasFn = true
        va.fn = parTy[2]
      else: parTy.error("Malformed varargs")
      continue
    parTy.expectKind nnkIdent
    let jsTy = getJSType $parTy
    param.expect(
      jsTy != jstNot,
      "Types for parameters in duk lib function must all be a JS`Type`"
    )
    for _ in toSeq(param.children)[0..^3]:
      params.add jsTy
  retParam.expect(
    retParam.kind == nnkEmpty or getJSType($retParam) != jstNot,
    "Return type must be a JS`Type`"
  )
  var cFnStmts = newStmtList()
  var args = newSeq[NimNode]()
  for i, ty in params:
    args.add newCall(ty.getRequireFn, ident"ctx", newIntLitNode i)
  if va.isVa:
    args.add newCall(
      bindSym"mapIt",
      infix(
        newIntLitNode params.len,
        "..<",
        newCall(bindSym"getTop", ident"ctx")
      ),
      newCall(
        if va.hasFn: va.fn
        else: va.ty.getRequireFn,
        nnkBracketExpr.newTree(ident"ctx", ident"it")
      )
    )
  let cFnCall = newCall(
    newPar fn,
    args
  )
  if cParams[0].kind == nnkEmpty:
    cfnStmts.add cFnCall
  else:
    cfnStmts.add newCall(
      bindSym"pushAny",
      ident"ctx",
      cFnCall
    ), bindSym"DUK_RET_RETURN"
  let outProc = newProc(
    params = [
      bindSym"RetT",
      nnkIdentDefs.newTree(ident"ctx", bindSym"Context", newEmptyNode())
    ],
    body = cFnStmts,
  )
  makePushCall(outProc, if va.isVa: -1 else: params.len)

type BlockInfo = ref object
  case isNested: bool
  of true: objName: string
  of false: discard

proc doLibBlock(outStmts: var NimNode, stmtList: NimNode, info: BlockInfo) =
  let isNested = info.isNested
  let tIdx = if isNested: newIntLitNode -2 else: ident"tIdx"
  if isNested: outStmts.add nnkDiscardStmt.newTree newCall(bindSym"pushBareObject", ident"ctx")
  for child in stmtList.children:
    child.expectKind {nnkProcDef, nnkCommand}
    case child.kind
    of nnkProcDef:
      let name = $child.name
      child.name = newEmptyNode()
      outStmts.add(
        newCall(bindSym"pushProc", ident"ctx", child),
        nnkDiscardStmt.newTree newCall(
          bindSym"putPropString",
          ident"ctx",
          tIdx,
          newStrLitNode name
        )
      )
    of nnkCommand: 
      case $child[0]
      of "sublib":
        child[1].expectKind nnkIdent
        outStmts.doLibBlock child[2], BlockInfo(isNested: true, objName: $child[1])
      else: child[0].error("Invalid subcommand")
    else: discard
  if isNested:
    outStmts.add(
      nnkDiscardStmt.newTree newCall(
        bindSym"putPropString",
        ident"ctx",
        tIdx,
        newStrLitNode info.objName
      )
    )

macro duklib*(name, body: untyped): untyped =
  name.expectKind nnkIdent
  body.expectKind nnkStmtList
  var libStmts = newStmtList()
  libStmts.doLibBlock body, BlockInfo(isNested: false)
  let builder = newProc(
    params = [
      newEmptyNode(),
      nnkIdentDefs.newTree(ident"ctx", bindSym"Context", newEmptyNode()),
      nnkIdentDefs.newTree(ident"tIdx", bindSym"IdxT", newEmptyNode())
    ],
    body = libStmts
  )
  newLetStmt(name, nnkObjConstr.newTree(
    bindSym"DukLib",
    newColonExpr(ident"builder", builder),
    newColonExpr(ident"name", newStrLitNode $name)
  ))
