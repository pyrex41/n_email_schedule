import unittest, times, options, sequtils
import ../src/models, ../src/rules, ../src/scheduler
import ../src/utils

suite "Scheduler Tests":
  let defaultTestDate = dateTime(2025, mMar, 1, 0, 0, 0, zone = utc())
  
  test "January First Birthday Contact":
    let jan1Birthday = Contact(
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
    
    let emailsResult = calculateScheduledEmails(jan1Birthday, defaultTestDate)
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
    let oregonContact = Contact(
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
    
    let emailsResult = calculateScheduledEmails(oregonContact, defaultTestDate)
    check emailsResult.isOk
    let emails = emailsResult.value
    
    # Oregon has a birthday rule, should have at least one email
    check emails.len > 0
  
  test "Year-Round Enrollment State (CT)":
    let ctContact = Contact(
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
    
    let emailsResult = calculateScheduledEmails(ctContact, defaultTestDate)
    check emailsResult.isOk
    let emails = emailsResult.value
    # No emails should be scheduled for year-round enrollment states
    check emails.len == 0
    
  suite "Test standard case email overlaps":
    test "Overlapping emails for standard case - birthday first":
      # Create a contact where birthday email (Apr 15) comes before effective email (May 15)
      # Birthday = Apr 29 -> Email on Apr 15 (14 days before)
      # Effective = Jun 14 -> Email on May 15 (30 days before) 
      # These are 30 days apart, should trigger the overlap handling
      let overlappingContact = Contact(
          id: 101,
          firstName: "Overlap",
          lastName: "Test1",
          email: "overlap1@example.com",
          currentCarrier: "Test Carrier",
          planType: "Medicare",
          state: "XX",  # Non-existent state to trigger standard case
          birthDate: some(dateTime(1980, mApr, 29, 0, 0, 0, zone = utc())),
          effectiveDate: some(dateTime(2022, mJun, 14, 0, 0, 0, zone = utc())),
          tobaccoUser: false,
          gender: "M",
          zipCode: "12345",
          agentID: 101
        )
      
      let emailsResult = calculateScheduledEmails(overlappingContact, defaultTestDate)
      check emailsResult.isOk
      let emails = emailsResult.value
      
      # Should only have birthday email (plus possibly carrier update)
      let birthdayEmails = emails.filterIt(it.emailType == "Birthday")
      let effectiveEmails = emails.filterIt(it.emailType == "Effective")
      
      check(birthdayEmails.len == 1)
      check(effectiveEmails.len == 0)
    
    test "Overlapping emails for standard case - effective first":
      # Create a contact where effective date email comes before birthday email
      # Effective = Apr 15 -> Email on Mar 16 (30 days before)
      # Birthday = May 5 -> Email on Apr 21 (14 days before)
      # These are less than 30 days apart, should trigger overlap handling
      let overlappingContact = Contact(
        id: 102,
        firstName: "Overlap",
        lastName: "EffectiveFirst",
        email: "overlap2@example.com",
        currentCarrier: "Test Carrier",
        planType: "Medicare",
        state: "XX",  # Non-existent state to trigger standard case
        effectiveDate: some(dateTime(2015, mApr, 15, 0, 0, 0, zone = utc())),
        birthDate: some(dateTime(1950, mMay, 5, 0, 0, 0, zone = utc())),
        tobaccoUser: false,
        gender: "M",
        zipCode: "12345",
        agentID: 1,
        phoneNumber: some("555-1234"),
        status: some("Active")
      )
      
      echo "DEBUG: Test case 'Overlapping emails - effective first'"
      echo "DEBUG: Contact details:"
      echo "DEBUG:   - ID: ", overlappingContact.id
      echo "DEBUG:   - Birth date: ", overlappingContact.birthDate.get().format("yyyy-MM-dd")
      echo "DEBUG:   - Effective date: ", overlappingContact.effectiveDate.get().format("yyyy-MM-dd")
      echo "DEBUG:   - State: ", overlappingContact.state
      echo "DEBUG: Today's date for test: ", defaultTestDate.format("yyyy-MM-dd")
      
      let emailsResult = calculateScheduledEmails(overlappingContact, defaultTestDate)
      echo "DEBUG: Email calculation result isOk: ", emailsResult.isOk
      
      check emailsResult.isOk
      let emails = emailsResult.value
      
      # Log all emails for debugging
      echo "Test case 'Overlapping emails - effective first': Found " & $emails.len & " emails"
      for i, email in emails:
        echo "   Email " & $i & ": type=" & email.emailType & 
            ", date=" & email.scheduledAt.format("yyyy-MM-dd") & 
            ", reason=" & email.reason
      
      # Should only have effective email (plus possibly AEP and CarrierUpdate)
      let birthdayEmails = emails.filterIt(it.emailType == "Birthday")
      let effectiveEmails = emails.filterIt(it.emailType == "Effective")
      
      echo "DEBUG: Birthday emails count: ", birthdayEmails.len
      echo "DEBUG: Effective emails count: ", effectiveEmails.len
      
      check(birthdayEmails.len == 0)
      check(effectiveEmails.len == 1)
      
    test "Non-overlapping emails for standard case":
      # Create a contact where emails are far apart (more than 30 days)
      # Birthday = Apr 19 -> Email on Apr 5 (14 days before)
      # Effective = Jul 15 -> Email on Jun 15 (30 days before)
      # These are more than 30 days apart, should not trigger overlap handling
      let nonOverlappingContact = Contact(
        id: 103,
        firstName: "NonOverlap",
        lastName: "Test",
        email: "nonoverlap@example.com",
        currentCarrier: "Test Carrier",
        planType: "Medicare",
        state: "XX",  # Non-existent state to trigger standard case
        birthDate: some(dateTime(1980, mApr, 19, 0, 0, 0, zone = utc())),
        effectiveDate: some(dateTime(2022, mJul, 15, 0, 0, 0, zone = utc())),
        tobaccoUser: false,
        gender: "M",
        zipCode: "12345",
        agentID: 103
      )
      
      let emailsResult = calculateScheduledEmails(nonOverlappingContact, defaultTestDate)
      check emailsResult.isOk
      let emails = emailsResult.value
      
      # Should have both emails
      let birthdayEmails = emails.filterIt(it.emailType == "Birthday")
      let effectiveEmails = emails.filterIt(it.emailType == "Effective")
      
      check(birthdayEmails.len == 1)
      check(effectiveEmails.len == 1)