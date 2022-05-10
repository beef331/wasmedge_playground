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
    returns[0] = wasmValue(params[0].getValue[: int32]() * params[1].getValue[: int32]())
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

  var myTypeFunc = module.findFunction(wasmString"getMyType")
  var procDefs = "\n"
  for funcName in module.functionNames:
    var myTypeFunc = module.findFunction(funcName)
    var res = "proc "
    res.add $funcName
    res.add "("
    for param in myTypeFunc.funcType.params:
      res.add $param
      res.add " "
    if res[^1] == ' ':
      res.setlen(res.high)
    res.add ")\n"
    procDefs.add res
  const expected = """

proc __errno_location()
proc _initialize()
proc emscripten_builtin_memalign(valtypei32 valtypei32)
proc emscripten_stack_get_base()
proc emscripten_stack_get_end()
proc emscripten_stack_get_free()
proc emscripten_stack_init()
proc getMyType(valtypei32 valtypei32)
proc indirectCall(valtypei32 valtypei32)
proc stackAlloc(valtypei32)
proc stackRestore(valtypei32)
proc stackSave()
"""
  check expected == procDefs


