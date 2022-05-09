import futhark
import wasmedge/int128s
import std/[strutils, os, typetraits, strformat]

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
  of "Result":
    result = "WasmResult"
  elif result.endsWith"Context":
    result = "Wasm" & result
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
  WasmError* = object of CatchableError
    code*: uint32
  WasmLoadError* = object of WasmError
  WasmValidationError* = object of WasmError
  WasmInstantiationError* = object of WasmError
  WasmExecutionError* = object of WasmError
  WasmImportError* = object of WasmError

  WasmReturnVal* = distinct WasmValue

  ## String Types
  WasmString* = distinct WasmInternalString
  UnmanagedWasmString* = distinct WasmInternalString ## This string doesnt need destroyed, it reuses resources
  WasmStrings* = WasmString or UnmanagedWasmString

  ## Contexts only using `Context` suffix if the type would be commonly ambiguous
  ConfigureContext* = distinct ptr WasmConfigureContext
  LoaderContext* = distinct ptr WasmLoaderContext
  AstModuleContext* = distinct ptr WasmAstModuleContext
  VmContext* = distinct ptr WasmVmContext
  MemoryContext* = distinct ptr WasmMemoryInstanceContext
  ModuleContext* = distinct ptr WasmModuleInstanceContext
  ValidatorContext* = distinct ptr WasmValidatorContext
  StatisticsContext* = distinct ptr WasmStatisticsContext
  ExecutorContext* = distinct ptr WasmExecutorContext
  StoreContext* = distinct ptr WasmStoreContext


  FunctionInst* = distinct ptr WasmFunctionInstanceContext
  UnmanagedFunctionInst* = distinct ptr WasmFunctionInstanceContext ## This isnt owned by us we dont destroy it
  FunctionType* = distinct ptr WasmFunctionTypeContext
  UnmanagedFunctionType* = distinct ptr WasmFunctionTypeContext ## This isnt owned by us we dont destroy it

  FunctionTypes* = FunctionType or UnmanagedFunctionType
  FunctionInsts* = FunctionType or UnmanagedFunctionInst

  ImportType* = distinct ptr WasmImportTypeContext
  ExportType* = distinct ptr WasmExportTypeContext


  HostRegistration* = enumwasmedgehostregistration
  ValType* = enumwasmedgevaltype
  WasmParamList* = ptr UncheckedArray[WasmValue]

  HostProc*[T: ptr or ref] = proc(data: T, mem: MemoryContext, params, returns: WasmParamList): WasmResult ## If using `ref` ensure you `GcRef`

proc `=destroy`(str: var WasmString) =
  if str.distinctBase.length > 0 and str.distinctBase.buf != nil:
    stringDelete(WasmInternalString str)

template makeDestructor(t: typedesc, procName: untyped): untyped {.dirty.} =
  proc `=destroy`(toDestroy: var t) =
    if toDestroy.distinctBase != nil:
      procName(toDestroy.distinctBase)

# Consider making a macro, probably moot though
makeDestructor(ConfigureContext, configureDelete)
makeDestructor(VmContext, vmDelete)
makeDestructor(ModuleContext, moduleInstanceDelete)
makeDestructor(AstModuleContext, astModuleDelete)
makeDestructor(LoaderContext, loaderDelete)
makeDestructor(ValidatorContext, validatorDelete)
makeDestructor(StatisticsContext, statisticsDelete)
makeDestructor(ExecutorContext, executorDelete)


proc create*(_: typedesc[ConfigureContext]): ConfigureContext = ConfigureContext configureCreate()
proc create*(_: typedesc[StatisticsContext]): StatisticsContext = StatisticsContext statisticsCreate()
proc create*(_: typedesc[StoreContext]): StoreContext = StoreContext storeCreate()

proc createVm*(c: var ConfigureContext): VmContext = VmContext c.distinctBase.vmCreate(nil)
proc createLoader*(c: var ConfigureContext): LoaderContext = LoaderContext c.distinctBase.loaderCreate()
proc createExecutor*(c: var ConfigureContext): ExecutorContext = ExecutorContext c.distinctBase.executorCreate(nil)
proc createExecutor*(c: var ConfigureContext, stats: var StatisticsContext): ExecutorContext = ExecutorContext c.distinctBase.executorCreate(stats.distinctBase)
proc createValidator*(c: var ConfigureContext): ValidatorContext = ValidatorContext c.distinctBase.validatorCreate()

