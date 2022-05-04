import futhark
import wasmedge/int128s
import std/[strutils, os]

proc removeWasmEdge(name, kind, partof: string): string =
  const prefix = "WasmEdge_"
  result =
    if name.startsWith(prefix):
      name[prefix.len..name.high]
    else:
      name
  case result:
  of "String":
    result = "WasmString"
  of "Value":
    result = "WasmValue"
  else: discard

  case kind
  of "const", "typedef":
    discard
  else:
    result[0] = result[0].toLowerAscii

const wasmedgePath {.strdefine.} = ""

importc:
  sysPath "/usr/lib/clang/13.0.1/include"
  path (wasmedgePath / "include")
  renameCallback removeWasmEdge
  "wasmedge/wasmedge.h"

{.passL:"-L" & wasmedgePath / "lib".}
{.passL:"-lwasmedge_c".}

type
  WasmTypes* = int32 or float32 or int64 or float64
  WasmLoadError* = object of CatchableError
  WasmValidationError* = object of CatchableError
  WasmInstantiationError* = object of CatchableError
  WasmExecutionError* = object of CatchableError



template isOk*(res: Result): bool = resultOk(res)
template isBad*(res: Result): bool = not isOk(res)
template msg*(res: Result): cstring = resultGetMessage(res)

template wasmValue*(i: int32): WasmValue = valueGenI32(i)
template wasmValue*(i: int64): WasmValue = valueGenI64(i)
template wasmValue*(f: float32): WasmValue = valueGenF32(f)
template wasmValue*(f: float64): WasmValue = valueGenF64(f)

proc getValue*[T: WasmTypes](val: WasmValue): T =
  when T is int32:
    valueGeti32(val)
  elif T is int64:
    valueGeti64(val)
  elif T is float32:
    valueGetf32(val)
  elif T is float64:
    valueGetF64(val)
  else: # Incase we add more types to `WasmTypes` later
    static: assert false

template wasmString*(s: string): WasmString = stringCreateByCstring(s.cstring)
template wasmString*(s: cstring): WasmString = stringCreateByCstring(s)
proc wasmString*(oa: openarray[char or byte]): WasmString = stringCreateByBuffer(cast[cstring](oa[0].addr), oa.len - 1)

proc loadWasmFromFile*(vm: ptr VmContext, file: string or cstring) =
  let res = vm.vmLoadWasmFromFile(file)
  if res.isBad:
    raise newException(WasmLoadError, $res.msg)

proc validate*(vm: ptr VmContext) =
  let res = vm.vmValidate()
  if res.isBad:
    raise newException(WasmValidationError, $res.msg)

proc instantiate*(vm: ptr VMContext) =
  let res = vm.vmInstantiate()
  if res.isBad:
    raise newException(WasmInstantiationError, $res.msg)

proc execute*(vm: ptr VmContext, name: WasmString, args, results: var openArray[WasmValue]) =
  let res = vm.vmExecute(name, args[0].addr, args.len.uint32, results[0].addr, results.len.uint32)
  if res.isBad:
    raise newException(WasmExecutionError, $res.msg)
