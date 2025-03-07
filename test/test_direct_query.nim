import os, httpclient, json, strformat, strutils, tables
import dotenv

proc testDirectQuery() =
  # Load environment with debugging and overriding enabled
  echo "Loading environment variables..."
  let envVars = loadEnv(override = true, debug = true)
  
  # Verify required environment variables
  let dbUrl = getEnv("TURSO_NIM_DB_URL", "")
  let authToken = getEnv("TURSO_NIM_AUTH_TOKEN", "")
  
  if dbUrl == "":
    echo "Error: TURSO_DB_URL environment variable is not set"
    return
  
  if authToken == "":
    echo "Error: TURSO_AUTH_TOKEN environment variable is not set"
    return
  
  # Debug token
  echo "\nEnvironment variable details:"
  echo fmt"TURSO_DB_URL = {dbUrl}"
  echo fmt"TURSO_AUTH_TOKEN length: {authToken.len}"
  echo fmt"TURSO_AUTH_TOKEN first 10 chars: '{authToken[0..9]}'"
  echo fmt"TURSO_AUTH_TOKEN last 10 chars: '{authToken[^10..^1]}'"
  
  # Check which source was used
  if "TURSO_DB_URL" in envVars:
    echo "\nUsing TURSO_DB_URL from .env file"
  else:
    echo "\nUsing TURSO_DB_URL from system environment"
  
  if "TURSO_AUTH_TOKEN" in envVars:
    echo "Using TURSO_AUTH_TOKEN from .env file"
  else:
    echo "Using TURSO_AUTH_TOKEN from system environment"
  
  # Set up client 
  let client = newHttpClient()
  let endpoint = dbUrl & "/v2/pipeline"
  
  # Create headers
  let requestHeaders = newHttpHeaders({
    "Content-Type": "application/json",
    "Authorization": "Bearer " & authToken.strip()
  }, titleCase = true)
  
  echo "\nHeaders being sent:"
  let authHeader = requestHeaders["Authorization"]
  echo fmt"Authorization: {authHeader}"
  let contentType = requestHeaders["Content-Type"]
  echo fmt"Content-Type: {contentType}"
  
  # Create request body
  let requestBody = %*{
    "requests": [
      { 
        "type": "execute", 
        "stmt": { 
          "sql": "SELECT 1"
        }
      },
      { "type": "close" }
    ]
  }
  
  echo "\nRequest payload:"
  echo pretty(requestBody)
  
  # Execute request
  try:
    echo "\nSending request to: ", endpoint
    
    let response = client.request(
      url = endpoint, 
      httpMethod = HttpPost, 
      body = $requestBody,
      headers = requestHeaders
    )
    
    echo fmt"Response status: {response.code}"
    
    if response.code.int == 200:
      let jsonResponse = parseJson(response.body)
      echo "Response payload:"
      echo pretty(jsonResponse)
    else:
      echo fmt"Error response: {response.body}"
  
  except:
    let errorMsg = getCurrentExceptionMsg()
    echo fmt"Error making request: {errorMsg}"
  
  finally:
    client.close()

echo "Direct Turso API Query Test"
echo "=========================="

# Run the test
testDirectQuery()
echo "Test completed"