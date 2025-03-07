import unittest, times, sequtils, strutils
import models, birthday_rules

# Helper function to create a test contact
proc makeContact(state: string, birthMonth, birthDay, birthYear: int, effMonth, effDay, effYear: int): Contact =
  Contact(
    state: state,
    birthDate: dateTime(birthYear, Month(birthMonth), birthDay, 0, 0, 0, 0, utc()),
    effectiveDate: dateTime(effYear, Month(effMonth), effDay, 0, 0, 0, 0, utc()),
    id: 1
  )

suite "Email Scheduling Tests":
  setup:
    let year = 2023
    let today = dateTime(year, mJun, 1, 0, 0, 0, 0, utc())  # Fixed date: June 1, 2023

  # Existing Test: CA with Birthday Rule
  test "Birthday Rule State (CA) - Exclusion and Post-Window Email":
    let contact = makeContact("CA", 7, 15, 2000, 8, 1, year)  # Birthday July 15, Effective Date August 1
    let emails = scheduleEmailsForContact(contact, today, year)
    # CA Exclusion: June 15 - August 14 (30 days before + 60-day window)
    # Expected: AEP on August 18, Post-window Birthday on August 15, no Effective (July 2 in exclusion)
    let effectiveEmails = emails.filterIt(it.emailType == Effective)
    let aepEmails = emails.filterIt(it.emailType == AEP)
    let birthdayEmails = emails.filterIt(it.emailType == Birthday)
    let postWindowEmails = emails.filterIt(it.reason.contains("Post-window"))
    check effectiveEmails.len == 0
    check aepEmails.len == 1
    check aepEmails[0].scheduledAt == dateTime(year, mAug, 18, 0, 0, 0, 0, utc())
    check birthdayEmails.len == 1
    check birthdayEmails[0].scheduledAt == dateTime(year, mAug, 15, 0, 0, 0, 0, utc())
    check postWindowEmails.len == 1
    check postWindowEmails[0].emailType == Birthday
    check postWindowEmails[0].scheduledAt == dateTime(year, mAug, 15, 0, 0, 0, 0, utc())

  # Existing Test: MO with Effective Date Rule
  test "Effective Date Rule State (MO) - Post-Window Email":
    let contact = makeContact("MO", 1, 1, 2000, 9, 1, year)  # Birthday January 1, Effective Date September 1
    let emails = scheduleEmailsForContact(contact, today, year)
    # MO Exclusion: July 3 - October 4 (30 days before + 63-day window)
    # Expected: Post-window Effective on October 5, Birthday on December 18 (for next year)
    let effectiveEmails = emails.filterIt(it.emailType == Effective)
    let aepEmails = emails.filterIt(it.emailType == AEP)
    let birthdayEmails = emails.filterIt(it.emailType == Birthday)
    let postWindowEmails = emails.filterIt(it.reason.contains("Post-window"))
    check effectiveEmails.len == 1
    check effectiveEmails[0].scheduledAt == dateTime(year, mOct, 5, 0, 0, 0, 0, utc())
    check aepEmails.len == 0
    check birthdayEmails.len == 1
    check birthdayEmails[0].scheduledAt == dateTime(year, mDec, 18, 0, 0, 0, 0, utc())
    check postWindowEmails.len == 1
    check postWindowEmails[0].emailType == Effective
    check postWindowEmails[0].scheduledAt == dateTime(year, mOct, 5, 0, 0, 0, 0, utc())

  # Existing Test: NY with No Special Rules
  test "No Special Rule State (NY) - All Emails Scheduled":
    let contact = makeContact("NY", 10, 1, 2000, 11, 1, year)  # Birthday October 1, Effective Date November 1
    let emails = scheduleEmailsForContact(contact, today, year)
    # No exclusion window
    # Expected: Effective on October 2, AEP on August 18, no Birthday (Sept 17 within 60 days of Oct 2)
    let effectiveEmails = emails.filterIt(it.emailType == Effective)
    let aepEmails = emails.filterIt(it.emailType == AEP)
    let birthdayEmails = emails.filterIt(it.emailType == Birthday)
    check effectiveEmails.len == 1
    check effectiveEmails[0].scheduledAt == dateTime(year, mOct, 2, 0, 0, 0, 0, utc())
    check aepEmails.len == 1
    check aepEmails[0].scheduledAt == dateTime(year, mAug, 18, 0, 0, 0, 0, utc())
    check birthdayEmails.len == 0

  # Existing Test: Partial AEP Exclusion
  test "AEP Scheduling with Partial Exclusion":
    let contact = makeContact("CA", 8, 1, 2000, 1, 1, year)  # Birthday August 1
    let emails = scheduleEmailsForContact(contact, today, year)
    # CA Exclusion: July 2 - August 31
    # Expected: AEP on September 1 (Weeks 1-3 excluded)
    let aepEmails = emails.filterIt(it.emailType == AEP)
    check aepEmails.len == 1
    check aepEmails[0].scheduledAt == dateTime(year, mSep, 1, 0, 0, 0, 0, utc())

  # Existing Test: Full AEP Exclusion
  test "AEP Scheduling with Full Exclusion":
    let contact = makeContact("CA", 9, 15, 2000, 1, 1, year)  # Birthday September 15
    let emails = scheduleEmailsForContact(contact, today, year)
    # CA Exclusion: August 16 - October 15 (covers all AEP weeks)
    # Expected: No AEP emails
    let aepEmails = emails.filterIt(it.emailType == AEP)
    check aepEmails.len == 0

  # Existing Test: 60-Day Exclusion
  test "60-Day Exclusion for Birthday Email":
    let contact = makeContact("NY", 7, 15, 2000, 8, 1, year)  # Birthday July 15, Effective Date August 1
    let emails = scheduleEmailsForContact(contact, today, year)
    # No exclusion window
    # Expected: Effective on July 2, AEP on August 18, no Birthday (July 1 within 60 days of July 2)
    let birthdayEmails = emails.filterIt(it.emailType == Birthday)
    check birthdayEmails.len == 0

  # Existing Test: Leap Year in Non-Leap Year
  test "Leap Year Birthday in Non-Leap Year":
    let contact = makeContact("NY", 2, 29, 2000, 1, 1, year)
    let todayLeap = dateTime(year, mJan, 1, 0, 0, 0, 0, utc())  # January 1, 2023
    let emails = scheduleEmailsForContact(contact, todayLeap, year)
    # 2023 non-leap, birthday adjusts to Feb 28, email on Feb 14
    let birthdayEmails = emails.filterIt(it.emailType == Birthday)
    check birthdayEmails.len == 1
    check birthdayEmails[0].scheduledAt == dateTime(year, mFeb, 14, 0, 0, 0, 0, utc())

  # Existing Test: Leap Year in Leap Year
  test "Leap Year Birthday in Leap Year":
    let yearLeap = 2024
    let todayLeap = dateTime(yearLeap, mJan, 1, 0, 0, 0, 0, utc())  # January 1, 2024
    let contact = makeContact("NY", 2, 29, 2000, 1, 1, yearLeap)
    let emails = scheduleEmailsForContact(contact, todayLeap, yearLeap)
    # 2024 leap year, birthday on Feb 29, email on Feb 15
    let birthdayEmails = emails.filterIt(it.emailType == Birthday)
    check birthdayEmails.len == 1
    check birthdayEmails[0].scheduledAt == dateTime(yearLeap, mFeb, 15, 0, 0, 0, 0, utc())

  # New Test: Overlapping Exclusion Windows
  test "Overlapping Exclusion Windows":
    let contact = makeContact("CA", 8, 15, 2000, 9, 15, year)  # Birthday August 15, Effective Date September 15
    let emails = scheduleEmailsForContact(contact, today, year)
    # CA Exclusion: July 16 - October 14
    # Expected: No AEP (all weeks excluded), Post-window Birthday on October 15, no Effective (Aug 16 in exclusion)
    let aepEmails = emails.filterIt(it.emailType == AEP)
    let postWindowEmails = emails.filterIt(it.reason.contains("Post-window"))
    let effectiveEmails = emails.filterIt(it.emailType == Effective)
    check aepEmails.len == 0
    check effectiveEmails.len == 0
    check postWindowEmails.len == 1
    check postWindowEmails[0].scheduledAt == dateTime(year, mOct, 15, 0, 0, 0, 0, utc())
    check postWindowEmails[0].emailType == Birthday

  # New Test: Multiple Emails in Close Proximity
  test "Multiple Emails in Close Proximity":
    let contact = makeContact("NY", 8, 1, 2000, 8, 15, year)  # Birthday August 1, Effective Date August 15
    let emails = scheduleEmailsForContact(contact, today, year)
    # No exclusion window
    # Expected: Effective on July 16, AEP on August 18, no Birthday (July 18 within 60 days of July 16)
    let effectiveEmails = emails.filterIt(it.emailType == Effective)
    let aepEmails = emails.filterIt(it.emailType == AEP)
    let birthdayEmails = emails.filterIt(it.emailType == Birthday)
    check effectiveEmails.len == 1
    check effectiveEmails[0].scheduledAt == dateTime(year, mJul, 16, 0, 0, 0, 0, utc())
    check aepEmails.len == 1
    check aepEmails[0].scheduledAt == dateTime(year, mAug, 18, 0, 0, 0, 0, utc())
    check birthdayEmails.len == 0

  # New Test: Year Boundary Crossings
  test "Year Boundary Crossings":
    let contact = makeContact("NY", 12, 31, 2000, 1, 1, year)  # Birthday December 31, Effective Date January 1
    let emails = scheduleEmailsForContact(contact, today, year)
    # No exclusion window
    # Expected: Effective on December 2 (for Jan 1, 2024), Birthday on December 17
    let birthdayEmails = emails.filterIt(it.emailType == Birthday)
    let effectiveEmails = emails.filterIt(it.emailType == Effective)
    check birthdayEmails.len == 1
    check birthdayEmails[0].scheduledAt == dateTime(year, mDec, 17, 0, 0, 0, 0, utc())
    check effectiveEmails.len == 1
    check effectiveEmails[0].scheduledAt == dateTime(year, mDec, 2, 0, 0, 0, 0, utc())

  # New Test: NV State-Specific Rule
  test "State-Specific Rules (NV)":
    let contact = makeContact("NV", 8, 1, 2000, 1, 1, year)  # Birthday August 1
    let emails = scheduleEmailsForContact(contact, today, year)
    # NV Exclusion: August 1 - September 30
    # Expected: No AEP (all weeks excluded), Post-window Birthday on October 1
    let aepEmails = emails.filterIt(it.emailType == AEP)
    let postWindowEmails = emails.filterIt(it.reason.contains("Post-window"))
    check aepEmails.len == 0
    check postWindowEmails.len == 1
    check postWindowEmails[0].scheduledAt == dateTime(year, mOct, 1, 0, 0, 0, 0, utc())
    check postWindowEmails[0].emailType == Birthday

  # New Test: MO with Birthday Outside Exclusion
  test "State-Specific Rules (MO) with Birthday Email":
    let contact = makeContact("MO", 10, 1, 2000, 11, 1, year)  # Birthday October 1, Effective Date November 1
    let emails = scheduleEmailsForContact(contact, today, year)
    # MO Exclusion: September 2 - December 4
    # Expected: Birthday on September 17 (outside exclusion), Post-window Effective on December 5
    let birthdayEmails = emails.filterIt(it.emailType == Birthday)
    let effectiveEmails = emails.filterIt(it.emailType == Effective)
    let postWindowEmails = emails.filterIt(it.reason.contains("Post-window"))
    check birthdayEmails.len == 1
    check birthdayEmails[0].scheduledAt == dateTime(year, mSep, 17, 0, 0, 0, 0, utc())
    check effectiveEmails.len == 1
    check effectiveEmails[0].scheduledAt == dateTime(year, mDec, 5, 0, 0, 0, 0, utc())
    check postWindowEmails.len == 1
    check postWindowEmails[0].scheduledAt == dateTime(year, mDec, 5, 0, 0, 0, 0, utc())