# Scheduler Component Documentation

## Purpose

The scheduler component is the core of the Medicare Email Scheduler application. It is responsible for:

1. Calculating when emails should be sent to Medicare contacts based on complex eligibility rules
2. Supporting both synchronous and asynchronous (parallel) processing of contacts
3. Distributing Annual Enrollment Period (AEP) emails across specified weeks
4. Respecting exclusion windows during which contacts should not receive emails
5. Generating different types of emails (Birthday, Effective Date, AEP, etc.)
6. Supporting both individual and batch processing modes

## Schema

### Core Data Structures

```nim
type
  EmailType* = enum
    Birthday = "Birthday",
    Effective = "Effective",
    AEP = "AEP",
    CarrierUpdate = "CarrierUpdate",
    PostExclusion = "PostExclusion"

  AepDistributionWeek* = enum
    Week1 = "First week (August 18)",
    Week2 = "Second week (August 25)",
    Week3 = "Third week (September 1)",
    Week4 = "Fourth week (September 7)"
    
  # For API response enrichment
  SchedulingMetadata* = object
    appliedRules*: seq[string]
    exclusions*: seq[string]
    stateRuleType*: string
    exclusionWindow*: tuple[start, endDate: string]
```

### Key Result Types

- `Result[seq[Email]]`: Result of calculating emails for a single contact
- `Future[Result[seq[Email]]]`: Async result for a single contact
- `Result[seq[seq[Email]]]`: Result of batch calculation (array of email arrays)
- `Future[Result[seq[seq[Email]]]]`: Async result of batch calculation

## Patterns

### Single Contact Processing Pattern

```nim
# 1. Get or create contact
let contact = ...

# 2. Calculate scheduled emails
let emailsResult = calculateScheduledEmails(contact, today)

# 3. Handle result
if emailsResult.isOk:
  let emails = emailsResult.value
  
  # 4. Process emails (save or log)
  for email in emails:
    # Process each email
else:
  # Handle error
  error "Failed to calculate emails: " & emailsResult.error.message
```

### Batch Processing Pattern

```nim
# 1. Get batch of contacts
let contacts = ...

# 2. Process in parallel
let batchResult = await calculateBatchScheduledEmailsAsync(contacts, today)

# 3. Handle batch result
if batchResult.isOk:
  let emailsBatch = batchResult.value
  
  # 4. Process each contact's emails
  for i, contact in contacts:
    let emails = emailsBatch[i]
    # Process emails for this contact
else:
  # Handle batch error
  error "Batch processing failed: " & batchResult.error.message
```

### Exclusion Window Pattern

```nim
# 1. Get exclusion window for contact
let (eewStart, eewEnd) = getExclusionWindow(contact, today)

# 2. Check if date is in exclusion window
if isInExclusionWindow(emailDate, eewStart, eewEnd):
  # Skip scheduling this email
  suppressed.add(emailType)
else:
  # Schedule the email
  emails.add(Email(...))
```

### AEP Distribution Pattern

```nim
# 1. Calculate base distribution
let 
  contactsCount = contacts.len
  baseContactsPerWeek = contactsCount div AEP_DISTRIBUTION_WEEKS
  remainder = contactsCount mod AEP_DISTRIBUTION_WEEKS

# 2. Distribute contacts to weeks
var weekAssignments: array[AEP_DISTRIBUTION_WEEKS, int]
for i in 0..<AEP_DISTRIBUTION_WEEKS:
  weekAssignments[i] = baseContactsPerWeek

# 3. Distribute remainder
for i in 0..<remainder:
  weekAssignments[i] += 1

# 4. Assign contacts to weeks
for i, contact in contacts:
  let weekIndex = i mod AEP_DISTRIBUTION_WEEKS
  let week = AepDistributionWeek(weekIndex)
  # Schedule email for this contact in the assigned week
```

## Interfaces

### Main Public Interfaces

```nim
# Calculate emails for a single contact (synchronous)
proc calculateScheduledEmails*(contact: Contact, today = now().utc, 
                              metadata: ptr SchedulingMetadata = nil): Result[seq[Email]]

# Async wrapper for calculating emails for a single contact
proc calculateScheduledEmailsAsync*(contact: Contact, today = now().utc,
                                    metadata: ptr SchedulingMetadata = nil): Future[Result[seq[Email]]] {.async.}

# Calculate emails for multiple contacts (synchronous)
proc calculateBatchScheduledEmails*(contacts: seq[Contact], today = now().utc): Result[seq[seq[Email]]]

# Calculate emails for multiple contacts in parallel (async)
proc calculateBatchScheduledEmailsAsync*(contacts: seq[Contact], today = now().utc): Future[Result[seq[seq[Email]]]] {.async.}

# Get exclusion window for a contact
proc getExclusionWindow*(contact: Contact, today: DateTime): tuple[start, endDate: DateTime]

# Get date for an AEP distribution week
proc getAepWeekDate*(week: AepDistributionWeek, currentYear: int): DateTime
```

### Helper Functions

```nim
# Check if a date is within an exclusion window
proc isInExclusionWindow(date: DateTime, eewStart, eewEnd: DateTime): bool

# Get a date in a specific year with same month/day
proc getYearlyDate(date: DateTime, year: int): DateTime

# Create metadata object for API responses
proc newSchedulingMetadata*(): SchedulingMetadata
```

## Invariants

1. **Contact Integrity**: Contacts must have both birthDate and effectiveDate to calculate emails properly
2. **Date Ordering**: No emails should be scheduled for dates in the past
3. **Exclusion Windows**: No emails should be scheduled during a contact's exclusion window
4. **Unique Email Types**: Each contact should not receive duplicate emails of the same type
5. **AEP Distribution**: AEP emails should be distributed as evenly as possible across the four weeks
6. **Year-Round States**: Contacts in year-round enrollment states should receive no scheduled emails
7. **Post-Exclusion Emails**: When emails are suppressed due to exclusion windows, a follow-up email should be scheduled after the window ends
8. **Chronological Order**: Emails for each contact should be sorted by date

## Error States

### Primary Error States

1. **Missing Date Fields**: 
   - Condition: Contact missing birthDate or effectiveDate
   - Handling: Return empty email list with warning message

2. **Year-Round Enrollment State**:
   - Condition: Contact state has year-round enrollment (e.g., CT)
   - Handling: Return empty email list with appropriate message

3. **Unknown State Rule**:
   - Condition: Contact has unknown state rule
   - Handling: Return empty email list with warning about unknown state

4. **Batch Processing Partial Failure**:
   - Condition: Some contacts in a batch fail to process
   - Handling: Return partial results for successful contacts, log errors for failed ones

5. **Exception during Processing**:
   - Condition: Unexpected exception during calculation
   - Handling: Catch exception, return error Result with message and code

### Recovery Mechanisms

1. **Fallback Dates**: If date parsing fails, use safe defaults
2. **AEP Rescheduling**: If preferred AEP week falls in exclusion window, try alternative weeks
3. **Partial Batch Results**: Continue processing other contacts when one fails
4. **Post-Window Emails**: Schedule follow-up emails after exclusion windows for suppressed emails