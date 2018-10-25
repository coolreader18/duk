# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest

import duk
import os

const testjs = staticRead("test.js")

var a = 2

duklib testLib:
  proc print(arg: JSString) =
    echo arg

  proc setA(newA: JSInt) =
    a = newA



test "ffi":
  var ctx = createHeap()
  ctx.injectLib testLib
  discard ctx.pushString(testjs)
  discard ctx.pushString("test.js")
  discard ctx.compileRaw(nil, 0, 2)
  discard ctx.pcall(0)
  ctx.pop()
  echo "val of a: ", a
  check a == 9
