import os
import duk_wrapper
import macros

type
  MemoryFunctions* = ref object
    alloc: AllocFunction
    realloc: ReallocFunction
    free: FreeFunction
  WrongTypeException* = object of Exception

import converters
export converters

proc `[]`*(ctx: Context, idx: IdxT): JSVal =
  JSVal(ctx: ctx, idx: idx)
proc `[]`*(ctx: Context, idx: BackwardsIndex): JSVal =
  JSVal(ctx: ctx, idx: -int(idx))
proc len*(ctx: Context): int =
  ctx.getTop()

proc top*(ctx: Context): JSVal = ctx[ctx.getTopIndex()]

template defaultAllocFuncs: MemoryFunctions =
  MemoryFunctions(alloc: nil, realloc: nil, free: nil)

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

import lib_macro
export lib_macro