import futhark
import int128s
import std/strutils

proc removeWasmEdge(name, kind, partof: string): string =
  const prefix = "WasmEdge_"
  result =
    if name.startsWith(prefix):
      name[prefix.len..name.high]
    else:
      name
  case kind
  of "const", "typedef":
    discard
  else:
    result[0] = result[0].toLowerAscii

importc:
  sysPath "/usr/lib/clang/13.0.1/include"
  path "/home/jason/.wasmedge/include/"
  renameCallback removeWasmEdge
  "wasmedge/wasmedge.h"

type WasmTypes = int32 or float32 or int64 or float64


template isOk*(res: Result): bool = resultOk(res)
template isBad*(res: Result): bool = not isOk(res)
template msg*(res: Result): cstring = resultGetMessage(res)

template wasmValue*(i: int32): Value = valueGenI32(i)
template wasmValue*(i: int64): Value = valueGenI64(i)
template wasmValue*(f: float32): Value = valueGenF32(f)
template wasmValue*(f: float64): Value = valueGenF64(f)

proc getValue*[T: WasmTypes](val: Value): T =
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

template wasmString*(s: string): String = stringCreateByCstring(s.cstring)
template wasmString*(s: cstring): String = stringCreateByCstring(s)
template wasmString*(oa: openarray[char or byte]): String = stringCreateByBuffer(oa[0].addr, oa.len - 1)

proc main() =
  echo "WasmEdge Version: ", versionGet()
  let confCtx = configureCreate()
  confCtx.configureAddHostRegistration(hostRegistrationWasi)
  let
    vmCtx = confCtx.vmCreate(nil)
    params = [wasmValue(10i32), wasmValue(30i32)]
    returns = [Value()]
    funcName = wasmString("add")
  var result = vmCtx.vmLoadWasmFromFile("adds.wasm")

  if result.isBad:
    echo "Loading failed: ", resultGetMessage(result)
    return
  result = vmValidate(vmCtx)

  if result.isBad:
    echo "Validation failed: ", resultGetMessage(result)
    return

  result = vmCtx.vmInstantiate()
  if result.isBad:
    echo "Instantiation failed: ", resultGetMessage(result)
    return


  result = vmCtx.vmExecute(funcName, params[0].unsafeaddr, 2, returns[0].unsafeaddr, 1)

  if result.isOk:
    echo "The value is: ", returns[0].getValue[:int32]()
  else:
    echo "Execution failed: ", resultGetMessage(result)

  vmDelete(vmCtx)
  configureDelete(confCtx)
  stringDelete(funcName)
main()
