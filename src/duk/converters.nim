import duk_wrapper

import lib

proc getTypeString*(val: JSVal): string =
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
  case dukBool
  of 0.BoolT, 1.BoolT: cint(dukBool) == 1
  else: raise newException(
    Exception,
    "Invalid value for `duk.BoolT`, why are you making your own `BoolT`s"
  )


converter convToBool*(val: JSVal): bool = val.requireBoolean

converter convToString*(val: JSVal): string = $val.requireString

converter convToInt*(val: JSVal): int = val.requireInt

converter convToNumber*(val: JSVal): cdouble = val.requireNumber

converter convToPtr*(val: JSVal): ptr = val.requirePointer

proc `$`*(val: JSVal): string =
  val.dup()
  result = $val.ctx[0].toString()
  val.ctx.pop()
