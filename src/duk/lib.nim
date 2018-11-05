import os
import duktape_wrapper
import ctx_val_proc
import sequtils

type
  MemoryFunctions* =
    tuple[alloc: AllocFunction, realloc: ReallocFunction, free: FreeFunction]
  JSType* = enum
    jstMinNone = 0, jstUndefined = 1, jstNull = 2, jstBoolean = 3,
    jstNumber = 4, jstString = 5, jstObject = 6, jstBuffer = 7, jstPointer = 8,
    jstLightFuncMax = 9, jstArray
  JSValObj* = object
    case ty*: JSType
    of jstMinNone, jstUndefined, jstNull: discard
    of jstBoolean: booleanVal*: bool
    of jstNumber: numberVal*: cdouble
    of jstString: stringVal*: cstring
    of jstObject: discard # TODO: Implement object representation
    of jstBuffer:
      bufferVal*: pointer
      bufferSize: cint
    of jstPointer: pointerVal*: pointer
    of jstLightFuncmax: discard # TODO: Implement lightfunc representation
    of jstArray: arrayVal*: seq[JSVal]
  JSVal* = ref JSValObj

proc getJSType*(ctx: Context, idx: IdxT): JSType {.dukCtxPtrProc.} =
  let ty = ctx.getType(idx)
  if ctx.isArray(idx).cint == 1:
    jstArray
  else:
    ty.JSType
    
import converters
export converters

proc `[]`*(ctx: Context, idx: IdxT): StackPtr =
  if not ctx.isValidIndex(idx).toBool:
    raise newException(IndexError, "Index " & $idx & " is not valid for context")
  (ctx: ctx, idx: idx)
template `[]`*(ctx: Context, idx: BackwardsIndex): StackPtr =
  ctx[-idx.IdxT]
proc len*(ctx: Context): int =
  ctx.getTop()

proc top*(ctx: Context): StackPtr = ctx[ctx.getTopIndex()]

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

template errorRaw*(ctx: Context, errCode: ErrcodeT, msg: string) =
  let info = instantiationInfo()
  ctx.errorRaw(errCode, info.filename.cstring, info.line.cint, "%s", msg.cstring)

proc genericError*(ctx: Context, msg: string) = ctx.errorRaw(DUK_ERR_ERROR, msg)
proc evalError*(ctx: Context, msg: string) = ctx.errorRaw(DUK_ERR_EVAL_ERROR, msg)
proc rangeError*(ctx: Context, msg: string) = ctx.errorRaw(DUK_ERR_RANGE_ERROR, msg)
proc referenceError*(ctx: Context, msg: string) = ctx.errorRaw(DUK_ERR_REFERENCE_ERROR, msg)
proc syntaxError*(ctx: Context, msg: string) = ctx.errorRaw(DUK_ERR_SYNTAX_ERROR, msg)
proc typeError*(ctx: Context, msg: string) = ctx.errorRaw(DUK_ERR_TYPE_ERROR, msg)
proc uriError*(ctx: Context, msg: string) = ctx.errorRaw(DUK_ERR_URI_ERROR, msg)

proc `=`(d: var Context, src: Context) {.borrow.}

iterator enumNext*(ctx: Context, idx: IdxT): StackPtr {.dukCtxPtrProc.} =
  while ctx[idx].next(false):
    yield ctx[^1]
    ctx.pop()

iterator enumNextValue*(ctx: Context, idx: IdxT): (StackPtr, StackPtr) {.dukCtxPtrProc.} =
  while ctx[idx].next(true):
    yield (ctx[^2], ctx[^1])
    ctx.pop2()

proc getArray*(ctx: Context, idx: IdxT): seq[StackPtr] {.dukCtxPtrProc.} =
  ctx.`enum`(idx, 1 shl 5)
  result = mapIt(toSeq ctx.enumNextValue(idx), it[1])
  ctx.pop()

template pushVal*(ctx: Context, val: int) = ctx.pushInt val.cint
template pushVal*(ctx: Context, val: string) = ctx.pushString val.cstring
template pushVal*(ctx: Context, val: cdouble) = ctx.pushNumber val
template pushVal*(ctx: Context, val: CFunction) = ctx.pushCFunction val
template pushVal*(ctx: Context, val: bool) = ctx.pushBoolean val
template tmpltPushArray(ctx: Context, arr: openarray[JSVal]) =
  let arrIdx = ctx.pushArray()
  for i, val in arr:
    ctx.pushVal val
    discard ctx.putPropIndex(arrIdx, i.uint)
proc pushBuffer*(ctx: Context, buf: pointer, len: cint) =
  discard ctx.pushBufferRaw(len, 1 shl 1)
  ctx.configBuffer -1, buf, len
proc pushVal*(ctx: Context, val: JSVal) =
  case val.ty
  of jstMinNone: discard
  of jstUndefined: ctx.pushUndefined
  of jstNull: ctx.pushNull
  of jstBoolean: ctx.pushBoolean val.booleanVal
  of jstNumber: ctx.pushNumber val.numberVal
  of jstString: discard ctx.pushLstring(val.stringVal, val.stringVal.len.cint)
  of jstObject: discard # TODO: Implement object representation
  of jstBuffer: ctx.pushBuffer val.bufferVal, val.bufferSize
  of jstPointer: ctx.pushPointer val.pointerVal
  of jstLightFuncmax: discard # TODO: Implement lightfunc representation
  of jstArray: ctx.tmpltPushArray val.arrayVal

proc pushArray*(ctx: Context, arr: openarray[JSVal]) {.dukCtxPtrProc.} =
  ctx.tmpltPushArray(arr)

proc requireArray*(ctx: Context, idx: IdxT): seq[StackPtr] {.dukCtxPtrProc.} =
  let val = ctx[idx]
  if not val.isArray:
    ctx.typeError(
      "Array required, found " & val.getTypeString & " (stack index " & $idx & ")"
    )
  val.getArray

template jsSeq*(arr: varargs[JSVal, newJSVal]): seq[JSVal] =
  toSeq arr.items
template newJSArray*(arr: varargs[untyped, newJSVal]): JSVal =
  JSVal(ty: jstArray, arrayVal: arr)

proc loadFile*(ctx: Context, filename: string) =
  ctx.loadJS readFile filename, filename

proc getJSVal*(val: StackPtr): JSVal =
  let ty = val.getJSType
  result.ty = ty
  case ty
  of jstBoolean: result.booleanVal = val.getBoolean()
  of jstNumber: result.numberVal = val.getNumber()
  of jstString: result.stringVal = val.getString()
  of jstObject: discard # TODO: Implement object representation
  of jstBuffer: result.bufferVal = val.getBuffer(addr result.bufferSize)
  of jstPointer: result.pointerVal = val.getPointer()
  of jstLightFuncmax: discard # TODO: Implement lightfunc representation
  of jstArray: result.arrayVal = mapIt(val.getArray(), it.getJsVal)
  else: discard # don't have fields in JSValObj
proc getJSVal*(ctx: Context, idx: IdxT): JSVal = ctx[idx].getJSVal
