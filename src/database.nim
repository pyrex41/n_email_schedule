import httpclient, json, asyncdispatch, os, times, strutils, tables, locks, random, logging, options
import models, dotenv, utils  # Add utils for the Result type

# Initialize random number generator
randomize()

type
  DbConnection = ref object
    client: AsyncHttpClient
    inUse: bool
    lastUsed: float  # Timestamp for connection cleanup

  ConnectionPool = ref object
    connections: seq[DbConnection]
    mutex: Lock
    maxConnections: int
    idleTimeout: float  # Seconds before an idle connection is closed

  DbConfig* = object
    baseUrl*: string
    authToken*: string
    organizationId*: string  # Added organization ID
    pool: ConnectionPool     # Connection pool for this database

# Initialize a global connection pool for faster database access
var defaultPool: ConnectionPool

proc initConnectionPool(maxConn = 10, idleTimeout = 300.0): ConnectionPool =
  result = ConnectionPool(
    connections: @[],
    maxConnections: maxConn,
    idleTimeout: idleTimeout
  )
  initLock(result.mutex)

proc newDbConfig*(url: string, token: string, orgId: string = ""): DbConfig =
  # Create a new database configuration with a connection pool
  let pool = initConnectionPool()
  
  result = DbConfig(
    baseUrl: url.strip(trailing = true),
    authToken: token,
    organizationId: orgId,
    pool: pool
  )

proc getConfigFromEnv*(): DbConfig =
  # Try to load from .env file first (won't override existing env vars)
  loadEnv()
  
  # Initialize default connection pool if not already done
  if defaultPool == nil:
    defaultPool = initConnectionPool()
  
  result = DbConfig(
    baseUrl: getEnv("TURSO_DB_URL", "https://medicare-portal-pyrex41.turso.io"),
    authToken: getEnv("TURSO_AUTH_TOKEN", ""),
    organizationId: getEnv("DEFAULT_ORG_ID", ""),
    pool: defaultPool
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
    organizationId: orgId,
    pool: defaultConfig.pool  # Reuse the same connection pool
  )

proc getConnection(pool: ConnectionPool): Future[DbConnection] {.async.} =
  ## Get an available connection from the pool or create a new one
  ## This function is thread-safe using a mutex
  withLock pool.mutex:
    # First, try to find an available connection
    for conn in pool.connections:
      if not conn.inUse:
        # Found an available connection
        conn.inUse = true
        conn.lastUsed = epochTime()
        return conn
    
    # If we have capacity to create a new connection
    if pool.connections.len < pool.maxConnections:
      # Create a new connection
      let client = newAsyncHttpClient()
      let conn = DbConnection(
        client: client,
        inUse: true,
        lastUsed: epochTime()
      )
      pool.connections.add(conn)
      return conn
  
  # If we get here, all connections are in use and we've hit the max
  # Wait for a connection to become available (simple retry approach)
  await sleepAsync(100)  # Wait 100ms
  return await getConnection(pool)

proc releaseConnection(pool: ConnectionPool, conn: DbConnection) =
  ## Release a connection back to the pool
  withLock pool.mutex:
    conn.inUse = false
    conn.lastUsed = epochTime()

