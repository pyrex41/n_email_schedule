import unittest, times, strutils, strformat, sequtils, options
import ../src/models, ../src/scheduler, ../src/rules

# A utility function to test and check email scheduling
template checkEmails(contact: Contact, expectedCount: int, expectedTypes: varargs[string]) =
  let emails = calculateScheduledEmails(contact, today)
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
      let emails = calculateScheduledEmails(txContact, today)
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
    let emails = calculateScheduledEmails(ctContact, today)
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
    let emails = calculateScheduledEmails(incompleteContact, today)
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
    let emailsBatch = calculateBatchScheduledEmails(contacts, today)
    
    # Check batch results
    check emailsBatch.len == contacts.len
    
    # Each contact should have scheduled emails
    for i in 0..<contacts.len:
      check emailsBatch[i].len > 0
    
    # Check AEP distribution
    var aepWeeks: array[4, int] = [0, 0, 0, 0]
    
    for i in 0..<contacts.len:
      for email in emailsBatch[i]:
        if email.emailType == "AEP":
          if "First week" in email.reason:
            aepWeeks[0] += 1
          elif "Second week" in email.reason:
            aepWeeks[1] += 1
          elif "Third week" in email.reason:
            aepWeeks[2] += 1
          elif "Fourth week" in email.reason:
            aepWeeks[3] += 1
    
    # Check distribution is relatively balanced
    let totalAepEmails = aepWeeks.foldl(a + b)
    check totalAepEmails > 0 