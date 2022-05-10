include wasmedge/exporter

proc doThing(a, b: int32): int32 {.importC.}

proc indirectCall(a, b: int32) {.wasmexport.} =
  assert doThing(a, b) == a * b


type MyType = object
  x, y, z: int
  w: string

proc getMyType(a, b: int32) {.wasmexport.} = discard
