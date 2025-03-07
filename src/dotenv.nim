import os, streams, strutils, tables

proc loadEnv*(path: string = ".env", override = false, debug = false): TableRef[string, string] =
  ## Loads environment variables from a .env file
  ## 
  ## Parameters:
  ##   path: Path to the .env file (default: ".env")
  ##   override: Whether to override existing environment variables (default: false)
  ##   debug: Whether to print debug information (default: false)
  ##
  ## Returns:
  ##   A table of loaded environment variables
  
  result = newTable[string, string]()
  
  if debug:
    echo "Loading environment variables from: ", path
  
  if not fileExists(path):
    if debug:
      echo "File not found: ", path
    return
  
  let fileStream = newFileStream(path, fmRead)
  if fileStream == nil:
    if debug:
      echo "Could not open file: ", path
    return
  
  defer: fileStream.close()
  
  var line = ""
  var lineNum = 0
  while fileStream.readLine(line):
    lineNum.inc
    line = line.strip()
    
    # Skip empty lines and comments
    if line.len == 0 or line[0] == '#':
      continue
    
    # Parse KEY=VALUE format
    let parts = line.split('=', 1)
    if parts.len == 2:
      let key = parts[0].strip()
      var value = parts[1].strip()
      
      # Handle quoted values
      if value.len >= 2 and ((value[0] == '"' and value[^1] == '"') or 
                              (value[0] == '\'' and value[^1] == '\'')):
        value = value[1..^2]
      
      # Check if variable should be set
      let existingValue = getEnv(key)
      let shouldSet = override or existingValue == ""
      
      # Store in result table
      result[key] = value
      
      if shouldSet:
        putEnv(key, value)
        if debug:
          echo "Set environment variable: ", key, "=", value
      elif debug:
        echo "Skipped existing environment variable: ", key, 
             " (current=", existingValue, ", .env=", value, ")"
    else:
      if debug:
        echo "Invalid format at line ", lineNum, ": ", line