include wasmedge/exporter

{.passL:"-sERROR_ON_UNDEFINED_SYMBOLS=0".}

proc doThing(a, b: int32): int32 {.importC.}

proc indirectCall(a, b: int32) {.wasmexport.} = discard doThing(a, b)
