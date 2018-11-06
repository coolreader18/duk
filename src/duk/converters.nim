import duktape_wrapper

import lib

proc getTypeString*(val: StackPtr): string =
  case val.getJSType()
  of jstMinNone: "none"
  of jstUndefined: "undefined"
  of jstNull: "null"
  of jstBoolean: "boolean"
  of jstNumber: "number"
  of jstString: "string"
  of jstObject, jstArray, jstBuffer: "object"
  of jstPointer: "pointer"
  of jstLightFuncMax: "function"
  
# it's not just a normal int, it's meant to represent a boolean
converter toBool*(dukBool: BoolT): bool =
  case dukBool.cint
  of 0, 1: dukBool.cint == 1
  else: raise newException(
    Exception,
    "Invalid value for `duk.BoolT`, why are you making your own `BoolT`s"
  )
converter toBoolT*(boolean: bool): BoolT =
  if boolean: 1.BoolT
  else: 0.BoolT

proc `$`*(val: StackPtr): string =
  val.dup()
  result = $val.ctx.toString(-1)
  val.ctx.pop()

converter newJSVal*(num: SomeNumber): JSVal =
  JSVal(ty: jstNumber, numberVal: num.cdouble)
converter newJSVal*(str: string): JSVal =
  JSVal(ty: jstString, stringVal: str.cstring)
converter newJSVal*(boolean: bool): JSVal =
  JSVal(ty: jstBoolean, booleanVal: boolean)
converter newJSVal*(arr: seq[JSVal]): JSVal =
  JSVal(ty: jstArray, arrayVal: arr)
# string, number, int, array
template pushAny*(ctx: Context, num: cdouble) = ctx.pushNumber num
template pushAny*(ctx: Context, num: cint) = ctx.pushInt num
template pushAny*(ctx: Context, str: string) = ctx.pushLstring str.cstring, str.len
template pushAny*(ctx: Context, boolean: bool) = ctx.pushBoolean boolean
template pushAny*(ctx: Context, arr: seq[JSVal]) = ctx.pushArray arr