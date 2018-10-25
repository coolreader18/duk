import macros, sequtils, sugar

import duk_wrapper

proc error(n: NimNode, msg: string) = error(msg, n)
proc expect(n: NimNode, cond: bool, msg: string) =
  if not cond: n.error(msg)

proc addFunc(libStmts: var NimNode; name: string; fn: NimNode, nargs: int) =
  libStmts.add nnkStmtList.newTree(
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

proc doLibBlock(outStmts: var NimNode, stmtList: NimNode, isObj: bool, objName: string = "") =
  outStmts.add newCall(
    if isObj: bindSym"pushBareObject" else: bindSym"pushGlobalObject",
    ident"ctx"
  )
  for child in stmtList.children:
    child.expectKind nnkProcDef
    let name = $child.name
    child.name = newEmptyNode()
    let cParams = child.params
    let retParam = cParams[0]
    if cParams.len == 2 and cParams[1][^2] == bindSym"Context":
      retParam.expect(
        retParam.kind != nnkEmpty and retParam[^2] == bindSym"RetT",
        "Return type for processing the raw context must be `RetT`"
      )
      outStmts.addFunc name, child, -1
    else:
      var params = newSeq[JSType]()
      for i in 1..<cParams.len:
        let param = cParams[i]
        let jsTy = getJSType $param[^2]
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
      let cFnCall = newCall(
        newPar child,
        args
      )
      if cParams[0].kind == nnkEmpty:
        cfnStmts. add cFnCall
      else:
        cfnStmts.add newCall(
          getJSType($retParam).getPushFn,
          ident"ctx",
          cFnCall
        ), nnkDotExpr.newTree(newIntLitNode 1, bindSym"RetT")
      let outProc = newProc(
        params = [
          bindSym"RetT",
          nnkIdentDefs.newTree(ident"ctx", bindSym"Context", newEmptyNode())
        ],
        body = cFnStmts,
      )
      outProc.addPragma ident"cdecl"
      outStmts.addFunc name, outProc, params.len
  outStmts.add newCall(bindSym"pop", ident"ctx")

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
  echo repr builder
  newLetStmt(name, nnkObjConstr.newTree(
    bindSym"DukLib",
    newColonExpr(ident"builder", builder),
    newColonExpr(ident"name", newStrLitNode $name)
  ))


