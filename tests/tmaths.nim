# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest

import wasmedge
test "Maths Test":
  let confCtx = configureCreate()
  confCtx.configureAddHostRegistration(hostRegistrationWasi)
  let
    vmCtx = confCtx.vmCreate(nil)
    addName = wasmString("add")
    multiName = wasmString("multiply")

  try:
    vmCtx.loadWasmFromFile("maths.wasm")
    vmCtx.validate()
    vmCtx.instantiate()

    var
      params = [wasmValue(10i32), wasmValue(30i32)]
      results = [WasmValue()]
    vmCtx.execute(addName, params, results)
    assert results[0].getValue[: int32] == 40
    vmCtx.execute(multiName, params, results)
    assert results[0].getValue[: int32] == 300


  finally:
    vmDelete(vmCtx)
    configureDelete(confCtx)
    stringDelete(addName)
    stringDelete(multiName)
