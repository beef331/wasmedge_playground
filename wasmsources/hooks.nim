include wasmedge/exporter
proc doThing(a, b: int32){.importC.}

proc indirectCall(a, b: int32) = doThing(a, b)
