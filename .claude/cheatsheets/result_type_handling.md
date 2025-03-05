# Result Type Handling in n_email_schedule

## Basic Result Type Patterns

The codebase uses a Result type pattern for error handling:

```nim
# Define a Result type
type Result[T] = object
  case isOk*: bool
  of true:
    value*: T
  of false:
    error*: ErrorInfo

# Create a successful result
proc ok*[T](value: T): Result[T] =
  Result[T](isOk: true, value: value)

# Create an error result
proc err*[T](message: string, code: int = 500): Result[T] =
  Result[T](isOk: false, error: ErrorInfo(message: message, code: code))
```

## Common Result Type Operations

```nim
# Check if a result is successful
if result.isOk:
  # Access the value
  let value = result.value
  # Use value...
else:
  # Access the error information
  let errorMsg = result.error.message
  let errorCode = result.error.code
  # Handle error...
```

## Combining Result with Async

```nim
# Function that returns a Future[Result[T]]
proc asyncOperation*(): Future[Result[SomeType]] {.async.} =
  try:
    # Do something that might fail
    let value = await someOtherAsyncOperation()
    return ok(value)
  except Exception as e:
    return err[SomeType]("Operation failed: " & e.msg, 500)

# Calling and handling
proc handleAsyncResult*() {.async.} =
  let resultFuture = await asyncOperation()
  if resultFuture.isOk:
    let value = resultFuture.value
    # Use value
  else:
    # Handle error
    let errorMsg = resultFuture.error.message
```

## Common Patterns from n_email_schedule

### 1. Early Return on Error

```nim
let connectionResult = await getConnection(config)
if not connectionResult.isOk:
  return err[seq[Contact]](connectionResult.error.message, connectionResult.error.code)

let conn = connectionResult.value
# Continue with connection...
```

### 2. Error Logging with Fallback

```nim
let contactsResult = await getContacts(dbConfig)
if contactsResult.isOk:
  contacts = contactsResult.value
  info "Retrieved " & $contacts.len & " contacts from database"
else:
  error "Failed to retrieve contacts: " & contactsResult.error.message
  contacts = getTestContacts()  # Fallback to test data
```

### 3. Unwrapping Results in Loops

```nim
for i, future in futures:
  try:
    let emailsResult = await future
    if emailsResult.isOk:
      results[i] = emailsResult.value
    else:
      error "Failed to calculate emails: " & emailsResult.error.message
      results[i] = @[]  # Empty result as fallback
  except Exception as e:
    error "Error processing future: " & e.msg
    results[i] = @[]
```

### 4. Cascading Error Handling

```nim
proc operationWithDependencies*(): Future[Result[Output]] {.async.} =
  # First operation
  let result1 = await operation1()
  if not result1.isOk:
    return err[Output]("First operation failed: " & result1.error.message, result1.error.code)
  
  # Second operation depends on first
  let result2 = await operation2(result1.value)
  if not result2.isOk:
    return err[Output]("Second operation failed: " & result2.error.message, result2.error.code)
  
  # Final operation depends on second
  return await operation3(result2.value)
```

### 5. Batch Result Collection

```nim
proc batchOperation*(items: seq[Item]): Future[Result[seq[Output]]] {.async.} =
  var results: seq[Output] = @[]
  var errors: seq[string] = @[]
  
  for item in items:
    let itemResult = await processItem(item)
    if itemResult.isOk:
      results.add(itemResult.value)
    else:
      errors.add(itemResult.error.message)
  
  if errors.len > 0:
    return err[seq[Output]]("Some items failed: " & errors.join("; "))
  
  return ok(results)
```

## Best Practices

1. **Always Check isOk**: Never access `.value` without checking `.isOk` first
2. **Propagate Error Context**: Include context when propagating errors up the call stack
3. **Consistent Error Codes**: Use consistent error codes (e.g., HTTP status codes)
4. **Include Fallbacks**: Have fallback strategies when operations fail
5. **Logging**: Log errors at appropriate levels (error, warn, info)
6. **Type Consistency**: Make sure return types match the expected Result type
7. **Async Handling**: When combined with async, always await before checking isOk

## Examples from Codebase

### Database Connection Handling

```nim
proc getContacts*(config: DbConfig): Future[Result[seq[Contact]]] {.async.} =
  let connResult = await getConnection(config)
  if not connResult.isOk:
    return err[seq[Contact]](connResult.error.message, connResult.error.code)
  
  let conn = connResult.value
  
  try:
    let contacts = await conn.getAllRows(sql"""
      SELECT id, first_name, last_name, email, current_carrier, plan_type,
             effective_date, birth_date, tobacco_user, gender, state, 
             zip_code, agent_id, phone_number, status
      FROM contacts
    """)
    
    var result: seq[Contact] = @[]
    # Process rows...
    
    await releaseConnection(config, conn)
    return ok(result)
  except Exception as e:
    await releaseConnection(config, conn)
    return err[seq[Contact]]("Failed to get contacts: " & e.msg, 500)
```

### Email Calculation and Saving

```nim
# In n_email_schedule.nim
let batchResult = await calculateBatchScheduledEmailsAsync(contacts, today)
if batchResult.isOk:
  let emailsBatch = batchResult.value
  # Process batch...
  
  # Save emails
  if not config.isDryRun:
    let batchSaveResult = await saveEmailsBatch(dbConfig, emails)
    if batchSaveResult.isOk:
      info "Saved emails successfully"
    else:
      error "Failed to save emails: " & batchSaveResult.error.message
      # Fall back to individual saves
      for email in emails:
        let saveResult = await saveEmail(dbConfig, email, contact.id)
        if saveResult.isOk:
          info "Saved email successfully"
        else:
          error "Failed to save email: " & saveResult.error.message
else:
  error "Batch processing failed: " & batchResult.error.message
```