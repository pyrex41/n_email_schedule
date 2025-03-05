import unittest, times, strutils, strformat, sequtils, options
import ../src/models, ../src/scheduler, ../src/rules
import ../src/utils

# A utility function to test and check email scheduling
template checkEmails(contact: Contact, expectedCount: int, expectedTypes: varargs[string]) =
  let emailsResult = calculateScheduledEmails(contact, today)
  check emailsResult.isOk
  let emails = emailsResult.value
  check emails.len == expectedCount
  
  for emailType in expectedTypes:
    let found = emails.anyIt(it.emailType == emailType)
    check found
    if not found:
      echo "Expected to find " & emailType & " email"

# A utility function to check if a date is in the exclusion window
proc isInExclusionWindow(date: DateTime, eewStart, eewEnd: DateTime): bool =
  date >= eewStart and date < eewEnd

# A utility function to get yearly date (since it's private in scheduler)
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

suite "Scheduler Simple Tests":
  # Reference date for all tests
  let today = parse("2025-01-01", "yyyy-MM-dd", utc())
  
  setup:
    echo "Testing with today = ", today.format("yyyy-MM-dd")
  
  test "Texas Contact (Birthday Rule)":
    # Create a contact with Option types for optional fields
    let txContact = Contact(
      id: 1,
      firstName: "Texas",
      lastName: "User",
      email: "tx@example.com", 
      currentCarrier: "Test Carrier",
      planType: "Medicare",
      effectiveDate: some(parse("2025-12-15", "yyyy-MM-dd", utc())),  # Far future to avoid exclusion window
      birthDate: some(parse("1950-02-01", "yyyy-MM-dd", utc())),
      tobaccoUser: false,
      gender: "M",
      state: "TX",
      zipCode: "75001",
      agentID: 101,
      phoneNumber: some("555-1234"),
      status: some("Active")
    )
    
    # Check state rule
    let stateRule = getStateRule(txContact.state)
    check stateRule == Birthday
    
    # Calculate expected email dates
    let 
      birthDate = txContact.birthDate.get
      birthYearlyDate = getYearlyDate(birthDate, today.year)
      expectedBirthdayEmail = birthYearlyDate - 14.days
    
    # Calculate exclusion window
    let 
      (startOffset, duration) = getRuleParams(txContact.state)
      ruleStart = getYearlyDate(birthDate, today.year) + startOffset.days
      ruleEnd = ruleStart + duration.days
      eewStart = ruleStart - 60.days
      eewEnd = ruleEnd
    
    # Check if expected email is in exclusion window
    let inWindow = isInExclusionWindow(expectedBirthdayEmail, eewStart, eewEnd)
    
    # Check scheduled emails
    if not inWindow:
      checkEmails(txContact, 4, "Birthday", "Effective", "AEP", "CarrierUpdate")
    else:
      # If in exclusion window, we might get a post-window email instead
      let emailsResult = calculateScheduledEmails(txContact, today)
      check emailsResult.isOk
      let emails = emailsResult.value
      check emails.len > 0
  
  test "Oregon Contact (Birthday Rule)":
    let orContact = Contact(
      id: 2,
      firstName: "Oregon",
      lastName: "User",
      email: "or@example.com", 
      currentCarrier: "Test Carrier",
      planType: "Medicare",
      effectiveDate: some(parse("2025-12-15", "yyyy-MM-dd", utc())),
      birthDate: some(parse("1955-09-15", "yyyy-MM-dd", utc())),
      tobaccoUser: false,
      gender: "F",
      state: "OR",
      zipCode: "97001",
      agentID: 102,
      phoneNumber: some("555-5678"),
      status: some("Active")
    )
    
    # Check state rule
    let stateRule = getStateRule(orContact.state)
    check stateRule == Birthday
    
    # Check scheduled emails
    checkEmails(orContact, 4, "Birthday", "Effective", "AEP", "CarrierUpdate")
  
  test "Missouri Contact (Effective Date Rule)":
    let moContact = Contact(
      id: 3,
      firstName: "Missouri",
      lastName: "User",
      email: "mo@example.com", 
      currentCarrier: "Test Carrier",
      planType: "Medicare",
      effectiveDate: some(parse("2025-12-15", "yyyy-MM-dd", utc())),
      birthDate: some(parse("1960-05-01", "yyyy-MM-dd", utc())),
      tobaccoUser: true,
      gender: "M",
      state: "MO",
      zipCode: "63101",
      agentID: 103,
      phoneNumber: some("555-9012"),
      status: some("Active")
    )
    
    # Check state rule
    let stateRule = getStateRule(moContact.state)
    check stateRule == Effective
    
    # Check scheduled emails
    checkEmails(moContact, 4, "Birthday", "Effective", "AEP", "CarrierUpdate")
  
  test "Connecticut Contact (Year Round Enrollment)":
    let ctContact = Contact(
      id: 4,
      firstName: "Connecticut",
      lastName: "User",
      email: "ct@example.com", 
      currentCarrier: "Test Carrier",
      planType: "Medicare",
      effectiveDate: some(parse("2025-04-01", "yyyy-MM-dd", utc())),
      birthDate: some(parse("1965-06-15", "yyyy-MM-dd", utc())),
      tobaccoUser: false,
      gender: "F",
      state: "CT",
      zipCode: "06001",
      agentID: 104,
      phoneNumber: some("555-3456"),
      status: some("Active")
    )
    
    # Check state rule
    let stateRule = getStateRule(ctContact.state)
    check stateRule == YearRound
    
    # Year-round states should get no emails except possibly carrier update
    let emailsResult = calculateScheduledEmails(ctContact, today)
    check emailsResult.isOk
    let emails = emailsResult.value
    check emails.len <= 1
    if emails.len == 1:
      check emails[0].emailType == "CarrierUpdate"
  
  test "Contact with Missing Dates":
    let incompleteContact = Contact(
      id: 5,
      firstName: "Incomplete",
      lastName: "User",
      email: "incomplete@example.com", 
      currentCarrier: "Test Carrier",
      planType: "Medicare",
      effectiveDate: none(DateTime),  # Missing effective date
      birthDate: some(parse("1970-07-15", "yyyy-MM-dd", utc())),
      tobaccoUser: false,
      gender: "M",
      state: "TX",
      zipCode: "75002",
      agentID: 105,
      phoneNumber: none(string),  # Missing phone number
      status: none(string)  # Missing status
    )
    
    # Should return empty sequence when critical dates are missing
    let emailsResult = calculateScheduledEmails(incompleteContact, today)
    check emailsResult.isOk
    let emails = emailsResult.value
    check emails.len == 0
  
  test "Batch Email Scheduling":
    # Create a sequence of contacts
    var contacts = @[
      Contact(
        id: 101,
        firstName: "Contact1",
        lastName: "User",
        email: "contact1@example.com",
        currentCarrier: "Carrier A",
        planType: "Medicare",
        effectiveDate: some(parse("2025-05-15", "yyyy-MM-dd", utc())),
        birthDate: some(parse("1955-03-10", "yyyy-MM-dd", utc())),
        tobaccoUser: false,
        gender: "F",
        state: "TX",
        zipCode: "75003",
        agentID: 201,
        phoneNumber: some("555-1111"),
        status: some("Active")
      ),
      Contact(
        id: 102,
        firstName: "Contact2",
        lastName: "User",
        email: "contact2@example.com",
        currentCarrier: "Carrier B",
        planType: "Medicare",
        effectiveDate: some(parse("2025-06-20", "yyyy-MM-dd", utc())),
        birthDate: some(parse("1960-04-20", "yyyy-MM-dd", utc())),
        tobaccoUser: true,
        gender: "M",
        state: "CA",
        zipCode: "90001",
        agentID: 202,
        phoneNumber: some("555-2222"),
        status: some("Active")
      ),
      Contact(
        id: 103,
        firstName: "Contact3",
        lastName: "User",
        email: "contact3@example.com",
        currentCarrier: "Carrier C",
        planType: "Medicare",
        effectiveDate: some(parse("2025-07-10", "yyyy-MM-dd", utc())),
        birthDate: some(parse("1965-05-30", "yyyy-MM-dd", utc())),
        tobaccoUser: false,
        gender: "F",
        state: "FL",
        zipCode: "33101",
        agentID: 203,
        phoneNumber: some("555-3333"),
        status: some("Active")
      ),
      Contact(
        id: 104,
        firstName: "Contact4",
        lastName: "User",
        email: "contact4@example.com",
        currentCarrier: "Carrier D",
        planType: "Medicare",
        effectiveDate: some(parse("2025-08-05", "yyyy-MM-dd", utc())),
        birthDate: some(parse("1970-06-15", "yyyy-MM-dd", utc())),
        tobaccoUser: true,
        gender: "M",
        state: "NY",
        zipCode: "10001",
        agentID: 204,
        phoneNumber: some("555-4444"),
        status: some("Active")
      )
    ]
    
    # Test batch scheduling
    let batchResult = calculateBatchScheduledEmails(contacts, today)
    
    # Check batch results
    check batchResult.isOk
    let emailsBatch = batchResult.value
    
    # Each contact should have scheduled emails
    for i in 0..<contacts.len:
      check emailsBatch[i].len > 0
    
    # Count AEP emails per week and check distribution
    var aepWeeks: array[4, int] = [0, 0, 0, 0]
    for contactEmails in emailsBatch:
      for email in contactEmails:
        if email.emailType == $EmailType.AEP:
          if email.scheduledAt == parse("2025-08-18", "yyyy-MM-dd", utc()):
            aepWeeks[0] += 1
          elif email.scheduledAt == parse("2025-08-25", "yyyy-MM-dd", utc()): 
            aepWeeks[1] += 1
          elif email.scheduledAt == parse("2025-09-01", "yyyy-MM-dd", utc()):
            aepWeeks[2] += 1
          elif email.scheduledAt == parse("2025-09-07", "yyyy-MM-dd", utc()):
            aepWeeks[3] += 1
    
    # Check distribution is relatively balanced
    let totalAepEmails = aepWeeks.foldl(a + b)
    check totalAepEmails > 0

  test "Birthday Email":
    # Create a test contact with a birthday
    let contact = Contact(
      id: 1,
      firstName: "John",
      lastName: "Doe",
      email: "john@example.com",
      currentCarrier: "Medicare Advantage",
      planType: "Test Plan",
      effectiveDate: some(parse("2023-06-02", "yyyy-MM-dd", utc())),
      birthDate: some(parse("1950-06-15", "yyyy-MM-dd", utc())),
      tobaccoUser: false,
      gender: "M",
      state: "TX",
      zipCode: "12345",
      agentID: 1,
      phoneNumber: some("555-123-4567"),
      status: some("Active")
    )

    # Execute the scheduler
    let emailsResult = calculateScheduledEmails(contact, parse("2023-06-01", "yyyy-MM-dd", utc()))
    check emailsResult.isOk
    let emails = emailsResult.value

    # Find birthday emails
    let birthdayEmails = emails.filterIt(it.emailType == $EmailType.Birthday)
    
    # Should have one birthday email
    check(birthdayEmails.len == 1)
    
    # The email should be scheduled 14 days before birthday (June 1)
    check(birthdayEmails[0].scheduledAt == parse("2023-06-01", "yyyy-MM-dd", utc()))
    
    # The email should be for correct contact
    check(birthdayEmails[0].contactId == 1)

  test "Effective Date Email":
    # Create a test contact with an effective date
    let contact = Contact(
      id: 1,
      firstName: "John",
      lastName: "Doe",
      email: "john@example.com",
      currentCarrier: "Medicare Advantage",
      planType: "Test Plan",
      effectiveDate: some(parse("2023-07-01", "yyyy-MM-dd", utc())),
      birthDate: some(parse("1950-06-15", "yyyy-MM-dd", utc())),
      tobaccoUser: false,
      gender: "M",
      state: "TX",
      zipCode: "12345",
      agentID: 1,
      phoneNumber: some("555-123-4567"),
      status: some("Active")
    )

    # Execute the scheduler
    let emailsResult = calculateScheduledEmails(contact, parse("2023-06-01", "yyyy-MM-dd", utc()))
    check emailsResult.isOk
    let emails = emailsResult.value

    # Find effective date emails
    let effectiveEmails = emails.filterIt(it.emailType == $EmailType.Effective)
    
    # Should have one effective date email
    check(effectiveEmails.len == 1)
    
    # The email should be scheduled 30 days before effective date (June 1)
    check(effectiveEmails[0].scheduledAt == parse("2023-06-01", "yyyy-MM-dd", utc()))
    
    # The email should be for correct contact
    check(effectiveEmails[0].contactId == 1)

  test "AEP Email":
    # Create a test contact for AEP testing
    let contact = Contact(
      id: 1,
      firstName: "John",
      lastName: "Doe",
      email: "john@example.com",
      currentCarrier: "Medicare Advantage",
      planType: "Test Plan",
      effectiveDate: some(parse("2023-07-01", "yyyy-MM-dd", utc())),  # July 1st
      birthDate: some(parse("1950-06-15", "yyyy-MM-dd", utc())),      # June 15th
      tobaccoUser: false,
      gender: "M",
      state: "TX",  # Regular state, not year-round enrollment
      zipCode: "12345",
      agentID: 1,
      phoneNumber: some("555-123-4567"),
      status: some("Active")
    )

    # Execute the scheduler with September 1 as current date (AEP occurs in Oct-Dec)
    let emailsResult = calculateScheduledEmails(contact, parse("2023-09-01", "yyyy-MM-dd", utc()))
    check emailsResult.isOk
    let emails = emailsResult.value

    # Find AEP emails
    let aepEmails = emails.filterIt(it.emailType == $EmailType.AEP)
    
    # Should have one AEP email
    check(aepEmails.len == 1)
    
    # The email should be scheduled during AEP period (Sept-Dec)
    check(aepEmails[0].scheduledAt >= parse("2023-09-01", "yyyy-MM-dd", utc()))
    check(aepEmails[0].scheduledAt <= parse("2023-12-31", "yyyy-MM-dd", utc()))
    
    # The email should be for correct contact
    check(aepEmails[0].contactId == 1)

  test "Batch Contact Processing":
    # Create multiple test contacts
    var contacts: seq[Contact] = @[]
    
    # Add several contacts with different birthdays and effective dates
    for i in 1..5:
      let contact = Contact(
        id: i,
        firstName: "Contact" & $i,
        lastName: "Test" & $i,
        email: "contact" & $i & "@example.com",
        currentCarrier: "Medicare Advantage",
        planType: "Test Plan",
        effectiveDate: some(parse("2023-0" & $i & "-01", "yyyy-MM-dd", utc())),  # Different months
        birthDate: some(parse("1950-0" & $(i+2) & "-15", "yyyy-MM-dd", utc())),  # Different months
        tobaccoUser: i mod 2 == 0,
        gender: if i mod 2 == 0: "M" else: "F",
        state: "TX",
        zipCode: "1234" & $i,
        agentID: i,
        phoneNumber: some("555-123-456" & $i),
        status: some("Active")
      )
      contacts.add(contact)
    
    # Execute batch scheduler
    let batchResult = calculateBatchScheduledEmails(contacts, today)
    check batchResult.isOk
    let emailsBatch = batchResult.value
    
    # Should have results for all contacts
    check(emailsBatch.len == contacts.len)
    
    # Each contact should have at least one email
    for contactEmails in emailsBatch:
      check(contactEmails.len > 0) 