proc create*(_: typedesc[ModuleContext], name: WasmStrings): ModuleContext = ModuleContext moduleInstanceCreate(name.distinctBase)
proc create*(_: typedesc[ModuleContext], name: openarray[char]): ModuleContext = ModuleContext moduleInstanceCreate(name.unmanagedWasmString)
proc createWasiModule*(): ModuleContext = ModuleContext moduleInstanceCreateWasi(nil, 0, nil, 0, nil, 0)

proc add*(c: var ConfigureContext, host: HostRegistration) = c.distinctBase.configureAddHostRegistration(host)
proc has*(c: var ConfigureContext, host: HostRegistration): bool = c.distinctBase.configureHasHostRegistration(host)

template isOk*(res: WasmResult): bool = resultOk(res)
template isBad*(res: WasmResult): bool = not isOk(res)
template msg*(res: WasmResult): cstring = resultGetMessage(res)
template code*(res: WasmResult): uint32 = resultGetCode(res)


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

proc `$`*(val: WasmValue): string =
  case val.typefield
  of valTypei32:
    $val.getValue[: int32]
  of valTypei64:
    $val.getValue[: int64]
  of valTypef32:
    $val.getValue[: float32]
  of valTypef64:
    $val.getValue[: float64]
  of valTypeFuncRef:
    fmt"""FuncRef: {getValue[int64](val)}"""
  of valTypeExternRef:
    fmt"""ExternRef: {getValue[int64](val)}"""
  of valTypev128:
    "Some V128"
  of valTypeNone:
    "None"

template wasmString*(s: string): WasmString = WasmString stringCreateByCstring(s.cstring)
template wasmString*(s: cstring): WasmString = WasmString stringCreateByCstring(s)
proc wasmString*(oa: openarray[char or byte]): WasmString = WasmString stringCreateByBuffer(cast[cstring](oa[0].addr), uint32(oa.len))

template unmanagedWasmString*(s: string): UnmanagedWasmString = UnmanagedWasmString stringWrap(s.cstring, uint32 s.len)
template unmanagedWasmString*(s: cstring, len: uint32): UnmanagedWasmString = UnmanagedWasmString stringWrap(s, len)
proc unmanagedWasmString*(oa: openarray[char or byte]): UnmanagedWasmString = UnmanagedWasmString(stringWrap(oa[0].addr, uint32 oa.len))

proc `$`*(s: WasmStrings): string =
  result.setlen(256)
  let realLength = stringCopy(s.distinctBase, result.cstring, result.len.uint32)
  result.setLen(realLength.int)

proc `==`*(a, b: distinct WasmStrings): bool = stringIsEqual(a.distinctBase, b.distinctBase)
proc `==`*(a: string, b: WasmStrings): bool = stringIsEqual(unmanagedWasmString(a).distinctBase, b.distinctBase)
proc `==`*(a: WasmStrings, b: string): bool = stringIsEqual(a.distinctBase, unmanagedWasmString(b).distinctBase)


template checkResult*(res: WasmResult, excpt: typedesc[WasmError]) =
  if res.isBad:
    raise (ref excpt)(msg: $res.msg, code: res.code)

proc parseFromFile*(loader: var LoaderContext, ast: var AstModuleContext, name: openarray[char])=
  let res = loader.distinctBase.loaderParseFromFile(ast.distinctBase.addr, name[0].unsafeaddr)
  checkResult(res, WasmLoadError)

proc parseFromBuffer*(loader: var LoaderContext, ast: var AstModuleContext, buffer: openarray[char]) =
  let res = loader.distinctBase.loaderParseFromBuffer(ast.distinctBase.addr, cast[ptr uint8](buffer[0].unsafeaddr), buffer.len.uint32)
  checkResult(res, WasmLoadError)

proc loadWasmFromFile*(vm: var VmContext, file: string or cstring) =
  let res = vm.distinctBase.vmLoadWasmFromFile(file)
  checkResult(res, WasmLoadError)

proc validate*(vm: var VmContext) =
  let res = vm.distinctBase.vmValidate()
  checkResult(res, WasmValidationError)

proc validate*(validator: var ValidatorContext, ast: var AstModuleContext) =
  let res = validator.distinctBase.validatorValidate(ast.distinctBase)
  checkResult(res, WasmValidationError)

proc instantiate*(vm: var VMContext) =
  let res = vm.distinctBase.vmInstantiate()
  checkResult(res, WasmInstantiationError)

proc instantiate*(executor: var ExecutorContext, module: var ModuleContext, store: StoreContext, ast: AstModuleContext) =
  let res = executor.distinctBase.executorInstantiate(module.distinctBase.addr, store.distinctBase, ast.distinctBase)
  checkResult(res, WasmInstantiationError)