proc cleanupIdleConnections(pool: ConnectionPool) =
  ## Close idle connections that haven't been used for a while
  let now = epochTime()
  withLock pool.mutex:
    var i = 0
    while i < pool.connections.len:
      let conn = pool.connections[i]
      if not conn.inUse and (now - conn.lastUsed) > pool.idleTimeout:
        # Close the connection and remove it from the pool
        try:
          conn.client.close()
        except:
          discard # Ignore errors during cleanup
        
        # Remove from the pool (swap with last element and pop)
        pool.connections[i] = pool.connections[^1]
        pool.connections.setLen(pool.connections.len - 1)
      else:
        inc i

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
  # Get a connection from the pool
  var conn: DbConnection
  try:
    conn = await getConnection(config.pool)
  except Exception as e:
    return err[JsonNode]("Failed to get database connection: " & e.msg, 500)
  
  try:
    var endpoint = config.baseUrl & "/v2/pipeline"
    
    # If an organization ID is specified, add it to the query parameters or headers
    if config.organizationId != "":
      # In a real implementation, you might use this to select different databases
      # Here we're just appending it as a query parameter for demonstration
      endpoint = endpoint & "?org=" & config.organizationId
      info "Using organization-specific database: " & config.organizationId
    
    conn.client.headers = newHttpHeaders({
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
    
    let response = await conn.client.request(endpoint, httpMethod = HttpPost, body = $reqBody)
    let body = await response.body
    let jsonResult = parseJson(body)
    
    # Check for database errors
    if "error" in jsonResult:
      return err[JsonNode]("Database error: " & jsonResult["error"].getStr, 500)
    
    return ok(jsonResult)
  except Exception as e:
    return err[JsonNode]("Failed to execute database query: " & e.msg, 500)
  finally:
    # Always release the connection back to the pool
    releaseConnection(config.pool, conn)
    
    # Periodically clean up idle connections (1% chance per query)
    if rand(1.0) < 0.01:
      cleanupIdleConnections(config.pool)

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
      var emptyContacts: seq[Contact] = @[]
      return ok(emptyContacts)  # Return empty sequence for specific contact not found
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
    var emptyContacts: seq[Contact] = @[]
    return ok(emptyContacts)

proc getContactsBatch*(config: DbConfig, contactIds: seq[int]): Future[Result[seq[Contact]]] {.async.} =
  ## Efficiently fetch multiple contacts in a single query
  if contactIds.len == 0:
    var emptyContacts: seq[Contact] = @[]
    return ok(emptyContacts)
  
  var contacts: seq[Contact] = @[]
  var parseErrors: seq[string] = @[]
  
  # Build a query to fetch all contacts in a single request
  var query = """
    SELECT 
      id, first_name, last_name, email, 
      current_carrier, plan_type, effective_date, birth_date,
      tobacco_user, gender, state, zip_code, agent_id, 
      phone_number, status 
    FROM contacts
    WHERE id IN (
  """
  
  # Add placeholders for each ID
  var placeholders: seq[string] = @[]
  var args = newJArray()
  
  for id in contactIds:
    placeholders.add("?")
    args.add(%*{"type": "integer", "value": id})
  
  query &= placeholders.join(",") & ")"
  
  # Execute the batched query
  let queryResult = await execQuery(config, query, args)
  if not queryResult.isOk:
    return err[seq[Contact]](queryResult.error.message, queryResult.error.code)
  
  let response = queryResult.value
  
  # Validate response structure
  if "results" notin response or response["results"].len == 0:
    return err[seq[Contact]]("Invalid database response: missing results", 500)
  
  let result = response["results"][0]
  if "rows" notin result:
    # No data found for specified IDs
    var emptyContacts: seq[Contact] = @[]
    return ok(emptyContacts)  # Return empty sequence
  
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
    var emptyContacts: seq[Contact] = @[]
    return ok(emptyContacts)

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

proc saveEmailsBatch*(config: DbConfig, emails: seq[Email]): Future[Result[int]] {.async.} =
  ## Save multiple emails in a single database operation
  ## Returns the number of emails successfully saved
  
  if emails.len == 0:
    return ok(0)
  
  try:
    # Build a multi-value insert query
    let queryPrefix = """
      INSERT INTO contact_events
      (contact_id, event_type, metadata, created_at, organization_id)
      VALUES 
    """
    
    var placeholders: seq[string] = @[]
    var args = newJArray()
    
    # Use organization ID from config or a default
    let orgId = if config.organizationId != "": config.organizationId else: "default"
    
    # Add each email as a set of values
    for email in emails:
      placeholders.add("(?, ?, ?, ?, ?)")
      
      let metadata = %*{
        "type": email.emailType,
        "status": email.status,
        "reason": email.reason
      }
      
      args.add(%*{"type": "integer", "value": email.contactId})
      args.add(%*{"type": "text", "value": "email_scheduled"})
      args.add(%*{"type": "text", "value": $metadata})
      args.add(%*{"type": "text", "value": email.scheduledAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'")})
      args.add(%*{"type": "text", "value": orgId})
    
    let query = queryPrefix & placeholders.join(", ")
    
    # Execute the batched query
    let response = await execQuery(config, query, args)
    if not response.isOk:
      return err[int]("Failed to save emails in batch: " & response.error.message, response.error.code)
    
    # Check if the query was successful - return count of emails
    if "results" in response.value:
      return ok(emails.len)
    else:
      return err[int]("Failed to save emails in batch: No results returned", 500)
  except Exception as e:
    return err[int]("Failed to save emails in batch: " & e.msg, 500) 