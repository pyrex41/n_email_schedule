import unittest, times, strutils, strformat, sequtils
import src/models, src/scheduler, src/rules

# Reference date for all tests
let today = parse("2025-01-01", "yyyy-MM-dd", utc())
echo "Testing with today = ", today.format("yyyy-MM-dd")

# We need our own version of getYearlyDate since it's private in scheduler.nim
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

# Check if a date is in the exclusion window
proc isInExclusionWindow(date: DateTime, eewStart, eewEnd: DateTime): bool =
  date >= eewStart and date < eewEnd

# Helper function to debug email scheduling
proc debugContactEmails(name: string, contact: Contact) =
  echo "\n----- Testing ", name, " -----"
  echo "State: ", contact.state
  echo "Birth date: ", contact.birthDate.format("yyyy-MM-dd")
  echo "Effective date: ", contact.effectiveDate.format("yyyy-MM-dd")
  
  # Print state rule information
  let stateRule = getStateRule(contact.state)
  let (startOffset, duration) = getRuleParams(contact.state)
  echo "State rule: ", stateRule
  echo "Rule params: startOffset=", startOffset, ", duration=", duration
  
  # Calculate expected dates
  echo "\nExpected scheduling:"
  try:
    # Calculate the yearly dates
    let 
      birthYearlyDate = getYearlyDate(contact.birthDate, today.year)
      effectiveYearlyDate = getYearlyDate(contact.effectiveDate, today.year)
      
    echo "Birth date in current year: ", birthYearlyDate.format("yyyy-MM-dd")
    echo "Effective date in current year: ", effectiveYearlyDate.format("yyyy-MM-dd")
    
    # Calculate expected email dates
    let
      expectedBirthdayEmail = birthYearlyDate - 14.days
      expectedEffectiveEmail = effectiveYearlyDate - 30.days
      expectedAepEmail = parse(fmt"{today.year:04d}-08-18", "yyyy-MM-dd", utc())
      
    echo "Expected birthday email: ", expectedBirthdayEmail.format("yyyy-MM-dd")
    echo "Expected effective email: ", expectedEffectiveEmail.format("yyyy-MM-dd")
    echo "Expected AEP email: ", expectedAepEmail.format("yyyy-MM-dd")
    
    # Calculate exclusion window
    let refDate = if stateRule == Birthday: contact.birthDate else: contact.effectiveDate
    let ruleStart = getYearlyDate(refDate, today.year) + startOffset.days
    let ruleEnd = ruleStart + duration.days
    let eewStart = ruleStart - 60.days
    let eewEnd = ruleEnd
    
    echo "\nExclusion window:"
    echo "Rule start: ", ruleStart.format("yyyy-MM-dd")
    echo "Rule end: ", ruleEnd.format("yyyy-MM-dd") 
    echo "Window: ", eewStart.format("yyyy-MM-dd"), " to ", eewEnd.format("yyyy-MM-dd")
    
    # Check if emails are in exclusion window
    echo "Birthday email in window? ", isInExclusionWindow(expectedBirthdayEmail, eewStart, eewEnd)
    echo "Effective email in window? ", isInExclusionWindow(expectedEffectiveEmail, eewStart, eewEnd)
    echo "AEP email in window? ", isInExclusionWindow(expectedAepEmail, eewStart, eewEnd)
  except Exception as e:
    echo "Error in date calculations: ", e.msg
    
  # Actually run the scheduler
  echo "\nActual scheduled emails:"
  try:
    let emails = calculateScheduledEmails(contact, today)
    echo "Number of emails: ", emails.len
    
    for i, email in emails:
      echo email.emailType, " email scheduled for ", email.scheduledAt.format("yyyy-MM-dd")
      
    # Check specifically for each type
    let
      birthdayEmails = emails.filterIt(it.emailType == $EmailType.Birthday)
      effectiveEmails = emails.filterIt(it.emailType == $EmailType.Effective)
      aepEmails = emails.filterIt(it.emailType == $EmailType.AEP)
      
    echo "\nSummary:"
    echo "Birthday emails: ", birthdayEmails.len
    echo "Effective date emails: ", effectiveEmails.len
    echo "AEP emails: ", aepEmails.len
  except Exception as e:
    echo "Error in scheduler: ", e.msg
    
  echo "------------------------\n"

# Test 1: Basic Birthday Email (Texas)
let txContact = Contact(
  id: 1,
  firstName: "Texas",
  lastName: "User",
  email: "tx@example.com", 
  currentCarrier: "Test Carrier",
  planType: "Medicare",
  effectiveDate: parse("2025-12-15", "yyyy-MM-dd", utc()),  # Far future to avoid exclusion window
  birthDate: parse("1950-02-01", "yyyy-MM-dd", utc()),
  state: "TX"
)
debugContactEmails("Texas Contact (Birthday)", txContact)

# Test 2: Oregon (Birthday Rule State)
let orContact = Contact(
  id: 2,
  firstName: "Oregon",
  lastName: "User",
  email: "or@example.com", 
  currentCarrier: "Test Carrier",
  planType: "Medicare",
  effectiveDate: parse("2025-12-15", "yyyy-MM-dd", utc()),  # Far future to avoid exclusion window
  birthDate: parse("1955-09-15", "yyyy-MM-dd", utc()),      # September 15 (further away from Jan-Apr)
  state: "OR"
)
debugContactEmails("Oregon Contact (Birthday Rule)", orContact)

# Test 3: Missouri (Effective Date Rule State)
let moContact = Contact(
  id: 3,
  firstName: "Missouri",
  lastName: "User",
  email: "mo@example.com", 
  currentCarrier: "Test Carrier",
  planType: "Medicare",
  effectiveDate: parse("2025-12-15", "yyyy-MM-dd", utc()),
  birthDate: parse("1960-05-01", "yyyy-MM-dd", utc()),
  state: "MO"
)
debugContactEmails("Missouri Contact (Effective Date Rule)", moContact)

# Test 4: Connecticut (Year Round Enrollment)
let ctContact = Contact(
  id: 4,
  firstName: "Connecticut",
  lastName: "User",
  email: "ct@example.com", 
  currentCarrier: "Test Carrier",
  planType: "Medicare",
  effectiveDate: parse("2025-04-01", "yyyy-MM-dd", utc()),
  birthDate: parse("1965-06-15", "yyyy-MM-dd", utc()),
  state: "CT"
)
debugContactEmails("Connecticut Contact (Year Round)", ctContact) 