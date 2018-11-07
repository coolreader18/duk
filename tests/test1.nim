# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest

import os, terminal, strutils, sets
import duk

duklib testLib:
  proc test(name: JSString, fn: StackPtr) =
    test $name:
      fn.dup()
      let failed = ctx.pcall(0) != 0
      var errMsg: string
      if failed:
        ctx[^1].`enum`(0)
        for k in ctx[^1].enumNext:
          echo k
        ctx.pop()
      ctx.pop2()
      if failed:
        styledEcho styleBright, fgRed, "error: ", resetStyle, errMsg 
        fail()
  proc assert(cond: JSBool, msg: JSString) =
    if not cond:
      ctx.errorRaw DUK_ERR_ERROR, "Assertion failed"

  proc print(args: varargs[string, `$`]) =
    for a in args:
      echo a

const sourcePath = currentSourcePath().split({'\\', '/'})[0..^2].join("/")

proc makeCtx(): Context =
  result = createHeap()
  result.injectLibGlobal testLib
proc makeCtx(file: string, lib: DukLib = nil): Context =
  result = makeCtx()
  if lib != nil:
    result.injectLibGlobal lib
  result.loadFile sourcePath / file

var crossVar = 0

duklib setLib:
  proc setVar(newA, b: JSInt) =
    crossVar = newA
    echo b

  proc get22(): JSInt =
    22

test "set values":
  var ctx = makeCtx("settest.js", setLib)
  echo "val of crossVar: ", crossVar
  check crossVar == 22

duklib generalLib:
  proc rawCtx(ctx: Context): RetT =
    discard
  
  proc getArr(): JSSeq =
    jsSeq(9, 10)

  sublib asd:
    proc nested(str: JSString): JSInt =
      JSInt str.len

suite "general_js_tests":
  var ctx = makeCtx()
  ctx.injectLibGlobal generalLib
  ctx.injectLibNamespace generalLib, "tester"
  ctx.loadFile sourcePath / "test.js"
