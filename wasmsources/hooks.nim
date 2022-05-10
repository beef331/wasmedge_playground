include wasmedge/exporter

proc doThing(a, b: int32): int32 {.importC.}

proc indirectCall(a, b: int32) {.wasmexport.} =
  assert doThing(a, b) == a * b

proc getFloat(a, b: int32): float32 {.wasmexport.} = discard
