# Asynchronous Programming Patterns in n_email_schedule

## Basic Async Pattern

The codebase follows these key patterns for asynchronous programming:

```nim
import asyncdispatch

# Mark function as async
proc someFunction*(param: Type): Future[ReturnType] {.async.} =
  # Function body
  result = someValue

# Call async function
proc callingFunction*() {.async.} =
  let result = await someFunction(param)
  # Use result
```

## Async with Result Type

For functions that can fail, we combine async with Result type:

```nim
proc someAsyncFunction*(param: Type): Future[Result[ReturnType]] {.async.} =
  try:
    # Function body
    return ok(someValue)
  except Exception as e:
    return err[ReturnType]("Error message: " & e.msg, 500)

# Calling and handling
proc callingFunction*() {.async.} =
  let resultFuture = await someAsyncFunction(param)
  if resultFuture.isOk:
    let value = resultFuture.value
    # Use value
  else:
    # Handle error
    let errorMsg = resultFuture.error.message
    let errorCode = resultFuture.error.code
```

## Async Wrappers

For CPU-bound functions that need to be called from async contexts:

```nim
# Original synchronous function
proc calculateSomething*(param: Type): Result[ReturnType] =
  # CPU-bound work
  return ok(result)

# Async wrapper
proc calculateSomethingAsync*(param: Type): Future[Result[ReturnType]] {.async.} =
  return calculateSomething(param)

# Usage
proc usageExample*() {.async.} =
  let result = await calculateSomethingAsync(param)
  # Process result
```

## Parallel Processing with Async

For processing multiple items in parallel:

```nim
proc processBatchAsync*(items: seq[Item]): Future[Result[seq[ProcessedItem]]] {.async.} =
  var futures = newSeq[Future[Result[ProcessedItem]]](items.len)
  var results = newSeq[ProcessedItem](items.len)
  
  # Start all async operations
  for i, item in items:
    futures[i] = processItemAsync(item)
  
  # Await all futures
  for i, future in futures:
    let result = await future
    if result.isOk:
      results[i] = result.value
    else:
      return err[seq[ProcessedItem]](result.error.message, result.error.code)
  
  return ok(results)
```

## Important Rules

1. **Export Async Functions**: Mark async functions with `*` for export
2. **Always Await**: Always await futures before accessing their values
3. **Error Handling**: Use Result type to handle errors in async contexts
4. **Proper Initialization**: Initialize sequences with proper size when collecting results
5. **Avoid Blocking**: Never use blocking I/O in async functions
6. **Concurrent Limits**: Be careful with database connection limits when running many parallel operations
7. **Propagate Errors**: Return early with error if a critical async operation fails

## Common Anti-patterns to Avoid

1. ❌ Forgetting to await a Future:
   ```nim
   let result = someAsyncFunction() # Wrong - returns a Future, not the value
   ```

2. ❌ Not handling Result type errors:
   ```nim
   let result = await someAsyncFunction()
   let value = result.value # Wrong - might crash if result is an error
   ```

3. ❌ Using blocking I/O in async functions:
   ```nim
   proc badAsync*() {.async.} =
     let data = readFile("path.txt") # Wrong - blocks the event loop
   ```

4. ❌ Creating too many parallel operations:
   ```nim
   for item in hugeList:
     asyncCheck processItemAsync(item) # Wrong - could exhaust resources
   ```

## Examples from Codebase

### Async Database Connection Management

```nim
proc getConnection*(config: DbConfig): Future[Result[DbConn]] {.async.} =
  try:
    withLock connectionPoolLock:
      if not connectionPool.hasKey(config.url):
        # Initialize pool for this connection string
        connectionPool[config.url] = @[]
      
      # Check if there's an available connection
      if connectionPool[config.url].len > 0:
        return ok(connectionPool[config.url].pop())
    
    # If no connection is available, create a new one
    let conn = open(config.url, config.user, config.password, config.database)
    return ok(conn)
  except Exception as e:
    return err[DbConn]("Failed to get database connection: " & e.msg, 500)
```

### Parallel Contact Processing

```nim
proc calculateBatchScheduledEmailsAsync*(contacts: seq[Contact], today = now().utc): Future[Result[seq[seq[Email]]]] {.async.} =
  # Create futures for all contact calculations
  var futures = newSeq[Future[Result[seq[Email]]]](contacts.len)
  
  # Start all contact calculations in parallel
  for i, contact in contacts:
    futures[i] = calculateScheduledEmailsAsync(contact, today)
  
  # Wait for all futures to complete and collect results
  var results = newSeq[seq[Email]](contacts.len)
  for i, future in futures:
    try:
      let emailsResult = await future
      if emailsResult.isOk:
        results[i] = emailsResult.value
      else:
        # Store error message but continue processing other contacts
        results[i] = @[]
    except Exception as e:
      # Handle any exceptions in awaiting futures
      results[i] = @[]
  
  return ok(results)
```