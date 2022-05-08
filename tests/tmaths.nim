# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest
import std/[sugar]
import wasmedge
test "VmExecute Math Test":
  var confCtx = ConfigureContext.create()
  confCtx.add hostRegistrationWasi
  var vmCtx = confCtx.createVm()

  vmCtx.loadWasmFromFile("maths.wasm")
  vmCtx.validate()
  vmCtx.instantiate()

  var
    params = [wasmValue(10i32), wasmValue(30i32)]
    results = [WasmValue()]

  vmCtx.execute("add", params, results)
  check results[0].getValue[: int32] == 40
  vmCtx.execute("multiply", params, results)
  check results[0].getValue[: int32] == 300

  let allFuncs = collect(for name in vmCtx.functionNames: $name)
  for x in ["add", "multiply"]:
    check x in allFuncs

test "Executor Math Test":
  var config = ConfigureContext.create()
  config.add hostRegistrationWasi

  var
    stats = StatisticsContext.create()
    loader = config.createLoader()
    validator = config.createValidator()
    executor = config.createExecutor(stats)
    ast: AstModuleContext
    module: ModuleContext
  loader.parseFromFile(ast, "maths.wasm")
  validator.validate(ast)

  var store = StoreContext.create()
  executor.instantiate(module, store, ast)

  let allFuncs = collect(for name in module.functionNames: $name)
  for x in ["add", "multiply"]:
    check x in allFuncs

  let
    addFunc = module.findFunction(wasmString"add")
    mulFunc = module.findFunction(wasmString"multiply")

  var params = [wasmValue(10i32), wasmValue(30i32)]
  var results = [WasmValue()]
  executor.invoke(addFunc, params, results)
  check results[0].getValue[: int32] == 40
  executor.invoke(mulFunc, params, results)
  check results[0].getValue[: int32] == 300


