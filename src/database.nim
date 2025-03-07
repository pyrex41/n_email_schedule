import httpclient, json, asyncdispatch, os, times, strutils, logging, strformat, random, math, options, tables
import models, dotenv, config

# Initialize logging
var dbLogger = getLogger("database")

const 
  MAX_RETRIES = 3
  RETRY_DELAY_MS = 500  # Base delay in ms before exponential backoff

type
  DbConfig* = object
    baseUrl*: string
    authToken*: string
    maxRetries*: int

  DbError* = object of IOError
    statusCode*: int

proc newDbConfig*(url: string, token: string, maxRetries: int = MAX_RETRIES): DbConfig =
  if url.len == 0:
    raise newException(ValueError, "Database URL cannot be empty")
  if token.len == 0:
    raise newException(ValueError, "Authentication token cannot be empty")
  
  result = DbConfig(
    baseUrl: url.strip(trailing = true),
    authToken: token,
    maxRetries: maxRetries
  )

proc getConfigFromEnv*(): DbConfig =
  # Try to load from .env file with override and debugging options
  info "Loading environment variables from .env file"
  let envVars = loadEnv(override = true, debug = true)
  
  info "Loading database configuration from environment"
  
  # Check if we have values from .env file or system env
  if "TURSO_NIM_DB_URL" in envVars:
    info "Found TURSO_NIM_DB_URL in .env file"
  else:
    info "TURSO_NIM_DB_URL not in .env file, checking system environment"
  
  if "TURSO_NIM_AUTH_TOKEN" in envVars:
    info "Found TURSO_NIM_AUTH_TOKEN in .env file"
  else:
    info "TURSO_NIM_AUTH_TOKEN not in .env file, checking system environment"
  
  # Get the values from environment (which may have been set by loadEnv)
  let dbUrl = getEnv("TURSO_NIM_DB_URL", "")
  let authToken = getEnv("TURSO_NIM_AUTH_TOKEN", "")
  
  # Verify required environment variables
  if dbUrl.len == 0:
    error "TURSO_NIM_DB_URL not set in environment variables"
    raise newException(ValueError, "Database URL is required. Set TURSO_NIM_DB_URL environment variable.")
  
  if authToken.len == 0:
    error "TURSO_NIM_AUTH_TOKEN not set in environment variables"
    raise newException(ValueError, "Authentication token is required. Set TURSO_NIM_AUTH_TOKEN environment variable.")
  
  # Log a masked version of the token for debugging
  let maskedToken = if authToken.len > 15: authToken[0..7] & "..." & authToken[^8..^1] else: "token too short"
  info fmt"Using auth token starting with: {maskedToken}"
  
  result = newDbConfig(dbUrl, authToken)
  info fmt"Database configuration loaded, URL: {result.baseUrl}"
  return result

