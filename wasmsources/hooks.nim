include wasmedge/exporter

proc doThing(a, b: int32): int32 {.importC.}

proc indirectCall(a, b: int32) {.wasmexport.} = discard doThing(a, b)
