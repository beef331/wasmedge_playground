import std/unittest
import wasmedge


test "String ops":
  let
    someBuffer = "Hello"
    someName = wasmString"Hello"
    someOtherString = unmanagedWasmString(someBuffer)
  check someBuffer == someName
  check someBuffer == someOtherString
  check someName == someBuffer

  check $someName == someBuffer
  check $someOtherString == someBuffer

test "Value":
  check wasmValue(1f).getValue[: float32]() == 1f
  check wasmValue(1d).getValue[: float64]() == 1d
  check wasmValue(1i32).getValue[: int32]() == 1i32
  check wasmValue(1i64).getValue[: int64]() == 1i64