proc parseIsoDate*(dateStr: string): DateTime =
  # Parse ISO date format like "2023-04-15T00:00:00Z"
  try:
    result = parse(dateStr, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
  except:
    # Fallback for simpler date format
    try:
      result = parse(dateStr, "yyyy-MM-dd", utc())
    except:
      # Default to current date if parsing fails
      error fmt"Failed to parse date: {dateStr}, defaulting to current date"
      result = now()

proc calculateRetryDelay(attempt: int): int =
  # Exponential backoff with jitter
  let baseDelay = RETRY_DELAY_MS * pow(2, attempt.float).int
  let jitter = rand(baseDelay div 4)  # Add up to 25% jitter
  return baseDelay + jitter

proc execQuery*(config: DbConfig, sql: string, args: JsonNode = newJArray()): Future[JsonNode] {.async.} =
  let client = newAsyncHttpClient()
  let endpoint = config.baseUrl & "/v2/pipeline"
  
  # Log detailed request information
  let maskedToken = if config.authToken.len > 15: config.authToken[0..7] & "..." & config.authToken[^8..^1] else: "token too short"
  echo fmt"==== DATABASE REQUEST ===="
  echo fmt"Endpoint: {endpoint}"
  echo fmt"Auth token: {maskedToken}"
  echo fmt"SQL: {sql}"
  echo fmt"Args: {args}"
  
  client.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Authorization": "Bearer " & config.authToken
  })
  
  let reqBody = %*{
    "requests": [
      {
        "type": "execute",
        "stmt": {
          "sql": sql,
          "args": args
        }
      },
      {"type": "close"}
    ]
  }
  
  echo fmt"Request body: {reqBody}"
  
  var attempts = 0
  var lastError = ""
  
  try:
    while attempts < config.maxRetries:
      try:
        echo fmt"Attempt #{attempts+1}/{config.maxRetries} to execute query"
        let response = await client.request(endpoint, httpMethod = HttpPost, body = $reqBody)
        let body = await response.body
        
        # Log detailed response information
        echo fmt"==== DATABASE RESPONSE ===="
        echo fmt"Status code: {response.code}"
        echo fmt"Headers: {response.headers}"
        echo fmt"Body length: {body.len}"
        echo fmt"Body (first 200 chars): {body[0..min(199, body.len-1)]}"
        
        if response.code.int >= 400:
          let errorMsg = fmt"HTTP error {response.code}: {body}"
          echo fmt"ERROR: {errorMsg}"
          lastError = errorMsg
          
          # Some errors shouldn't be retried (e.g., authorization issues)
          if response.code.int == 401 or response.code.int == 403:
            var dbError = newException(DbError, lastError)
            dbError.statusCode = response.code.int
            raise dbError
          
          # For other errors, we'll retry
          inc attempts
          if attempts < config.maxRetries:
            let delay = calculateRetryDelay(attempts)
            echo fmt"Will retry in {delay}ms (attempt {attempts+1}/{config.maxRetries})"
            await sleepAsync(delay)
            continue
          else:
            break
        
        # Safely parse the JSON body with error handling
        try:
          result = parseJson(body)
          echo "Query executed successfully, parsing JSON"
          return result
        except JsonParsingError as e:
          let errorMsg = fmt"Invalid JSON response: {e.msg}"
          echo fmt"ERROR: {errorMsg}"
          lastError = errorMsg
          # Return an empty JSON object instead of nil to prevent segfaults
          return %*{"error": errorMsg, "rawBody": body}
        
      except DbError as e:
        # Let DbError propagate up immediately
        echo fmt"Database error: {e.msg}"
        raise e
      except HttpRequestError as e:
        let errorMsg = fmt"HTTP request failed: {e.msg}"
        echo fmt"ERROR: {errorMsg}"
        lastError = errorMsg
        
        inc attempts
        if attempts < config.maxRetries:
          let delay = calculateRetryDelay(attempts)
          echo fmt"Will retry in {delay}ms (attempt {attempts+1}/{config.maxRetries})"
          await sleepAsync(delay)
        else:
          break
      except Exception as e:
        let errorMsg = fmt"Error executing query: {e.msg}"
        echo fmt"EXCEPTION: {errorMsg}"
        lastError = errorMsg
        
        inc attempts
        if attempts < config.maxRetries:
          let delay = calculateRetryDelay(attempts)
          echo fmt"Will retry in {delay}ms (attempt {attempts+1}/{config.maxRetries})"
          await sleepAsync(delay)
        else:
          break
      
    # If we reached here, all retries failed
    echo fmt"All {config.maxRetries} retry attempts failed. Last error: {lastError}"
    # Return an error object instead of an empty one
    return %*{"error": lastError}
  finally:
    client.close()

proc countContacts*(config: DbConfig): Future[int] {.async.} =
  let query = "SELECT COUNT(*) FROM contacts"
  
  let response = await execQuery(config, query)
  
  try:
    if "results" in response and response["results"].len > 0:
      let result = response["results"][0]
      if "response" in result and "result" in result["response"]:
        let sqlResult = result["response"]["result"]
        if "rows" in sqlResult and sqlResult["rows"].len > 0:
          return parseInt(sqlResult["rows"][0][0]["value"].getStr)
  except:
    let errorMsg = getCurrentExceptionMsg()
    error fmt"Error counting contacts: {errorMsg}"
  
  return 0

