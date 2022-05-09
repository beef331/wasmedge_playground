import unittest
import wasmedge
test "HostFunctions":
  var
    config = ConfigureContext.create()
    stats = StatisticsContext.create()
    loader = config.createLoader()
    validator = config.createValidator()
    executor = config.createExecutor(stats)
    ast: AstModuleContext
    wasiModule = createWasiModule()

  loader.parseFromFile(ast, "hooks.wasm")
  validator.validate(ast)

  var store = StoreContext.create()

  executor.registerImport(store, wasiModule)

  proc myProc(data: pointer, mem: MemoryContext, params, returns: WasmParamList): WasmResult {.cdecl.} =
    echo params[0].getValue[: int32](), " ", params[1].getValue[: int32]()
    WasmResult()

  var myModule = ModuleContext.create(wasmString"env")
  let
    funcType = FunctionType.create([valTypei32, valTypei32], [valTypei32])
    funcInst = funcType.createInst(myProc)

  myModule.addFunction(wasmString"doThing", funcInst)
  executor.registerImport(store, myModule)

  var module = ModuleContext.default
  executor.instantiate(module, store, ast)
  var
    args = [wasmValue(10i32), wasmValue(11i32)]
    results = [WasmValue()]


  let funcName = module.findFunction(wasmString"indirectCall")

  executor.invoke(funcName, args, results)


