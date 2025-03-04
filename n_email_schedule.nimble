# Package

version       = "0.1.0"
author        = "pyrex41"
description   = "Medicare Email Scheduler"
license       = "MIT"
srcDir        = "src"
bin           = @["n_email_schedule"]


# Dependencies

requires "nim >= 2.2.2"
requires "asyncdispatch"
requires "httpclient"
requires "times"
requires "json"
requires "strutils"
requires "tables"
requires "sequtils"
requires "unittest"
requires "jester"
