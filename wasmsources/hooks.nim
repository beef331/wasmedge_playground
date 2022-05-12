include wasmedge/exporter

proc doThing(a, b: int32): int32 {.importC.}

proc indirectCall(a, b: int32) {.wasmexport.} =
  assert doThing(a, b) == a * b

proc getFloat(a, b: int32): float32 {.wasmexport.} = discard

type MyType = object
  x, y, z: int32
  w: float32

var memory {.exportC.}: ptr UncheckedArray[MyType]

proc getMyType() {.wasmexport.} =
  memory[0] = MyType(x: 100, y: 300, z: 300, w: 15)
