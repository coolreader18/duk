# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest

import duk
import os

var a = 2

duklib testLib:
  proc print(args: varargs[typed, `$`]) =
    for a in args:
      echo a

  proc setA(newA, b: JSInt) =
    a = newA
    echo b

  proc get22(): JSInt =
    22
  
  proc rawCtx(ctx: Context): RetT =
    discard
  
  proc getArr(): JSSeq =
    jsSeq(9, 10)

  sublib asd:
    proc nested(str: JSString): JSInt =
      JSInt str.len


const testjs = staticRead"test.js"

# var ctx: Context
# ctx.pushArray()

import strutils
test "ffi":
  var ctx = createHeap()
  ctx.injectLib testLib
  const sourcePath = currentSourcePath().split({'\\', '/'})[0..^2].join("/")
  ctx.loadFile sourcePath / "test.js"
  echo "val of a: ", a
  check a == 22
