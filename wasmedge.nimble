# Package

version       = "0.1.0"
author        = "Jason"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.6.0"
requires "futhark"

import std/[strutils, os]

task buildWasmSources, "Builds all wasmsources and moves them to 'tests'":
  for file in "wasmsources".listFiles:
    if file.endsWith".nim":
      selfExec("c " & file)
