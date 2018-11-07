# Package

version       = "0.1.0"
author        = "coolreader18"
description   = "An idiomatic library for duktape"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 0.19.0"

requires "nimgen >= 0.1.4"

import distros

var cmd = ""
if detectOs(Windows):
  cmd = "cmd /c "

task setup, "Download and generate":
  exec cmd & "nimgen duktape.cfg"

before install:
  setupTask()
