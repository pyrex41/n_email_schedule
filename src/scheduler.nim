import times, algorithm, sequtils, strformat
import models, rules

type
  EmailType* = enum
    Birthday = "Birthday",
    Effective = "Effective",
    AEP = "AEP",
    CarrierUpdate = "CarrierUpdate"

  AepDistributionWeek* = enum
    Week1 = "First week (August 18)",
    Week2 = "Second week (August 25)",
    Week3 = "Third week (September 1)",
    Week4 = "Fourth week (September 7)"

proc isInExclusionWindow(date: DateTime, eewStart, eewEnd: DateTime): bool =
  date >= eewStart and date < eewEnd

proc getYearlyDate(date: DateTime, year: int): DateTime =
  try:
    # Extract month and day from the date
    let 
      monthInt = ord(date.month)
      dayInt = min(date.monthday, 28) # Safe value for all months

    # Create a new date with the same month/day but in target year
    result = parse(fmt"{year:04d}-{monthInt:02d}-{dayInt:02d}", "yyyy-MM-dd", utc())
    
    # If date has passed this year, use next year
    if result < now():
      result = parse(fmt"{year+1:04d}-{monthInt:02d}-{dayInt:02d}", "yyyy-MM-dd", utc())
  except:
    # Fallback to January 1 of the given year
    result = parse(fmt"{year:04d}-01-01", "yyyy-MM-dd", utc())

proc getExclusionWindow(contact: Contact, today: DateTime): tuple[start,
    endDate: DateTime] =
  try:
    let
      stateRule = getStateRule(contact.state)
      (startOffset, duration) = getRuleParams(contact.state)
      refDate = if stateRule == Birthday: contact.birthDate else: contact.effectiveDate
      ruleStart = getYearlyDate(refDate, today.year) + startOffset.days
      ruleEnd = ruleStart + duration.days

    result = (start: ruleStart - 60.days, endDate: ruleEnd)
  except:
    # Fallback to a safe default if there's any error
    let currentDate = now().utc
    result = (
      start: currentDate - 30.days,
      endDate: currentDate + 30.days
    )

proc getAepWeekDate*(week: AepDistributionWeek, currentYear: int): DateTime =
  ## Get the date for each AEP distribution week
  try:
    case week
    of Week1: # First week - August 18
      result = parse(fmt"{currentYear:04d}-08-18", "yyyy-MM-dd", utc())
    of Week2: # Second week - August 25
      result = parse(fmt"{currentYear:04d}-08-25", "yyyy-MM-dd", utc())
    of Week3: # Third week - September 1
      result = parse(fmt"{currentYear:04d}-09-01", "yyyy-MM-dd", utc())
    of Week4: # Fourth week - September 7
      result = parse(fmt"{currentYear:04d}-09-07", "yyyy-MM-dd", utc())
  except:
    # Default to August 18th if there's an error
    result = parse(fmt"{currentYear:04d}-08-18", "yyyy-MM-dd", utc())

proc scheduleEmail(emails: var seq[Email], emailType: EmailType,
                  date: DateTime, eewStart, eewEnd: DateTime,
                  today: DateTime, reason = ""): bool =
  if date >= today and not isInExclusionWindow(date, eewStart, eewEnd):
    emails.add(Email(
      emailType: $emailType,
      status: "Pending",
      scheduledAt: date,
      reason: reason
    ))
    return true
  return false

