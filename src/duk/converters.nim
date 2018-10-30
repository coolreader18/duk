import duktape_wrapper

import lib

proc getTypeString*(val: StackPtr): string =
  case val.getDukType()
  of dtMinNone: "none"
  of dtUndefined: "undefined"
  of dtNull: "null"
  of dtBoolean: "boolean"
  of dtNumber: "number"
  of dtString: "string"
  of dtObject: "object"
  of dtBuffer: "buffer"
  of dtPointer: "pointer"
  of dtLightFuncMax: "function"
  
# it's not just a normal int, it's meant to represent a boolean
converter toBool*(dukBool: BoolT): bool =
  case dukBool.cint
  of 0, 1: dukBool.cint == 1
  else: raise newException(
    Exception,
    "Invalid value for `duk.BoolT`, why are you making your own `BoolT`s"
  )

proc `$`*(val: StackPtr): string =
  val.dup()
  result = $val.ctx.toString(-1)
  val.ctx.pop()
