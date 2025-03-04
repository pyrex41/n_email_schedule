import unittest, times
import ../src/models, ../src/rules, ../src/scheduler

suite "Scheduler Tests":
  setup:
    let 
      today = dateTime(1, mMar, 2025, 0, 0, 0, zone = utc())
      jan1Birthday = Contact(
        id: 1,
        firstName: "John",
        lastName: "Doe",
        email: "john@example.com", 
        currentCarrier: "Test Carrier",
        planType: "Medicare",
        effectiveDate: dateTime(1, mFeb, 2015, 0, 0, 0, zone = utc()),
        birthDate: dateTime(1, mJan, 1950, 0, 0, 0, zone = utc()),
        tobaccoUser: false,
        gender: "M",
        state: "TX",
        zipCode: "12345",
        agentID: 1,
        phoneNumber: "555-1234",
        status: "Active"
      )
      oregonContact = Contact(
        id: 2,
        firstName: "Jane",
        lastName: "Smith", 
        email: "jane@example.com",
        currentCarrier: "Test Carrier",
        planType: "Medicare",
        effectiveDate: dateTime(1, mJun, 2015, 0, 0, 0, zone = utc()),
        birthDate: dateTime(15, mMay, 1950, 0, 0, 0, zone = utc()),
        tobaccoUser: false,
        gender: "F",
        state: "OR",
        zipCode: "97123",
        agentID: 2,
        phoneNumber: "555-5678",
        status: "Active"
      )
      ctContact = Contact(
        id: 3,
        firstName: "Bob",
        lastName: "Johnson",
        email: "bob@example.com",
        currentCarrier: "Test Carrier",
        planType: "Medicare",
        effectiveDate: dateTime(1, mJul, 2015, 0, 0, 0, zone = utc()),
        birthDate: dateTime(10, mJun, 1952, 0, 0, 0, zone = utc()),
        tobaccoUser: false,
        gender: "M",
        state: "CT",
        zipCode: "06001",
        agentID: 3,
        phoneNumber: "555-9012",
        status: "Active"
      )
  
  test "January First Birthday Contact":
    let emails = calculateScheduledEmails(jan1Birthday, today)
    check emails.len == 4  # Birthday, Effective, AEP (1), CarrierUpdate
    
    # Birthday email should be scheduled for Dec 18, 2025 (14 days before)
    let birthdayEmail = emails.filterIt(it.emailType == "Birthday")[0]
    check birthdayEmail.scheduledAt == dateTime(18, mDec, 2025, 0, 0, 0, zone = utc())
    
    # Effective email should be scheduled for Jan 2, 2026 (30 days before)
    let effectiveEmail = emails.filterIt(it.emailType == "Effective")[0]
    check effectiveEmail.scheduledAt == dateTime(2, mJan, 2026, 0, 0, 0, zone = utc())
    
    # AEP email should be scheduled for Aug 15, 2025
    let aepEmail = emails.filterIt(it.emailType == "AEP")[0]
    check aepEmail.scheduledAt == dateTime(15, mAug, 2025, 0, 0, 0, zone = utc())
  
  test "Oregon Contact with Birthday Rule":
    # Oregon has Birthday rule with exclusion window (31 days starting on birthday)
    let emails = calculateScheduledEmails(oregonContact, today)
    
    # Check if we have a post-exclusion window email
    let postExclusionEmails = emails.filterIt(it.reason == "Post exclusion window email")
    check postExclusionEmails.len > 0
    check postExclusionEmails[0].emailType == "Birthday"
  
  test "Year-Round Enrollment State (CT)":
    let emails = calculateScheduledEmails(ctContact, today)
    # No emails should be scheduled for year-round enrollment states
    check emails.len == 0 