proc calculateScheduledEmails*(contact: Contact, today: DateTime): seq[Email] =
  result = @[]

  try:
    let stateRule = getStateRule(contact.state)
    let currentYear = today.year

    # Skip for year-round enrollment states
    if stateRule == YearRound:
      return result

    # Calculate exclusion window
    let (eewStart, eewEnd) = getExclusionWindow(contact, today)

    # Track suppressed emails for post-exclusion window email
    var suppressed: seq[EmailType] = @[]

    # Birthday email (14 days before)
    let
      birthdayDate = getYearlyDate(contact.birthDate, currentYear)
      birthdayEmailDate = birthdayDate - 14.days

    if not scheduleEmail(result, Birthday, birthdayEmailDate, eewStart, eewEnd, today):
      if isInExclusionWindow(birthdayEmailDate, eewStart, eewEnd):
        suppressed.add(Birthday)

    # Effective date email (30 days before)
    let
      effectiveDate = getYearlyDate(contact.effectiveDate, currentYear)
      effectiveEmailDate = effectiveDate - 30.days

    if not scheduleEmail(result, Effective, effectiveEmailDate, eewStart,
        eewEnd, today):
      if isInExclusionWindow(effectiveEmailDate, eewStart, eewEnd):
        suppressed.add(Effective)

    # AEP email - Try each week in sequence until one works
    var aepScheduled = false
    for week in [Week1, Week2, Week3, Week4]:
      let aepDate = getAepWeekDate(week, currentYear)
      if scheduleEmail(result, AEP, aepDate, eewStart, eewEnd, today, 
                      "AEP - " & $week):
        aepScheduled = true
        break
    
    if not aepScheduled:
      suppressed.add(AEP)

    # Post-exclusion window email
    if suppressed.len > 0 and today <= eewEnd:
      # When a state has a rule window and emails were suppressed
      let postWindowDate = eewEnd + 1.days
      if postWindowDate >= today:
        let emailType = if stateRule == Birthday: Birthday else: Effective
        if emailType in suppressed:
          result.add(Email(
            emailType: $emailType,
            status: "Pending",
            scheduledAt: postWindowDate,
            reason: "Post-window " & $emailType & " email"
          ))

    # Carrier update email - only for non-year-round states
    if stateRule != YearRound:
      let carUpdateDate = parse(fmt"{currentYear:04d}-01-31", "yyyy-MM-dd", utc())
      if carUpdateDate >= today:
        result.add(Email(
          emailType: $EmailType.CarrierUpdate,
          status: "Pending",
          scheduledAt: carUpdateDate,
          reason: "Annual carrier update"
        ))

    # Sort emails by date
    try:
      result.sort(proc(x, y: Email): int = cmp(x.scheduledAt, y.scheduledAt))
    except:
      # Just return unsorted if sorting fails
      discard
  except Exception as e:
    # On any error, return empty sequence
    result = @[]

proc calculateBatchScheduledEmails*(contacts: seq[Contact],
    today: DateTime): seq[seq[Email]] =
  
  ## distributing AEP emails across four weeks as specified in requirements

  # Initialize the result with empty sequences for each contact
  result = newSeq[seq[Email]](contacts.len)

  # First, calculate regular emails for each contact individually
  for i, contact in contacts:
    try:
      result[i] = calculateScheduledEmails(contact, today)
    except:
      # If there's an error, initialize with an empty sequence
      result[i] = @[]

  # For AEP emails, if we have multiple contacts, we need to distribute
  # them evenly across the four distribution weeks
  if contacts.len > 1:
    try:
      # Remove any existing AEP emails (we'll redistribute them)
      for i in 0..<result.len:
        result[i] = result[i].filterIt(it.emailType != $AEP)

      # Calculate the number of contacts per week
      # Use integer division to get base count and remainder
      let
        currentYear = today.year
        contactsCount = contacts.len
        baseContactsPerWeek = contactsCount div 4
        remainder = contactsCount mod 4

      # Distribute contacts to weeks initially
      var weekAssignments: array[4, int] = [baseContactsPerWeek, baseContactsPerWeek,
                                           baseContactsPerWeek, baseContactsPerWeek]

      # Distribute the remainder (if any)
      for i in 0..<remainder:
        weekAssignments[i] += 1

      # Initial assignment of contacts to weeks
      var initialWeekAssignments: seq[AepDistributionWeek] = @[]
      var weekIndex = 0
      
      for i in 0..<contactsCount:
        initialWeekAssignments.add(AepDistributionWeek(i mod 4))
      
      # Schedule AEP emails for each contact
      for i, contact in contacts:
        # Skip AEP emails for year-round enrollment states
        if getStateRule(contact.state) == YearRound:
          continue
          
        # Get the contact's exclusion window
        let (eewStart, eewEnd) = getExclusionWindow(contact, today)
        var scheduled = false
        
        # First try the initially assigned week
        let initialWeek = initialWeekAssignments[i]
        let initialDate = getAepWeekDate(initialWeek, currentYear)
        
        if not isInExclusionWindow(initialDate, eewStart, eewEnd) and initialDate >= today:
          result[i].add(Email(
            emailType: $AEP,
            status: "Pending",
            scheduledAt: initialDate,
            reason: "AEP - " & $initialWeek
          ))
          scheduled = true
        else:
          # If initial week fails, try all other weeks in order
          for week in [Week1, Week2, Week3, Week4]:
            if week == initialWeek:
              continue # Skip the week we already tried
              
            let weekDate = getAepWeekDate(week, currentYear)
            if not isInExclusionWindow(weekDate, eewStart, eewEnd) and weekDate >= today:
              result[i].add(Email(
                emailType: $AEP,
                status: "Pending",
                scheduledAt: weekDate,
                reason: "AEP - " & $week & " (fallback)"
              ))
              scheduled = true
              break
      
      # Sort all email sequences by date
      for i in 0..<result.len:
        if result[i].len > 0:
          try:
            result[i].sort(proc(x, y: Email): int = cmp(x.scheduledAt, y.scheduledAt))
          except:
            # Just return unsorted if sorting fails
            discard
    except:
      # On any error in the batch processing, just return the individual results
      discard

  return result
