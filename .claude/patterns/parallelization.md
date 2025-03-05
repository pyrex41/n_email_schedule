# Parallelization Patterns in n_email_schedule

## Single-Contact Parallel Processing

### Description
This pattern involves splitting a complex processing task for a single entity into multiple parallel subtasks that can be executed concurrently, then combining their results.

### Implementation
```nim
# 1. Define specialized async functions for each subtask
proc scheduleBirthdayEmailAsync*(contact: Contact, today: DateTime): Future[Result[seq[Email]]] {.async.} =
  # Process birthday emails only
  # ...

proc scheduleEffectiveEmailAsync*(contact: Contact, today: DateTime): Future[Result[seq[Email]]] {.async.} =
  # Process effective date emails only
  # ...

# 2. Execute subtasks in parallel
var futures: seq[Future[Result[seq[Email]]]]
futures.add(scheduleBirthdayEmailAsync(contact, today))
futures.add(scheduleEffectiveEmailAsync(contact, today))
# ...add more specialized processing tasks

# 3. Wait for all subtasks to complete
let results = waitFor all(futures)

# 4. Combine results
var combinedResults: seq[Email] = @[]
for result in results:
  if result.isOk:
    combinedResults.add(result.value)

# 5. Process combined results if needed
sort(combinedResults)
```

### Usage Examples
- Email type processing in scheduler.nim
- Any entity that requires multiple independent calculations
- Processing different sections of a document in parallel

### Benefits
- Reduces processing time by utilizing multiple cores
- Simplifies code by separating concerns for each subtask
- Makes testing easier with isolated processing functions

### Considerations
- Overhead for setting up parallel tasks may not be worth it for simple operations
- Care must be taken to properly handle shared resources
- Error handling across parallel tasks requires careful design

## Batch Parallel Processing

### Description
This pattern involves processing multiple independent entities concurrently.

### Implementation
```nim
# 1. Create a set of futures for each entity
var futures: seq[Future[Result[T]]]
for entity in entities:
  futures.add(processEntityAsync(entity))

# 2. Wait for all processing to complete
for i, future in futures:
  let result = await future
  # Handle each result
```

### Usage Examples
- Batch email scheduling in scheduler.nim
- Processing multiple files/documents
- Processing multiple user requests

## Caching for Parallel Processing

### Description
Using caching to avoid redundant calculations when processing similar entities in parallel.

### Implementation
```nim
# 1. Create a cache
var cache = initTable[string, ResultType]()

# 2. Check cache before expensive calculations
proc calculate(key: string): ResultType =
  if cache.hasKey(key):
    return cache[key]
  
  # Perform expensive calculation
  let result = expensiveCalculation()
  
  # Store in cache
  cache[key] = result
  return result
```

### Usage Examples
- Exclusion window caching in scheduler.nim
- Caching database query results
- Caching parsing results for similar inputs