import asyncdispatch, os, logging, times, strformat, options, tables, strutils
import database, models, dotenv

# Setup logging
var consoleLogger = newConsoleLogger(fmtStr="[$time] - $levelname: ")
addHandler(consoleLogger)

# Initialize file logger if needed
var fileLogger = newFileLogger("database_test.log", fmtStr="[$date $time] - $levelname: ")
addHandler(fileLogger)

proc checkEnvironmentVars() =
  # Check essential environment variables
  let requiredVars = ["TURSO_NIM_DB_URL", "TURSO_NIM_AUTH_TOKEN"]
  var missingVars: seq[string] = @[]
  
  for varName in requiredVars:
    if getEnv(varName) == "":
      missingVars.add(varName)
  
  if missingVars.len > 0:
    let mv = missingVars.join(", ")
    info fmt"Missing required environment variables: {mv}"
    info "Please ensure these are set in your .env file"
    quit(1)
  else:
    info "All required environment variables are present"

proc testGetOrgConfig() {.async.} =
  info "Testing getOrgDbConfig..."
  let mainConfig = getConfigFromEnv()
  
  # Log config details to help with debugging
  info fmt"Using main config with baseUrl: {mainConfig.baseUrl}"
  info fmt"Auth token length: {mainConfig.authToken.len}"
  info fmt"Auth token first 10 chars: '{mainConfig.authToken[0..9]}'"
  
  let orgResult = await getOrgDbConfig(mainConfig, 1)
  if orgResult.isOk:
    let orgConfig = orgResult.value
    info fmt"Successfully retrieved config for org #1:"
    info fmt"  Base URL: {orgConfig.baseUrl}"
    let maskedToken = if orgConfig.authToken.len > 15: 
                        orgConfig.authToken[0..7] & "..." & orgConfig.authToken[^8..^1] 
                      else: 
                        "token too short"
    info fmt"  Auth token: {maskedToken}"
  else:
    error fmt"Failed to get org config: {orgResult.error}"

proc testGetContact() {.async.} =
  info "Testing getContactById..."
  let mainConfig = getConfigFromEnv()
  
  # First get the org config
  let orgResult = await getOrgDbConfig(mainConfig, 1)
  if not orgResult.isOk:
    error fmt"Failed to get org config: {orgResult.error}"
    return

  let orgConfig = orgResult.value
  info fmt"Using organization config with baseUrl: {orgConfig.baseUrl}"
  
  # Then get the specific contact
  let contactOpt = await getContactById(orgConfig, 1)
  if isSome(contactOpt):
    let contact = get(contactOpt)
    info fmt"Found contact: {contact.firstName} {contact.lastName} - {contact.email}"
    let birthDate = contact.birthDate.format("yyyy-MM-dd")
    info fmt"Birth date: {birthDate}"
    let effectiveDate = contact.effectiveDate.format("yyyy-MM-dd")
    info fmt"Effective date: {effectiveDate}"
  else:
    warn "Contact #1 not found"

proc testSaveEmail() {.async.} =
  info "Testing saveEmail..."
  let mainConfig = getConfigFromEnv()
  
  # Get the org config
  let orgResult = await getOrgDbConfig(mainConfig, 1)
  if not orgResult.isOk:
    error fmt"Failed to get org config: {orgResult.error}"
    return

  let orgConfig = orgResult.value
  info fmt"Using organization config with baseUrl: {orgConfig.baseUrl}"
  
  # Create a test email
  let testEmail = Email(
    emailType: EmailType.Birthday,
    scheduledAt: now() + 1.days,
    reason: "Test email for contact #1"
  )
  
  # Save the email
  let success = await saveEmail(orgConfig, testEmail, 1)
  if success:
    info "Successfully saved test email for contact #1"
  else:
    error "Failed to save test email"

proc testBatchOperations() {.async.} =
  info "Testing batch operations..."
  let mainConfig = getConfigFromEnv()
  
  # Get the org config
  let orgResult = await getOrgDbConfig(mainConfig, 1)
  if not orgResult.isOk:
    error fmt"Failed to get org config: {orgResult.error}"
    return

  let orgConfig = orgResult.value
  info fmt"Using organization config with baseUrl: {orgConfig.baseUrl}"
  
  # Get total count of contacts
  let count = await countContacts(orgConfig)
  info fmt"Total contacts in database: {count}"
  
  # Get the first few contacts
  let contacts = await getContacts(orgConfig, 0, 5)
  info fmt"Retrieved {contacts.len} contacts:"
  
  # Create batch email test data
  var emailBatch: seq[tuple[email: Email, contactId: int]] = @[]
  
  for i, contact in contacts:
    info fmt"{i+1}. {contact.firstName} {contact.lastName} - {contact.email}"
    
    # Add a test email for each contact
    let testEmail = Email(
      emailType: if i mod 2 == 0: EmailType.Birthday else: EmailType.Effective,
      scheduledAt: now() + (i+1).days,
      reason: fmt"Batch test email #{i+1}"
    )
    
    emailBatch.add((testEmail, contact.id))
  
  # Test batch email saving if we have contacts
  if emailBatch.len > 0:
    let successCount = await saveEmailsBatch(orgConfig, emailBatch)
    info fmt"Successfully saved {successCount}/{emailBatch.len} emails in batch"
    
    # Test updating last emailed date
    var updates: seq[tuple[contactId: int, date: DateTime]] = @[]
    for (_, contactId) in emailBatch:
      updates.add((contactId, now()))
    
    let updateCount = await updateContactsLastEmailedDateBatch(orgConfig, updates)
    info fmt"Successfully updated {updateCount}/{updates.len} last emailed dates"
  else:
    warn "No contacts found for batch operations"

proc testChunkedProcessing() {.async.} =
  info "Testing chunked processing..."
  let mainConfig = getConfigFromEnv()
  
  # Get the org config
  let orgResult = await getOrgDbConfig(mainConfig, 1)
  if not orgResult.isOk:
    error fmt"Failed to get org config: {orgResult.error}"
    return

  let orgConfig = orgResult.value
  info fmt"Using organization config with baseUrl: {orgConfig.baseUrl}"
  
  # Define a simple processor function
  proc processor(contacts: seq[Contact]): Future[bool] {.async.} =
    info fmt"Processing chunk of {contacts.len} contacts..."
    for i, contact in contacts:
      info fmt"  Processing contact #{i+1}: {contact.firstName} {contact.lastName}"
      # Simulate some work
      await sleepAsync(10)
    return true
  
  # Process contacts in chunks of 3
  let success = await processContactsInChunks(orgConfig, 3, processor)
  info fmt"Chunked processing completed successfully: {success}"

proc main() {.async.} =
  info "Database Test Script"
  info "===================="
  
  # Load environment variables with overriding and debug enabled
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
  
  # Check for required variables
  checkEnvironmentVars()
  
  try:
    # Test getting organization config
    await testGetOrgConfig()
    info ""
    
    # Test getting a specific contact
    await testGetContact()
    info ""
    
    # Test saving an email
    await testSaveEmail()
    info ""
    
    # Test batch operations
    await testBatchOperations()
    info ""
    
    # Test chunked processing
    await testChunkedProcessing()
    
  except:
    let errorMsg = getCurrentExceptionMsg()
    error fmt"Error: {errorMsg}"

# Run the main procedure
waitFor main()
info "Test completed"