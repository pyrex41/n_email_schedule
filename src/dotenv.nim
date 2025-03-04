import os, strutils

proc loadEnv*(filename = ".env") =
  ## Loads environment variables from a .env file
  if not fileExists(filename):
    return
    
  let content = readFile(filename)
  for line in content.splitLines():
    # Skip comments and empty lines
    let trimmedLine = line.strip()
    if trimmedLine.len == 0 or trimmedLine.startsWith("#"):
      continue
      
    # Parse KEY=VALUE format
    let parts = trimmedLine.split('=', 1)
    if parts.len != 2:
      continue
      
    let 
      key = parts[0].strip()
      value = parts[1].strip()
    
    # Skip if already set in environment (don't override)
    if getEnv(key) == "":
      putEnv(key, value)

proc getEnvOrEmpty*(key: string): string =
  ## Get environment variable or empty string if not found
  result = getEnv(key) 