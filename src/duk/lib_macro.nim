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
  JSInt* = int
  
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
    if cParams.len == 2 and $cParams[1][^2] == "Context":
      outStmts.addFunc name, child, -1
    else:
      var params = newSeq[(string, JSType)]()
      for i in 1..<cParams.len:
        let param = cParams[i]
        let jsTy = getJSType $param[^2]
        param.expect(
          jsTy != jstNot,
          "Types for parameters in duk lib function must all be a JS`Type`"
        )
        for parmIdent in toSeq(param.children)[0..^3]:
          params.add ($parmIdent, jsTy)
      var cFnStmts = newStmtList()
      let letSec = nnkLetSection.newNimNode
      for i, tup in params:
        let (name, ty) = tup
        letSec.add nnkIdentDefs.newTree(
          ident name,
          newEmptyNode(),
          newCall(ty.getRequireFn, ident"ctx", newIntLitNode i)
        )
      cFnStmts.add letSec
      child.name = ident"__cfn"
      cFnStmts.add child
      let cFnCall = newCall(
        ident"__cfn",
        params.mapIt ident it[0]
      )
      cFnStmts.add if cParams[0].kind == nnkEmpty:
          cFnCall
        else:
          nnkDiscardStmt.newTree cFnCall
      let outProc = newProc(
        params = [bindSym"RetT", nnkIdentDefs.newTree(ident"ctx", bindSym"Context", newEmptyNode())],
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
  newLetStmt(name, nnkObjConstr.newTree(
    bindSym"DukLib",
    newColonExpr(ident"builder", builder),
    newColonExpr(ident"name", newStrLitNode $name)
  ))


