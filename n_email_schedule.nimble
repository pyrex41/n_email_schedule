# Package

version       = "0.1.0"
author        = "Medicare API Team"
description   = "RESTful API for scheduling Medicare enrollment emails"
license       = "Proprietary"
srcDir        = "src"
bin           = @["api"]

# Dependencies

requires "nim >= 2.0.0"
requires "mummy >= 0.4.5"

# Tasks

task run, "Run the API server":
  exec "nim c -r src/api.nim"
