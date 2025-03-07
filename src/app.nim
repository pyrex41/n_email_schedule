import happyx
import birthday_rules, models, database, dotenv
import json, options, logging, strformat

# Setup logging
var consoleLogger = newConsoleLogger(fmtStr="[$time] - $levelname: ")
addHandler(consoleLogger)

# Initialize file logger
var fileLogger = newFileLogger("app.log", fmtStr="[$date $time] - $levelname: ")
addHandler(fileLogger)

# Load environment variables with debug enabled
info "Loading environment variables..."
let envVars = loadEnv(override = true, debug = true)

# Print environment source info
if "TURSO_NIM_DB_URL" in envVars:
  info "Using TURSO_NIM_DB_URL from .env file"
else:
  info "Using TURSO_NIM_DB_URL from system environment"

if "TURSO_NIM_AUTH_TOKEN" in envVars:
  info "Using TURSO_NIM_AUTH_TOKEN from .env file"
else:
  info "Using TURSO_NIM_AUTH_TOKEN from system environment"

# Check main config
let mainConfig = getConfigFromEnv()
info fmt"Using main config URL: {mainConfig.baseUrl}"
info fmt"Auth token length: {mainConfig.authToken.len}"

let port = getEnv("PORT", "5000").parseInt()

serve "127.0.0.1", port:
  get "/":
    let contact = Contact(
      id: 1,
      firstName: "John",
      lastName: "Doe",
      email: "john.doe@example.com",
      currentCarrier: "Blue Cross",
      planType: "Medicare Advantage",
      effectiveDate: now(),
      birthDate: now() - initTimeInterval(days = 365 * 65),  # 65 years old
      tobaccoUser: false,
      gender: "Male",
      state: "CA",
      zipCode: "90210",
      agentID: 42,
      phoneNumber: "555-123-4567",
      status: "Active"
    )
    let today = now()
    let year = today.year
    let emails = scheduleEmailsForContact(contact, today, year)
    
    # Convert emails to JSON using the toJson helper
    let jsonEmails = emails.toJson()
    
    # Set content type header and return JSON
    outHeaders["Content-Type"] = "application/json"
    return $jsonEmails

  get "/schedule/{orgId:int}/{contactId:int}":
    let mainConfig = getConfigFromEnv()
    let orgResult = await getOrgDbConfig(mainConfig, orgId)
    echo orgResult
    if not orgResult.isOk:
      # Set content type header and return JSON error
      outHeaders["Content-Type"] = "application/json"
      return $(%*{"error": orgResult.error})

    let orgConfig = orgResult.value
    let contactResult = await getContactById(orgConfig, contactId)
    echo contactResult
    
    if contactResult.isNone:
      # Set content type header and return JSON error for contact not found
      outHeaders["Content-Type"] = "application/json"
      return $(%*{"error": "Contact not found"})
    
    let contact = contactResult.get()
    let today = now()
    let year = today.year
    let emails = scheduleEmailsForContact(contact, today, year)
    
    # Convert emails to JSON using the toJson helper
    let jsonEmails = emails.toJson()  
    
    # Set content type header and return JSON
    outHeaders["Content-Type"] = "application/json"
    return $jsonEmails
  
  get "/schedule/{orgId:int}":
    let mainConfig = getConfigFromEnv()
    let orgResult = await getOrgDbConfig(mainConfig, orgId)
    echo orgResult
    if not orgResult.isOk:
      # Set content type header and return JSON error
      outHeaders["Content-Type"] = "application/json"
      return $(%*{"error": orgResult.error})

    let orgConfig = orgResult.value
    let totalContacts = await countContacts(orgConfig)
    info fmt"Total contacts found: {totalContacts}"
    
    # Initialize empty contacts and emails sequences
    var allContacts: seq[Contact] = @[]
    var allEmails: seq[Email] = @[]
    
    # Use pagination to fetch all contacts in chunks
    var offset = 0
    let chunkSize = 100
    
    while offset < totalContacts:
      info fmt"Fetching contacts chunk: offset={offset}, limit={chunkSize}"
      let contactsChunk = await getContacts(orgConfig, offset, chunkSize)
      if contactsChunk.len == 0:
        break  # No more contacts to fetch
      
      # Add the fetched contacts to our collection
      allContacts.add(contactsChunk)
      
      # Update offset for the next chunk
      offset += contactsChunk.len
      
      # Safety check - if we got fewer than requested, we're done
      if contactsChunk.len < chunkSize:
        break
    
    info fmt"Processing emails for {allContacts.len} contacts"
    
    # Schedule emails for each contact
    for contact in allContacts:
      let today = now()
      let year = today.year
      let contactEmails = scheduleEmailsForContact(contact, today, year)
      allEmails.add(contactEmails)
    
    info fmt"Generated {allEmails.len} emails"
    
    # Set content type and return the emails as JSON
    outHeaders["Content-Type"] = "application/json"
    return $allEmails.toJson()

  get "/contact/{orgId:int}":
    # Get pagination parameters from query parameters, with defaults
    let offsetParam = query.getOrDefault("offset", "0")
    let limitParam = query.getOrDefault("limit", "100")
    
    # Parse pagination parameters with error handling
    var offset = 0
    var limit = 100
    try:
      offset = parseInt(offsetParam)
      limit = parseInt(limitParam)
      # Apply reasonable bounds to limit
      if limit <= 0:
        limit = 1
      elif limit > 500:
        limit = 500
    except ValueError:
      # If parsing fails, use defaults
      offset = 0
      limit = 100
    
    info fmt"Pagination parameters: offset={offset}, limit={limit}"

    let mainConfig = getConfigFromEnv()
    let orgResult = await getOrgDbConfig(mainConfig, orgId)
    echo orgResult
    if not orgResult.isOk:
      # Set content type header and return JSON error
      outHeaders["Content-Type"] = "application/json"
      return $(%*{"error": orgResult.error})
    
    let orgConfig = orgResult.value
    let totalContacts = await countContacts(orgConfig)
    info fmt"Total contacts found: {totalContacts}"
    
    # Fetch only the requested chunk of contacts
    info fmt"Fetching contacts: offset={offset}, limit={limit}"
    let contacts = await getContacts(orgConfig, offset, limit)
    
    # Create a JSON array for contacts manually
    var contactsJson = newJArray()
    for contact in contacts:
      contactsJson.add(contact.toJson())
    
    # Set content type and return the contacts as JSON with pagination metadata
    outHeaders["Content-Type"] = "application/json"
    return $(%*{
      "totalContacts": totalContacts,
      "offset": offset,
      "limit": limit,
      "count": contacts.len,
      "contacts": contactsJson
    })
    
    
  get "/contact/{orgId:int}/{contactId:int}":
    let mainConfig = getConfigFromEnv()
    let orgResult = await getOrgDbConfig(mainConfig, orgId)
    echo orgResult
    if not orgResult.isOk:
      # Set content type header and return JSON error
      outHeaders["Content-Type"] = "application/json"
      return $(%*{"error": orgResult.error})
    
    let orgConfig = orgResult.value
    let contactResult = await getContactById(orgConfig, contactId)
    echo contactResult
    
    if contactResult.isNone:
      # Set content type header and return JSON error for contact not found
      outHeaders["Content-Type"] = "application/json"
      return $(%*{"error": "Contact not found"})
    
    # Contact was found, we can safely get() it
    let contact = contactResult.get()
    outHeaders["Content-Type"] = "application/json"
    return $(%*{"contact": contact.toJson()})
    
    
  # New direct schema check endpoint
  get "/debug/schema":
    info "Running direct schema check"
    let mainConfig = getConfigFromEnv()
    echo "mainConfig: " & mainConfig.baseUrl
    echo "authToken: " & mainConfig.authToken[0..10] & "..." & mainConfig.authToken[^10..^1]
    
    # Directly query the sqlite_master table to see all tables
    info "Executing direct query on sqlite_master table"
    let query = "SELECT name FROM sqlite_master WHERE type='table'"
    
    # Execute the query with extra logging
    try:
      info "About to execute query: " & query
      let response = await execQuery(mainConfig, query)
      info "Query executed, response type: " & $response.kind & ", size: " & $response.len
      
      # Log the raw response for debugging
      echo "Raw response: " & $response
      
      # Return response for debugging
      outHeaders["Content-Type"] = "application/json"
      return $(%*{
        "mainConfigUrl": mainConfig.baseUrl,
        "authTokenLength": mainConfig.authToken.len,
        "rawResponse": response
      })
    except Exception as e:
      # Catch and log any exceptions
      let msg = getCurrentExceptionMsg()
      error "Exception in schema endpoint: " & msg
      outHeaders["Content-Type"] = "application/json"
      return $(%*{
        "error": msg
      })

