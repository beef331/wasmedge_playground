import unittest
import wasmedge


type MyType = object
  x, y, z: int32
  w: float32

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

  proc myProc(data: pointer, mem: MemoryInst, params, returns: WasmParamList): WasmResult {.cdecl.} =
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

  var myType = MyType(x: 100, y: 1, z: 3, w: 30)
  let
    getMyType = module.findFunction(wasmString"getMyType")
    myMemory = module.findMemory(wasmString"memory")
  executor.invoke(getMyType)
  myMemory.getData(myType)
  check myType == MyType(x: 100, y: 300, z: 300, w: 15)

  var
    args = [wasmValue(10i32), wasmValue(11i32)]
    results = [WasmValue()]


  let funcName = module.findFunction(wasmString"indirectCall")

  executor.invoke(funcName, args, results)

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
    res.add ")"

    var hasResults = false
    for resultTyp in myTypeFunc.funcType.returns:
      if not hasResults:
        hasResults = true
        res.add ": ("
      res.add $resultTyp
      res.add " "
    if hasResults:
      res.setLen(res.high)
      res.add ")"

    res.add "\n"
    procDefs.add res
  const expected = """

proc __errno_location(): (valtypei32)
proc _initialize()
proc emscripten_builtin_memalign(valtypei32 valtypei32): (valtypei32)
proc emscripten_stack_get_base(): (valtypei32)
proc emscripten_stack_get_end(): (valtypei32)
proc emscripten_stack_get_free(): (valtypei32)
proc emscripten_stack_init()
proc getFloat(valtypei32 valtypei32): (valtypef32)
proc getMyType()
proc indirectCall(valtypei32 valtypei32)
proc stackAlloc(valtypei32): (valtypei32)
proc stackRestore(valtypei32)
proc stackSave(): (valtypei32)
"""
  check expected == procDefs
