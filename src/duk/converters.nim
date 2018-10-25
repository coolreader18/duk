import duk_wrapper

import lib

proc getTypeString*(val: JSVal): string =
  case val.getType()
  of DUK_TYPE_NONE: "none"
  of DUK_TYPE_UNDEFINED: "undefined"
  of DUK_TYPE_NULL: "null"
  of DUK_TYPE_BOOLEAN: "boolean"
  of DUK_TYPE_NUMBER: "number"
  of DUK_TYPE_STRING: "string"
  of DUK_TYPE_OBJECT: "object"
  of DUK_TYPE_BUFFER: "buffer"
  of DUK_TYPE_POINTER: "pointer"
  of DUK_TYPE_LIGHTFUNC: "lightfunc"
  else: "unknown"
  
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

template `$`*(val: JSVal): string = val.convToString
 
converter convToInt*(val: JSVal): int = val.requireInt

converter convToNumber*(val: JSVal): cdouble = val.requireNumber
 
converter convToPtr*(val: JSVal): ptr = val.requirePointer

