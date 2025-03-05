import unittest, times, options, sequtils
import ../src/models, ../src/rules, ../src/scheduler
import ../src/utils

suite "Scheduler Tests":
  setup:
    let 
      today = dateTime(2025, mMar, 1, 0, 0, 0, zone = utc())
      jan1Birthday = Contact(
        id: 1,
        firstName: "John",
        lastName: "Doe",
        email: "john@example.com", 
        currentCarrier: "Test Carrier",
        planType: "Medicare",
        effectiveDate: some(dateTime(2015, mFeb, 1, 0, 0, 0, zone = utc())),
        birthDate: some(dateTime(1950, mJan, 1, 0, 0, 0, zone = utc())),
        tobaccoUser: false,
        gender: "M",
        state: "TX",
        zipCode: "12345",
        agentID: 1,
        phoneNumber: some("555-1234"),
        status: some("Active")
      )
      oregonContact = Contact(
        id: 2,
        firstName: "Jane",
        lastName: "Smith", 
        email: "jane@example.com",
        currentCarrier: "Test Carrier",
        planType: "Medicare",
        effectiveDate: some(dateTime(2015, mJun, 1, 0, 0, 0, zone = utc())),
        birthDate: some(dateTime(1950, mMay, 15, 0, 0, 0, zone = utc())),
        tobaccoUser: false,
        gender: "F",
        state: "OR",
        zipCode: "97123",
        agentID: 2,
        phoneNumber: some("555-5678"),
        status: some("Active")
      )
      ctContact = Contact(
        id: 3,
        firstName: "Bob",
        lastName: "Johnson",
        email: "bob@example.com",
        currentCarrier: "Test Carrier",
        planType: "Medicare",
        effectiveDate: some(dateTime(2015, mJul, 1, 0, 0, 0, zone = utc())),
        birthDate: some(dateTime(1952, mJun, 10, 0, 0, 0, zone = utc())),
        tobaccoUser: false,
        gender: "M",
        state: "CT",
        zipCode: "06001",
        agentID: 3,
        phoneNumber: some("555-9012"),
        status: some("Active")
      )
  
  test "January First Birthday Contact":
    let emailsResult = calculateScheduledEmails(jan1Birthday, today)
    check emailsResult.isOk
    let emails = emailsResult.value
    check emails.len == 4  # Birthday, Effective, AEP (1), CarrierUpdate
    
    # Birthday email should be scheduled for Dec 18, 2025 (14 days before)
    let birthdayEmail = emails.filterIt(it.emailType == "Birthday")[0]
    check birthdayEmail.scheduledAt == dateTime(2025, mDec, 18, 0, 0, 0, zone = utc())
    
    # Effective email should be scheduled for Jan 2, 2026 (30 days before)
    let effectiveEmail = emails.filterIt(it.emailType == "Effective")[0]
    check effectiveEmail.scheduledAt == dateTime(2026, mJan, 2, 0, 0, 0, zone = utc())
    
    # AEP email should be scheduled for Aug 15, 2025
    let aepEmail = emails.filterIt(it.emailType == "AEP")[0]
    check aepEmail.scheduledAt == dateTime(2025, mAug, 15, 0, 0, 0, zone = utc())
  
  test "Oregon Contact with Birthday Rule":
    # Oregon has Birthday rule with exclusion window (31 days starting on birthday)
    let emailsResult = calculateScheduledEmails(oregonContact, today)
    check emailsResult.isOk
    let emails = emailsResult.value
    
    # Check if we have a post-exclusion window email
    let postExclusionEmails = emails.filterIt(it.reason == "Post exclusion window email")
    check postExclusionEmails.len > 0
    check postExclusionEmails[0].emailType == "Birthday"
  
  test "Year-Round Enrollment State (CT)":
    let emailsResult = calculateScheduledEmails(ctContact, today)
    check emailsResult.isOk
    let emails = emailsResult.value
    # No emails should be scheduled for year-round enrollment states
    check emails.len == 0 