proc getContacts*(config: DbConfig, offset: int = 0, limit: int = 100): Future[seq[Contact]] {.async.} =
  let query = """
    SELECT 
      id, first_name, last_name, email, 
      current_carrier, plan_type, effective_date, birth_date,
      tobacco_user, gender, state, zip_code, agent_id, 
      phone_number, status 
    FROM contacts
    LIMIT ? OFFSET ?
  """
  
  let args = %*[
    {"type": "integer", "value": $limit},
    {"type": "integer", "value": $offset}
  ]
  
  info fmt"Fetching contacts from database (limit: {limit}, offset: {offset})"
  
  let response = await execQuery(config, query, args)
  var contacts: seq[Contact] = @[]
  
  try:
    if "results" in response and response["results"].len > 0:
      let result = response["results"][0]
      if "response" in result and "result" in result["response"]:
        let sqlResult = result["response"]["result"]
        if "rows" in sqlResult and sqlResult["rows"].len > 0:
          for row in sqlResult["rows"]:
            info fmt"Contact row data: {row}"
            try:
              let contact = Contact(
                id: parseInt(row[0]["value"].getStr),
                firstName: row[1]["value"].getStr,
                lastName: row[2]["value"].getStr,
                email: row[3]["value"].getStr,
                currentCarrier: row[4]["value"].getStr,
                planType: row[5]["value"].getStr,
                effectiveDate: parseIsoDate(row[6]["value"].getStr),
                birthDate: parseIsoDate(row[7]["value"].getStr),
                tobaccoUser: row[8]["value"].getStr == "1",
                gender: row[9]["value"].getStr,
                state: row[10]["value"].getStr,
                zipCode: row[11]["value"].getStr,
                agentID: if row[12]["type"].getStr == "null": 0 else: parseInt(row[12]["value"].getStr),
                phoneNumber: row[13]["value"].getStr,
                status: row[14]["value"].getStr
              )
              contacts.add(contact)
            except:
              let errorMsg = getCurrentExceptionMsg()
              error fmt"Error parsing contact data: {errorMsg}, row: {row}"
  except:
    let errorMsg = getCurrentExceptionMsg()
    error fmt"Error processing contacts query: {errorMsg}"
  
  info fmt"Retrieved {contacts.len} contacts from database"
  return contacts

proc getContactById*(config: DbConfig, contactId: int): Future[Option[Contact]] {.async.} =
  let query = """
    SELECT 
      id, first_name, last_name, email, 
      current_carrier, plan_type, effective_date, birth_date,
      tobacco_user, gender, state, zip_code, agent_id, 
      phone_number, status 
    FROM contacts
    WHERE id = ?
  """
  
  let args = %*[
    {"type": "integer", "value": $contactId}
  ]
  
  info fmt"Fetching contact with ID {contactId}"
  
  let response = await execQuery(config, query, args)
  
  try:
    if "results" in response and response["results"].len > 0:
      let result = response["results"][0]
      if "response" in result and "result" in result["response"]:
        let sqlResult = result["response"]["result"]
        if "rows" in sqlResult and sqlResult["rows"].len > 0:
          let row = sqlResult["rows"][0]
          info fmt"Contact row data: {row}"
          try:
            let contact = Contact(
              id: parseInt(row[0]["value"].getStr),
              firstName: row[1]["value"].getStr,
              lastName: row[2]["value"].getStr,
              email: row[3]["value"].getStr,
              currentCarrier: row[4]["value"].getStr,
              planType: row[5]["value"].getStr,
              effectiveDate: parseIsoDate(row[6]["value"].getStr),
              birthDate: parseIsoDate(row[7]["value"].getStr),
              tobaccoUser: row[8]["value"].getStr == "1",
              gender: row[9]["value"].getStr,
              state: row[10]["value"].getStr,
              zipCode: row[11]["value"].getStr,
              agentID: if row[12]["type"].getStr == "null": 0 else: parseInt(row[12]["value"].getStr),
              phoneNumber: row[13]["value"].getStr,
              status: row[14]["value"].getStr
            )
            return some(contact)
          except:
            let errorMsg = getCurrentExceptionMsg()
            error fmt"Error parsing contact data: {errorMsg}, row: {row}"
  except:
    let errorMsg = getCurrentExceptionMsg()
    error fmt"Error processing contact query: {errorMsg}"
  
  info fmt"No contact found with ID {contactId}"
  return none(Contact)

