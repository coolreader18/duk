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
  proc print(arg: JSString) =
    echo arg

  proc setA(newA: JSInt) =
    a = newA

  proc get22(): JSInt =
    22
  
  proc rawCtx(ctx: Context): RetT =
    discard

const testjs = staticRead"test.js"

test "ffi":
  var ctx = createHeap()
  ctx.injectLib testLib
  ctx.loadJS testjs, "test.js"
  ctx.pop()
  echo "val of a: ", a
  check a == 22