proc execute*(vm: var VmContext, name: WasmStrings, args, results: var openArray[WasmValue]) =
  let res = vm.distinctBase.vmExecute(WasmInternalString(name), args[0].addr, args.len.uint32, results[0].addr, results.len.uint32)
  checkResult(res, WasmExecutionError)

proc execute*(vm: var VmContext, name: string, args, results: var openArray[WasmValue]) =
  let funcName = unmanagedWasmString(name)
  let res = vm.distinctBase.vmExecute(WasmInternalString(funcName), args[0].addr, args.len.uint32, results[0].addr, results.len.uint32)
  checkResult(res, WasmExecutionError)

proc registerImport*(exec: var ExecutorContext, store: var StoreContext, hostMod: var ModuleContext) =
  let res = exec.distinctBase.executorRegisterImport(store.distinctBase, hostMod.distinctBase)
  checkResult(res, WasmImportError)

proc register*(executor: var ExecutorContext, module: var ModuleContext, store: var StoreContext, ast: var AstModuleContext, modName: WasmStrings) =
  let res = executor.distinctBase.executorRegister(module.distinctBase, store.distinctBase, ast.distinctBase, modName)
  checkResult(res, WasmImportError)

proc hookFunction*[T](params, results: openArray[ValType], prc: HostProc[T], data: T, cost = 0i32): FunctionInst =
  let hostFType =
    if params.len == 0 and results.len == 0:
      functionTypeCreate(nil, 0, nil, 0)
    elif params.len == 0:
      functionTypeCreate(nil, 0, results[0].addr, results.len)
    else:
      functionTypeCreate(params[0].addr, params.len.uint32 nil, 0)
  FunctionInst functionInstanceCreate(hostFtype, prc, data, cost)

proc findFunction*(module: var ModuleContext, name: WasmStrings): UnmanagedFunctionInst =
  UnmanagedFunctionInst module.distinctBase.moduleInstanceFindFunction(name.distinctBase)

proc funcType*(funcInst: var UnmanagedFunctionInst): UnmanagedFunctionType =
  assert funcInst.distinctBase != nil
  UnmanagedFunctionType funcInst.distinctBase.functionInstanceGetFunctionType()

proc invoke*(exec: var ExecutorContext, funcInst: UnmanagedFunctionInst, args, results: var openarray[WasmValue]) =
  assert funcInst.distinctBase != nil
  let res = exec.distinctBase.executorInvoke(funcInst.distinctBase, args[0].addr, args.len.uint32, results[0].addr, results.len.uint32)
  checkResult(res, WasmExecutionError)


proc initWasi*(module: var ModuleContext) =
  module.distinctBase.moduleInstanceInitWasi(nil, 0, nil, 0, nil, 0)

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

iterator importTypes*(ast: var AstModuleContext): ImportType =
  let importNum = ast.distinctBase.astModulelistImportsLength()
  var implTypes = newSeq[ImportType](importNum)
  let got = int ast.distinctBase.astModuleListImports(implTypes[0].distinctBase.addr, importNum)
  for x in implTypes.toOpenArray(0, got):
    yield x

iterator exportTypes*(ast: var AstModuleContext): ExportType =
  let exportNum = ast.distinctBase.astModulelistExportsLength()
  var implTypes = newSeq[ExportType](exportNum)
  let got = int ast.distinctBase.astModuleListExports(implTypes[0].distinctBase.addr, exportNum)
  for x in implTypes.toOpenArray(0, got):
    yield x

iterator modules*(store: var StoreContext): UnmanagedWasmString =
  let nameCount = store.distinctBase.storeListModuleLength()
  var modNames = newSeq[UnmanagedWasmString](nameCount)
  let got = int store.distinctBase.storeListModule(modNames[0].distinctBase.addr, nameCount)
  for x in modNames.toOpenArray(0, got):
    yield x

iterator functionNames*(module: var ModuleContext): UnmanagedWasmString =
  let funcNum = module.distinctBase.moduleInstanceListFunctionLength()
  var funcNames = newSeq[UnmanagedWasmString](funcNum)
  let got = int module.distinctBase.moduleInstanceListFunction(funcNames[0].distinctBase.addr, funcNum)
  for x in funcNames.toOpenArray(0, got - 1):
    yield x

iterator params*(funcType: FunctionType): ValType =
  let paramCount = funcType.distinctBase.functionTypeGetParametersLength()
  var paramTypes = newSeq[ValType](paramCount.int)
  discard funcType.distinctBase.functionTypeGetParameters(paramTypes[0].addr, paramCount)
  for paramType in paramTypes:
    yield paramType