proc saveEmail*(config: DbConfig, email: Email, contactId: int): Future[bool] {.async.} =
  let query = """
    INSERT INTO contact_events
    (contact_id, event_type, metadata, created_at)
    VALUES (?, ?, ?, ?)
  """
  
  let metadata = %*{
    "type": $email.emailType,
    "reason": email.reason
  }
  
  let args = %*[
    {"type": "integer", "value": $contactId},
    {"type": "text", "value": "email_scheduled"},
    {"type": "text", "value": $metadata},
    {"type": "text", "value": email.scheduledAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'")}
  ]
  
  let formattedDate = email.scheduledAt.format("yyyy-MM-dd")
  info fmt"Saving email for contact #{contactId}, type: {$email.emailType}, scheduled at: {formattedDate}"
  
  try:
    let response = await execQuery(config, query, args)
    let success = "results" in response
    
    if success:
      info fmt"Successfully saved email for contact #{contactId}"
    else:
      error fmt"Failed to save email for contact #{contactId}"
    
    return success
  except:
    let errorMsg = getCurrentExceptionMsg()
    error fmt"Error saving email: {errorMsg}"
    return false

proc saveEmailsBatch*(config: DbConfig, emails: seq[tuple[email: Email, contactId: int]]): Future[int] {.async.} =
  if emails.len == 0:
    return 0
    
  # Begin transaction
  discard await execQuery(config, "BEGIN TRANSACTION")
  
  let query = """
    INSERT INTO contact_events
    (contact_id, event_type, metadata, created_at)
    VALUES (?, ?, ?, ?)
  """
  
  var successCount = 0
  var errorOccurred = false
  
  try:
    for idx, (email, contactId) in emails:
      let metadata = %*{
        "type": $email.emailType,
        "reason": email.reason
      }
      
      let args = %*[
        {"type": "integer", "value": $contactId},
        {"type": "text", "value": "email_scheduled"},
        {"type": "text", "value": $metadata},
        {"type": "text", "value": email.scheduledAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'")}
      ]
      
      let formattedDate = email.scheduledAt.format("yyyy-MM-dd")
      debug fmt"Batch saving email {idx+1}/{emails.len} for contact #{contactId}, type: {$email.emailType}, scheduled at: {formattedDate}"
      
      try:
        let response = await execQuery(config, query, args)
        if "results" in response:
          inc successCount
        else:
          error fmt"Failed to save email for contact #{contactId} in batch"
      except:
        let errorMsg = getCurrentExceptionMsg()
        error fmt"Error saving email in batch: {errorMsg}"
        errorOccurred = true
        break
    
    # If everything was successful, commit the transaction
    if not errorOccurred:
      discard await execQuery(config, "COMMIT")
      info fmt"Successfully saved {successCount}/{emails.len} emails in batch"
    else:
      discard await execQuery(config, "ROLLBACK")
      error fmt"Rolling back transaction due to errors, saved {successCount}/{emails.len} emails"
      successCount = 0  # Reset to 0 since we rolled back
      
  except:
    let errorMsg = getCurrentExceptionMsg()
    error fmt"Error in batch email save: {errorMsg}"
    # Attempt to rollback transaction on error
    try:
      discard await execQuery(config, "ROLLBACK")
    except:
      error "Failed to rollback transaction"
    successCount = 0
    
  return successCount

proc getOrgDbConfig*(mainConfig: DbConfig, orgId: int): Future[Result[DbConfig]] {.async.} =
  let query = """
    SELECT turso_db_url, turso_auth_token 
    FROM organizations 
    WHERE id = ?
  """
  
  let args = %*[
    {"type": "integer", "value": $orgId}
  ]
  
  try:
    info fmt"Retrieving database configuration for organization #{orgId}"
    let response = await execQuery(mainConfig, query, args)
    
    # Return error if response is nil or an empty object
    if response.isNil or (response.kind == JObject and response.len == 0):
      info fmt"Nil or empty response when retrieving database config for organization #{orgId}"
      return Result[DbConfig](isOk: false, error: fmt"Failed to retrieve database configuration for organization #{orgId}")
    
    # Log the full response for debugging
    info fmt"Raw API response: {response}"
    
    # Use hasKey and type checks for safer navigation
    if response.kind == JObject and response.hasKey("results") and 
       response["results"].kind == JArray and response["results"].len > 0:
      
      let result = response["results"][0]
      info fmt"Result object: {result}"
      
      if result.kind == JObject and result.hasKey("response") and 
         result["response"].kind == JObject and result["response"].hasKey("result"):
        
        let sqlResult = result["response"]["result"]
        info fmt"SQL result: {sqlResult}"
        
        if sqlResult.kind == JObject and sqlResult.hasKey("rows") and 
           sqlResult["rows"].kind == JArray and sqlResult["rows"].len > 0:
          
          let rowsArray = sqlResult["rows"]
          if rowsArray.len == 0 or rowsArray[0].kind != JArray or rowsArray[0].len < 2:
            return Result[DbConfig](isOk: false, error: fmt"Organization #{orgId} not found or has invalid data structure")
          
          let row = rowsArray[0]
          info fmt"Row data: {row}"
          
          # Safe extraction with type checks
          if row[0].kind != JObject or not row[0].hasKey("value") or
             row[1].kind != JObject or not row[1].hasKey("value"):
            return Result[DbConfig](isOk: false, error: fmt"Invalid database configuration format for organization #{orgId}")
          
          # Extract the URL and token from the complex objects
          let url = row[0]["value"].getStr("")
          let token = row[1]["value"].getStr("")
          
          info fmt"Extracted URL: '{url}', token length: {token.len}"
          
          if url.len == 0:
            return Result[DbConfig](isOk: false, error: fmt"Organization #{orgId} has empty database URL")
          
          if token.len == 0:
            return Result[DbConfig](isOk: false, error: fmt"Organization #{orgId} has empty auth token")
          
          info fmt"Retrieved database config for organization #{orgId}"
          return Result[DbConfig](isOk: true, value: newDbConfig(url, token))
    
    return Result[DbConfig](isOk: false, error: fmt"Organization #{orgId} not found")
  except Exception as e:
    let errorMsg = e.msg
    error fmt"Error retrieving org database config: {errorMsg}"
    return Result[DbConfig](isOk: false, error: errorMsg)

proc processContactsInChunks*(config: DbConfig, chunkSize: int = 100, 
    processor: proc (contacts: seq[Contact]): Future[bool] {.async.}): Future[bool] {.async.} =
  var offset = 0
  var allSuccess = true
  var hasMore = true
  
  while hasMore:
    let contacts = await getContacts(config, offset, chunkSize)
    
    if contacts.len == 0:
      hasMore = false
    else:
      let success = await processor(contacts)
      if not success:
        allSuccess = false
        warn fmt"Processor failed on chunk with offset {offset}, continuing with next chunk"
        
      offset += contacts.len
      
      if contacts.len < chunkSize:
        hasMore = false
  
  return allSuccess

proc updateContactLastEmailedDate*(config: DbConfig, contactId: int, date: DateTime): Future[bool] {.async.} =
  let query = """
    UPDATE contacts
    SET last_emailed_date = ?
    WHERE id = ?
  """
  
  let formattedDate = date.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  let args = %*[
    {"type": "text", "value": formattedDate},
    {"type": "integer", "value": $contactId}
  ]
  
  info fmt"Updating last_emailed_date for contact #{contactId} to {formattedDate}"
  
  try:
    let response = await execQuery(config, query, args)
    let success = "results" in response
    
    if success:
      info fmt"Successfully updated last_emailed_date for contact #{contactId}"
    else:
      error fmt"Failed to update last_emailed_date for contact #{contactId}"
    
    return success
  except:
    let errorMsg = getCurrentExceptionMsg()
    error fmt"Error updating last_emailed_date: {errorMsg}"
    return false

proc updateContactsLastEmailedDateBatch*(config: DbConfig, updates: seq[tuple[contactId: int, date: DateTime]]): Future[int] {.async.} =
  if updates.len == 0:
    return 0
    
  # Begin transaction
  discard await execQuery(config, "BEGIN TRANSACTION")
  
  let query = """
    UPDATE contacts
    SET last_emailed_date = ?
    WHERE id = ?
  """
  
  var successCount = 0
  var errorOccurred = false
  
  try:
    for idx, (contactId, date) in updates:
      let formattedDate = date.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
      let args = %*[
        {"type": "text", "value": formattedDate},
        {"type": "integer", "value": $contactId}
      ]
      
      debug fmt"Batch updating last_emailed_date {idx+1}/{updates.len} for contact #{contactId} to {formattedDate}"
      
      try:
        let response = await execQuery(config, query, args)
        if "results" in response:
          inc successCount
        else:
          error fmt"Failed to update last_emailed_date for contact #{contactId} in batch"
      except:
        let errorMsg = getCurrentExceptionMsg()
        error fmt"Error updating last_emailed_date in batch: {errorMsg}"
        errorOccurred = true
        break
    
    # If everything was successful, commit the transaction
    if not errorOccurred:
      discard await execQuery(config, "COMMIT")
      info fmt"Successfully updated {successCount}/{updates.len} last_emailed_dates in batch"
    else:
      discard await execQuery(config, "ROLLBACK")
      error fmt"Rolling back transaction due to errors, updated {successCount}/{updates.len} contacts"
      successCount = 0  # Reset to 0 since we rolled back
      
  except:
    let errorMsg = getCurrentExceptionMsg()
    error fmt"Error in batch last_emailed_date update: {errorMsg}"
    # Attempt to rollback transaction on error
    try:
      discard await execQuery(config, "ROLLBACK")
    except:
      error "Failed to rollback transaction"
    successCount = 0
    
  return successCount

proc testBasicConnection*(config: DbConfig): Future[bool] {.async.} =
  ## Tests a simple connection to the Turso database
  let client = newAsyncHttpClient()
  
  # Try accessing /health endpoint which doesn't require complex queries
  let endpoint = config.baseUrl & "/health"
  
  # Log masked token
  let maskedToken = if config.authToken.len > 15: config.authToken[0..7] & "..." & config.authToken[^8..^1] else: "token too short"
  info fmt"Testing basic connection to {endpoint} with token: {maskedToken}"
  
  client.headers = newHttpHeaders({
    "Authorization": "Bearer " & config.authToken
  })
  
  try:
    info "Sending test request to database health endpoint"
    let response = await client.request(endpoint, httpMethod = HttpGet)
    let body = await response.body
    
    info fmt"Health check response: {response.code}, body: {body}"
    return response.code.int == 200
  except:
    let errorMsg = getCurrentExceptionMsg()
    error fmt"Error testing connection: {errorMsg}"
    return false
  finally:
    client.close()

proc listOrganizations*(config: DbConfig): Future[JsonNode] {.async.} =
  ## Lists all organizations in the database
  let query = """
    SELECT id, name, turso_db_url
    FROM organizations
  """
  
  info "Retrieving list of all organizations"
  
  try:
    let response = await execQuery(config, query)
    
    # Return the raw response for debugging
    info fmt"Raw organizations response: {response}"
    
    # Also try parsing it to a more structured format
    var orgs: seq[JsonNode] = @[]
    
    if response.kind == JObject and response.hasKey("results") and 
       response["results"].kind == JArray and response["results"].len > 0:
      
      let result = response["results"][0]
      if result.kind == JObject and result.hasKey("response") and 
         result["response"].kind == JObject and result["response"].hasKey("result"):
        
        let sqlResult = result["response"]["result"]
        if sqlResult.kind == JObject and sqlResult.hasKey("rows") and 
           sqlResult["rows"].kind == JArray:
          
          for row in sqlResult["rows"]:
            if row.kind == JArray and row.len >= 3:
              let org = %* {
                "id": row[0]["value"].getStr(""),
                "name": row[1]["value"].getStr(""),
                "dbUrl": row[2]["value"].getStr("")
              }
              orgs.add(org)
    
    return %* {
      "rawResponse": response,
      "parsedOrgs": orgs
    }
  except Exception as e:
    let errorMsg = e.msg
    error fmt"Error listing organizations: {errorMsg}"
    return %* {
      "error": errorMsg
    }

proc checkTableExists*(config: DbConfig, tableName: string): Future[bool] {.async.} =
  ## Checks if a table exists in the database
  let query = """
    SELECT name FROM sqlite_master 
    WHERE type='table' AND name=?
  """
  
  let args = %*[
    {"type": "text", "value": tableName}
  ]
  
  info fmt"Checking if table '{tableName}' exists"
  
  try:
    let response = await execQuery(config, query, args)
    
    if response.kind == JObject and response.hasKey("results") and 
       response["results"].kind == JArray and response["results"].len > 0:
      
      let result = response["results"][0]
      if result.kind == JObject and result.hasKey("response") and 
         result["response"].kind == JObject and result["response"].hasKey("result"):
        
        let sqlResult = result["response"]["result"]
        if sqlResult.kind == JObject and sqlResult.hasKey("rows") and 
           sqlResult["rows"].kind == JArray:
          
          return sqlResult["rows"].len > 0
    
    return false
  except Exception as e:
    let errorMsg = e.msg
    error fmt"Error checking if table exists: {errorMsg}"
    return false

proc createOrganizationsTable*(config: DbConfig): Future[bool] {.async.} =
  ## Creates the organizations table if it doesn't exist
  let createTableQuery = """
    CREATE TABLE IF NOT EXISTS organizations (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      turso_db_url TEXT NOT NULL,
      turso_auth_token TEXT NOT NULL
    )
  """
  
  info "Creating organizations table"
  
  try:
    let createResponse = await execQuery(config, createTableQuery)
    if "results" in createResponse:
      # Check if there are any organizations
      let countQuery = "SELECT COUNT(*) FROM organizations"
      let countResponse = await execQuery(config, countQuery)
      
      var hasOrgs = false
      if countResponse.kind == JObject and countResponse.hasKey("results") and 
         countResponse["results"].kind == JArray and countResponse["results"].len > 0:
        
        let result = countResponse["results"][0]
        if result.kind == JObject and result.hasKey("response") and 
           result["response"].kind == JObject and result["response"].hasKey("result"):
          
          let sqlResult = result["response"]["result"]
          if sqlResult.kind == JObject and sqlResult.hasKey("rows") and 
             sqlResult["rows"].kind == JArray and sqlResult["rows"].len > 0:
            
            let row = sqlResult["rows"][0]
            if row.kind == JArray and row.len > 0:
              let count = parseInt(row[0]["value"].getStr("0"))
              hasOrgs = count > 0
      
      # If no organizations, insert a default one
      if not hasOrgs:
        info "No organizations found, creating a default organization"
        let insertQuery = """
          INSERT INTO organizations (id, name, turso_db_url, turso_auth_token) 
          VALUES (1, 'Default Organization', ?, ?)
        """
        
        let args = %*[
          {"type": "text", "value": config.baseUrl},
          {"type": "text", "value": config.authToken}
        ]
        
        let insertResponse = await execQuery(config, insertQuery, args)
        if "results" in insertResponse:
          info "Successfully created default organization"
          return true
        else:
          error "Failed to create default organization"
          return false
      
      return true
    else:
      error "Failed to create organizations table"
      return false
  except Exception as e:
    let errorMsg = e.msg
    error fmt"Error creating organizations table: {errorMsg}"
    return false

proc dbURLWithBranch*(baseUrl: string, branch: string): string =
  ## Converts a base Turso URL to a branch-specific URL
  if baseUrl.contains("?"):
    result = baseUrl & "&branch=" & branch
  else:
    result = baseUrl & "?branch=" & branch
  info fmt"Generated branch URL: {result}"

proc getOrgSpecificConfig*(orgId: int): DbConfig =
  ## Creates a database config for a specific organization using hardcoded org names
  # Get base config
  let baseConfig = getConfigFromEnv()
  
  # For Turso, create a URL that points to a specific branch
  # The URL format should be the base URL with a query parameter: ?branch=org-1
  let baseUrl = baseConfig.baseUrl
  let orgBranch = "org-" & $orgId
  
  # Format org-specific URL based on the Turso API
  var orgUrl = baseUrl
  if orgUrl.contains("?"):
    orgUrl = orgUrl & "&branch=" & orgBranch
  else:
    orgUrl = orgUrl & "?branch=" & orgBranch
  
  info fmt"Created org-specific config for org #{orgId}"
  info fmt"Original URL: {baseUrl}"
  info fmt"Org URL: {orgUrl}"
  
  # Return new config with org-specific URL
  return newDbConfig(orgUrl, baseConfig.authToken)

proc getOrgSpecificSchemaInfo*(orgId: int): Future[JsonNode] {.async.} =
  ## Gets direct schema info from an org-specific database
  let orgConfig = getOrgSpecificConfig(orgId)
  
  # Query the database schema
  let query = "SELECT * FROM sqlite_master WHERE type='table'"
  
  info fmt"Executing direct schema query on org #{orgId}"
  let response = await execQuery(orgConfig, query)
  
  return response