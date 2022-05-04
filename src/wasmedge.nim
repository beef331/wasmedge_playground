import futhark
import wasmedge/int128s
import std/[strutils, os, typetraits]

proc removeWasmEdge(name, kind, partof: string): string =
  const prefix = "WasmEdge_"
  result =
    if name.startsWith(prefix):
      name[prefix.len..name.high]
    else:
      name
  case result:
  of "String":
    result = "WasmInternalString"
  of "Value":
    result = "WasmValue"
  of "ConfigureContext":
    result = "WasmInternalConfContext"
  of "VMContext":
    result = "WasmVmContext"
  else: discard

  case kind
  of "const", "typedef", "enum":
    discard
  else:
    result[0] = result[0].toLowerAscii

const wasmedgePath {.strdefine.} = ""

importc:
  sysPath "/usr/lib/clang/13.0.1/include"
  path (wasmedgePath / "include")
  renameCallback removeWasmEdge
  "wasmedge/wasmedge.h"
when wasmedgePath.len > 0: # Only add link path if we've data
  {.passL:"-L" & wasmedgePath / "lib".}
{.passL:"-lwasmedge_c".}

type
  WasmTypes* = int32 or float32 or int64 or float64
  WasmLoadError* = object of CatchableError
  WasmValidationError* = object of CatchableError
  WasmInstantiationError* = object of CatchableError
  WasmExecutionError* = object of CatchableError

  ## String Types
  WasmString* = distinct WasmInternalString
  UnmanagedWasmString* = distinct WasmInternalString ## This string doesnt need destroyed, it reuses resources
  WasmStrings* = WasmString or UnmanagedWasmString

  ConfigureContext = distinct ptr WasmInternalConfContext
  VmContext = distinct ptr WasmVmContext
  HostRegistration* = enumwasmedgehostregistration
  ValType* = enumwasmedgevaltype
  FunctionType* = distinct ptr FunctionTypeContext

proc `=destroy`(str: var WasmString) =
  if str.distinctBase.length > 0 and str.distinctBase.buf != nil:
    stringDelete(WasmInternalString str)

proc `=destroy`(conf: var ConfigureContext) =
  if (ptr WasmInternalConfContext)(conf) != nil:
    configureDelete((ptr WasmInternalConfContext)(conf))

proc `=destroy`(vm: var VmContext) =
  if vm.distinctBase != nil:
    vmDelete(vm.distinctBase)


proc createConfigureContext*(): ConfigureContext = ConfigureContext configureCreate()
proc vmCreate*(c: var ConfigureContext): VmContext = VmContext(c.distinctBase.vmCreate(nil))
proc add*(c: var ConfigureContext, host: HostRegistration) = c.distinctBase.configureAddHostRegistration(host)


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

template wasmString*(s: string): WasmString = WasmString stringCreateByCstring(s.cstring)
template wasmString*(s: cstring): WasmString = WasmString stringCreateByCstring(s)
proc wasmString*(oa: openarray[char or byte]): WasmString = stringCreateByBuffer(cast[cstring](oa[0].addr), oa.len - 1)

template unmanagedWasmString*(s: string): UnmanagedWasmString = UnmanagedWasmString wasmString(s)
template unmanagedWasmString*(s: cstring, len: uint32): UnmanagedWasmString = UnmanagedWasmString wasmString(s[0], len)
proc unmanagedWasmString*(oa: openarray[char or byte]): UnmanagedWasmString = UnmanagedWasmString(wasmString(oa))

proc `$`*(s: WasmStrings): string =
  result.setlen(256)
  let realLength = stringCopy(s.distinctBase, result.cstring, result.len.uint32)
  result.setLen(realLength.int)

proc `==`*(a, b: distinct WasmStrings): bool = stringIsEqual(a.distinctBase, b.distinctBase)
proc `==`*(a: string, b: WasmStrings): bool = stringIsEqual(unmanagedWasmString(a).distinctBase, b.distinctBase)
proc `==`*(a: WasmStrings, b: string): bool = stringIsEqual(a.distinctBase, unmanagedWasmString(b).distinctBase)


proc loadWasmFromFile*(vm: var VmContext, file: string or cstring) =
  let res = vm.distinctBase.vmLoadWasmFromFile(file)
  if res.isBad:
    raise newException(WasmLoadError, $res.msg)

proc validate*(vm: var VmContext) =
  let res = vm.distinctBase.vmValidate()
  if res.isBad:
    raise newException(WasmValidationError, $res.msg)

proc instantiate*(vm: var VMContext) =
  let res = vm.distinctBase.vmInstantiate()
  if res.isBad:
    raise newException(WasmInstantiationError, $res.msg)

proc execute*(vm: var VmContext, name: WasmStrings, args, results: var openArray[WasmValue]) =
  let res = vm.distinctBase.vmExecute(WasmInternalString(name), args[0].addr, args.len.uint32, results[0].addr, results.len.uint32)
  if res.isBad:
    raise newException(WasmExecutionError, $res.msg)

proc execute*(vm: var VmContext, name: string, args, results: var openArray[WasmValue]) =
  let funcName = unmanagedWasmString(name)
  let res = vm.distinctBase.vmExecute(WasmInternalString(funcName), args[0].addr, args.len.uint32, results[0].addr, results.len.uint32)
  if res.isBad:
    raise newException(WasmExecutionError, $res.msg)

iterator functionNames*(vm: VmContext, count = 128): UnmanagedWasmString =
  ## yields the function names for `count` functions in the VM
  var
    funcNames = newSeq[UnmanagedWasmString](count)
    funcTypes = newSeq[FunctionType](count)
  let realCount = int vm.distinctBase.vmGetFunctionList(funcNames[0].distinctBase.addr, funcTypes[0].distinctBase.addr, count.uint32 - 1)
  funcNames.setLen(realCount)
  funcTypes.setLen(realCount)
  for x in funcNames:
    yield x

iterator functionNameTypes*(vm: VmContext, count = 128): (UnmanagedWasmString, FunctionType) =
  ## yields the function names and types for `count` functions in the VM
  var
    funcNames = newSeq[UnmanagedWasmString](count)
    funcTypes = newSeq[FunctionType](count)
  let realCount = int vm.distinctBase.vmGetFunctionList(funcNames[0].distinctBase.addr, funcTypes[0].distinctBase.addr, count.uint32 - 1)
  funcNames.setLen(realCount)
  funcTypes.setLen(realCount)
  for i, x in funcNames:
    yield (x, funcTypes[i])

iterator params*(funcType: FunctionType): ValType =
  let paramCount = funcType.distinctBase.functionTypeGetParametersLength()
  var paramTypes = newSeq[ValType](paramCount.int)
  let gotCount = funcType.distinctBase.functionTypeGetParameters(paramTypes[0].addr, paramCount)
  for paramType in paramTypes:
    yield paramType

