import os
import duk_wrapper
import macros

type
  MemoryFunctions* = tuple[
    alloc: AllocFunction,
    realloc: ReallocFunction,
    free: FreeFunction
  ]
  WrongTypeException* = object of Exception

type DukType* = enum
  dtMinNone = 0, dtUndefined = 1, dtNull = 2, dtBoolean = 3, dtNumber = 4,
  dtString = 5, dtObject = 6, dtBuffer = 7, dtPointer = 8, dtLightFuncMax = 9

template getDukType*(ctx: Context, idx: IdxT): DukType =
  DukType ctx.getType(idx)
template getDukType*(val: JSVal): DukType =
  getDukType(val.ctx, val.idx)

import converters
export converters

proc `[]`*(ctx: Context, idx: IdxT): JSVal =
  JSVal(ctx: ctx, idx: idx)
proc `[]`*(ctx: Context, idx: BackwardsIndex): JSVal =
  JSVal(ctx: ctx, idx: -int(idx))
proc len*(ctx: Context): int =
  ctx.getTop()

proc top*(ctx: Context): JSVal = ctx[ctx.getTopIndex()]

const defaultAllocFuncs: MemoryFunctions = (alloc: nil, realloc: nil, free: nil)

proc createHeap*(
    heapUdata: pointer = nil,
    fatalHandler: FatalFunction = nil,
    allocFuncs: MemoryFunctions = defaultAllocFuncs
  ): Context =
  createHeap(
    allocFuncs.alloc,
    allocFuncs.realloc,
    allocFuncs.free,
    heapUdata,
    fatalHandler
  )

proc `=destroy`(ctx: var Context) =
  ctx.destroyHeap()

proc loadJS*(ctx: Context, text, filename: string) =
  discard ctx.pushString(text)
  discard ctx.pushString(filename)
  discard ctx.compileRaw(nil, 0, 2)
  discard ctx.pcall(0)
  ctx.pop()

proc loadFile*(ctx: Context, filename: string) =
  ctx.loadJS readFile filename, filename
    
import lib_macro
export lib_macro