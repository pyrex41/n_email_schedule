import httpclient, json, asyncdispatch, os, times, strutils
import models, dotenv

type
  DbConfig* = object
    baseUrl*: string
    authToken*: string
    organizationId*: string  # Added organization ID

proc newDbConfig*(url: string, token: string, orgId: string = ""): DbConfig =
  result = DbConfig(
    baseUrl: url.strip(trailing = true),
    authToken: token,
    organizationId: orgId
  )

proc getConfigFromEnv*(): DbConfig =
  # Try to load from .env file first (won't override existing env vars)
  loadEnv()
  
  result = DbConfig(
    baseUrl: getEnv("TURSO_DB_URL", "https://medicare-portal-pyrex41.turso.io"),
    authToken: getEnv("TURSO_AUTH_TOKEN", ""),
    organizationId: getEnv("DEFAULT_ORG_ID", "")
  )

proc getOrgDbConfig*(orgId: string): DbConfig =
  ## Get database configuration for a specific organization
  let defaultConfig = getConfigFromEnv()
  
  if orgId == "":
    # If no org ID provided, use default
    return defaultConfig
  
  # For now, we're just setting the org ID, but in a real system
  # you might switch the baseUrl or use a different connection method
  # based on the organization
  result = DbConfig(
    baseUrl: defaultConfig.baseUrl,
    authToken: defaultConfig.authToken,
    organizationId: orgId
  )

proc parseIsoDate(dateStr: string): DateTime =
  # Parse ISO date format like "2023-04-15T00:00:00Z"
  try:
    result = parse(dateStr, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
  except:
    # Fallback for simpler date format
    try:
      result = parse(dateStr, "yyyy-MM-dd", utc())
    except:
      # Default to current date if parsing fails
      result = now()

proc execQuery*(config: DbConfig, sql: string, args: JsonNode = newJArray()): Future[Result[JsonNode]] {.async.} =
  try:
    let client = newAsyncHttpClient()
    var endpoint = config.baseUrl & "/v2/pipeline"
    
    # If an organization ID is specified, add it to the query parameters or headers
    if config.organizationId != "":
      # In a real implementation, you might use this to select different databases
      # Here we're just appending it as a query parameter for demonstration
      endpoint = endpoint & "?org=" & config.organizationId
      info "Using organization-specific database: " & config.organizationId
    
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
    
    let response = await client.request(endpoint, httpMethod = HttpPost, body = $reqBody)
    let body = await response.body
    let jsonResult = parseJson(body)
    client.close()
    
    # Check for database errors
    if "error" in jsonResult:
      return err[JsonNode]("Database error: " & jsonResult["error"].getStr, 500)
    
    return ok(jsonResult)
  except Exception as e:
    return err[JsonNode]("Failed to execute database query: " & e.msg, 500)

proc getContacts*(config: DbConfig, contactId: int = 0): Future[Result[seq[Contact]]] {.async.} =
  var contacts: seq[Contact] = @[]
  var parseErrors: seq[string] = @[]
  
  # Build the query, adding a WHERE clause if contactId is specified
  var query = """
    SELECT 
      id, first_name, last_name, email, 
      current_carrier, plan_type, effective_date, birth_date,
      tobacco_user, gender, state, zip_code, agent_id, 
      phone_number, status 
    FROM contacts
  """
  
  if contactId > 0:
    query &= " WHERE id = ?"
  
  # Prepare arguments if needed
  var args = newJArray()
  if contactId > 0:
    args.add(%*{"type": "integer", "value": contactId})
  
  # Execute the query
  let queryResult = await execQuery(config, query, args)
  if not queryResult.isOk:
    return err[seq[Contact]](queryResult.error.message, queryResult.error.code)
  
  let response = queryResult.value
  
  # Validate response structure
  if "results" notin response or response["results"].len == 0:
    return err[seq[Contact]]("Invalid database response: missing results", 500)
  
  let result = response["results"][0]
  if "rows" notin result:
    # No data could be fine if filtering by ID and none found
    if contactId > 0:
      return ok(@[])  # Return empty sequence for specific contact not found
    else:
      return err[seq[Contact]]("No data returned from database", 404)
  
  # Process rows
  for i, row in result["rows"]:
    try:
      # Handle date fields with Option[DateTime]
      var effectiveDateOpt: Option[DateTime]
      var birthDateOpt: Option[DateTime]
      
      try:
        if row[6].kind != JNull:
          effectiveDateOpt = some(parseIsoDate(row[6].getStr))
        else:
          effectiveDateOpt = none(DateTime)
      except Exception as e:
        parseErrors.add("Row " & $i & " effective date parse error: " & e.msg)
        effectiveDateOpt = none(DateTime)
        
      try:
        if row[7].kind != JNull:
          birthDateOpt = some(parseIsoDate(row[7].getStr))
        else:
          birthDateOpt = none(DateTime)
      except Exception as e:
        parseErrors.add("Row " & $i & " birth date parse error: " & e.msg)
        birthDateOpt = none(DateTime)
        
      # Create contact with Option fields
      let contact = Contact(
        id: row[0].getInt,
        firstName: row[1].getStr,
        lastName: row[2].getStr,
        email: row[3].getStr,
        currentCarrier: row[4].getStr,
        planType: row[5].getStr,
        effectiveDate: effectiveDateOpt,
        birthDate: birthDateOpt,
        tobaccoUser: row[8].getBool,
        gender: row[9].getStr,
        state: row[10].getStr,
        zipCode: row[11].getStr,
        agentID: row[12].getInt,
        phoneNumber: if row[13].kind != JNull: some(row[13].getStr) else: none(string),
        status: if row[14].kind != JNull: some(row[14].getStr) else: none(string)
      )
      contacts.add(contact)
    except Exception as e:
      parseErrors.add("Error processing row " & $i & ": " & e.msg)
  
  # If we have any contacts, return them with warnings if needed
  if contacts.len > 0:
    if parseErrors.len > 0:
      echo "Warning: Some contacts were processed with errors: " & parseErrors.join("; ")
    return ok(contacts)
  else:
    # If we have no contacts but have errors, return the errors
    if parseErrors.len > 0:
      return err[seq[Contact]]("Failed to process contacts: " & parseErrors[0], 500)
    # Otherwise just return empty list
    return ok(@[])

proc saveEmail*(config: DbConfig, email: Email, contactId: int): Future[Result[bool]] {.async.} =
  try:
    let query = """
      INSERT INTO contact_events
      (contact_id, event_type, metadata, created_at, organization_id)
      VALUES (?, ?, ?, ?, ?)
    """
    
    let metadata = %*{
      "type": email.emailType,
      "status": email.status,
      "reason": email.reason
    }
    
    # Use organization ID from config or a default
    let orgId = if config.organizationId != "": config.organizationId else: "default"
    
    let args = %*[
      {"type": "integer", "value": contactId},
      {"type": "text", "value": "email_scheduled"},
      {"type": "text", "value": $metadata},
      {"type": "text", "value": email.scheduledAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'")},
      {"type": "text", "value": orgId}
    ]
    
    let response = await execQuery(config, query, args)
    if not response.isOk:
      return err[bool]("Failed to save email: " & response.error.message, response.error.code)
    
    # Check if the query was successful
    if "results" in response.value:
      return ok(true)
    else:
      return err[bool]("Failed to save email: No results returned", 500)
  except Exception as e:
    return err[bool]("Failed to save email: " & e.msg, 500) 