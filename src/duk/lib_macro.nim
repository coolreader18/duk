import macros, sequtils, sugar

import duktape_wrapper, consts, lib

proc error(n: NimNode, msg: string) = error(msg, n)
proc expect(n: NimNode, cond: bool, msg: string) =
  if not cond: n.error(msg)

proc addFunc(outStmts: var NimNode; name: string; fn: NimNode, nargs: int) =
  fn.addPragma ident"cdecl"
  outStmts.add nnkStmtList.newTree(
        nnkDiscardStmt.newTree newCall(
          bindSym"pushCFunction",
          ident"ctx",
          fn,
          newIntLitNode nargs
        ),
        nnkDiscardStmt.newTree newCall(
          bindSym"putPropString",
          ident"ctx",
          newIntLitNode -2,
          newStrLitNode name
        )
  )

type
  JSString* = cstring
  JSNumber* = cdouble
  JSInt* = cint
  
type DukLib* = ref object
  builder: proc(ctx: Context)
  name*: string
  
type JSType = enum
  jstString, jstNumber, jstInt, jstNot

proc getJSType(ty: string): JSType =
  case ty
  of "JSString": jstString
  of "JSNumber": jstNumber
  of "JSInt": jstInt
  else: jstNot

proc getRequireFn(ty: JSType): NimNode = 
  case ty
  of jstString: bindSym"requireString"
  of jstNumber: bindSym"requireNumber"
  of jstInt: bindSym"requireInt"
  of jstNot: newEmptyNode()

proc getPushFn(ty: JSType): NimNode =
  case ty
  of jstString: bindSym"pushString"
  of jstNumber: bindSym"pushNumber"
  of jstInt: bindSym"pushInt"
  of jstNot: newEmptyNode()

proc injectLib*(ctx: Context, lib: DukLib) =
  lib.builder(ctx)
  
type VarargsInfo = tuple[isVa: bool, ty: JSType, isUnTy: bool, fn: NimNode, outTy: NimNode]

proc doVarargs(va: var VarargsInfo, parTy: NimNode) =
  va.isVa = true
  if $parTy[1] == "typed":
    parTy.expect(
      parTy.len == 3,
      "If the varargs is `typed`, there needs to be a transformer function"
    )
    va.isUnTy = true
    va.fn = parTy[2]
    va.outTy = newCall(
      ident"type",
      va.fn.newCall bindSym"top".newCall bindSym"createHeap".newCall,
    )
    parTy[1] = va.outTy
    parTy.del 2
  else:
    let jsTy = getJSType $parTy[1]
    parTy.expect(
      jsTy != jstNot,
      "Types for parameters in duk lib function must all be a JS`Type`"
    )
    va.ty = jsTy

proc doProc(outStmts: var NimNode, fn: NimNode) = 
  let name = $fn.name
  fn.name = newEmptyNode()
  let cParams = fn.params
  let retParam = cParams[0]
  if cParams.len == 2 and cParams[1][^2].eqIdent"Context":
    retParam.expect(
      retParam.kind != nnkEmpty and retParam.eqIdent"RetT",
      "Return type for processing the raw context must be `RetT`"
    )
    outStmts.addFunc name, fn, -1
  else:
    var params = newSeq[JSType]()
    var va: VarargsInfo
    for i in 1..<cParams.len:
      let param = cParams[i]
      let parTy = param[^2]
      if parTy.kind == nnkBracketExpr:
        parTy.expect parTy[0] == ident"varargs", "Expected `varargs`"
        parTy.expect(
          param.len == 3 and i == cParams.len - 1,
          "Only one vararg can be in a parameter list, and at the end"
        )
        va.doVarargs parTy
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
          if va.isUnTy: va.fn
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
        getJSType($retParam).getPushFn,
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
    outStmts.addFunc name, outProc, if va.isVa: -1 else: params.len

proc doLibBlock(outStmts: var NimNode, stmtList: NimNode, isObj: bool, objName: string = "") =
  outStmts.add if isObj: nnkDiscardStmt.newTree newCall(bindSym"pushBareObject", ident"ctx")
    else: newCall(bindSym"pushGlobalObject", ident"ctx")
  for child in stmtList.children:
    child.expectKind {nnkProcDef, nnkCommand}
    case child.kind
    of nnkProcDef: outStmts.doProc child
    of nnkCommand: 
      case $child[0]
      of "sublib":
        child[1].expectKind nnkIdent
        outStmts.doLibBlock child[2], true, $child[1]
      else: child[0].error("Invalid subcommand")
    else: discard
  outStmts.add(
    if isObj:
      nnkDiscardStmt.newTree newCall(
        bindSym"putPropString",
        ident"ctx",
        newIntLitNode -2,
        newStrLitNode objName
      )
    else: newCall(bindSym"pop", ident"ctx")
  )

macro duklib*(name, body: untyped): untyped =
  name.expectKind nnkIdent
  body.expectKind nnkStmtList
  var libStmts = newStmtList()
  libStmts.doLibBlock body, false
  let builder = newProc(
    params = [
      newEmptyNode(),
      nnkIdentDefs.newTree(ident"ctx", bindSym"Context", newEmptyNode())
    ],
    body = libStmts
  )
  newLetStmt(name, nnkObjConstr.newTree(
    bindSym"DukLib",
    newColonExpr(ident"builder", builder),
    newColonExpr(ident"name", newStrLitNode $name)
  ))

