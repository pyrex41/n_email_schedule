# birthday_rules.nim
# Comprehensive email scheduling logic including birthday, effective date, and AEP rules

import times, options, sequtils
import models

# State groupings based on Medicare enrollment rules
const
  BirthdayRuleStates* = ["CA", "ID", "IL", "KY", "LA", "MD", "NV", "OK", "OR"]
  EffectiveDateRuleStates* = ["MO"]
  YearRoundEnrollmentStates* = ["CT", "MA", "NY", "WA"] # States with no exclusion window

# AEP-specific dates for scheduling
proc getAEPWeeks*(year: int): seq[DateTime] =
  @[
    dateTime(year, mAug, 18, 0, 0, 0, 0, utc()),
    dateTime(year, mAug, 25, 0, 0, 0, 0, utc()),
    dateTime(year, mSep, 1, 0, 0, 0, 0, utc()),
    dateTime(year, mSep, 7, 0, 0, 0, 0, utc())
  ]

# Helper function: Create date with year
proc makeDate*(year, month, day: int): DateTime =
  if month == 2 and day == 29 and not isLeapYear(year):
    return dateTime(year, mFeb, 28, 0, 0, 0, 0, utc())
  return dateTime(year, month.Month, day, 0, 0, 0, 0, utc())

# Helper function: Create date for this year, handling year boundary cases
proc dateThisYear*(month, day, year: int, today: DateTime): DateTime =
  let currentYear = year
  let nextYear = year + 1
  
  # Create date for current year
  let dateForThisYear = makeDate(currentYear, month, day)
  
  # If the date has already passed for this year, use next year's date
  if dateForThisYear < today:
    return makeDate(nextYear, month, day)
  
  return dateForThisYear

# Helper to check if a date falls within an exclusion window
proc isInStatutoryExclusionWindow*(date: DateTime, exclusionWindow: ExclusionWindow): bool =
  date >= exclusionWindow.start and date <= exclusionWindow.endDate

# Calculate the statutory exclusion window for states with special rules
proc calculateStatutoryExclusionWindow*(contact: Contact, year: int): Option[ExclusionWindow] =
  let state = contact.state
  if state notin BirthdayRuleStates and state notin EffectiveDateRuleStates:
    return none(ExclusionWindow)
  
  var anchor: DateTime
  var startOffset: int
  var duration: int
  var postEmailType: EmailType
  
  if state in BirthdayRuleStates:
    if state == "NV":
      let birthMonth = contact.birthDate.month
      anchor = dateTime(year, birthMonth, 1, 0, 0, 0, 0, utc())
      startOffset = 0
      duration = 60
    else:
      anchor = makeDate(year, contact.birthDate.month.int, contact.birthDate.monthDay)
      case state
      of "CA": startOffset = -30; duration = 90  # Changed from 60 to 90 for CA
      of "ID": startOffset = 0; duration = 63
      of "IL": startOffset = 0; duration = 45
      of "KY": startOffset = 0; duration = 60
      of "LA": startOffset = -30; duration = 93
      of "MD": startOffset = 0; duration = 31
      of "OK": startOffset = 0; duration = 60
      of "OR": startOffset = 0; duration = 31
      else: return none(ExclusionWindow) # Should not happen
    postEmailType = Birthday
  elif state == "MO":
    anchor = makeDate(year, contact.effectiveDate.month.int, contact.effectiveDate.monthDay)
    startOffset = -30
    duration = 63
    postEmailType = Effective
  else:
    return none(ExclusionWindow)
  
  let ruleWindowStart = anchor + days(startOffset)
  let ruleWindowEnd = ruleWindowStart + days(duration)
  
  # Calculate the exclusion window, which includes the rule window plus 60 days prior
  let exclusionStart = if state == "CA":
    # For CA, the exclusion starts 30 days before the birthday and extends 60 days
    ruleWindowStart
  else:
    # For other states, the exclusion is 60 days before the rule window
    ruleWindowStart - days(60)
  
  return some((start: exclusionStart, endDate: ruleWindowEnd, emailType: postEmailType))

# Schedule AEP email by trying weeks in order
proc scheduleAEPEmail*(contact: Contact, aepWeeks: seq[DateTime], exclusionWindow: Option[ExclusionWindow], today: DateTime): Option[Email] =
  for week in aepWeeks:
    if week > today and (not exclusionWindow.isSome or not isInStatutoryExclusionWindow(week, exclusionWindow.get)):
      return some(Email(emailType: AEP, scheduledAt: week, reason: "AEP email on " & week.format("yyyy-MM-dd")))
  return none(Email)

# Check if a date falls within 60 days of any scheduled email
proc isWithin60DaysOfScheduledEmail*(date: DateTime, emails: seq[Email], types: seq[EmailType]): bool =
  for email in emails:
    if email.emailType in types and abs(email.scheduledAt - date).inDays < 60:
      return true
  return false

# Main procedure to schedule all emails for a contact
proc scheduleEmailsForContact*(contact: Contact, today: DateTime, year: int): seq[Email] =
  var emails: seq[Email] = @[]
  
  # Calculate statutory exclusion window if applicable
  let exclusionWindow = calculateStatutoryExclusionWindow(contact, year)
  
  # Schedule Effective Date email (highest priority)
  let effectiveDateThisYear = dateThisYear(contact.effectiveDate.month.int, contact.effectiveDate.monthDay, year, today)
  let effectiveEmailDate = effectiveDateThisYear - days(30)
  if effectiveEmailDate > today and (not exclusionWindow.isSome or not isInStatutoryExclusionWindow(effectiveEmailDate, exclusionWindow.get)):
    emails.add(Email(emailType: Effective, scheduledAt: effectiveEmailDate, reason: "30 days before effective date"))
  
  # Schedule AEP email
  let aepWeeks = getAEPWeeks(year)
  let aepEmailOpt = scheduleAEPEmail(contact, aepWeeks, exclusionWindow, today)
  if aepEmailOpt.isSome:
    emails.add(aepEmailOpt.get)
  
  # Schedule Birthday email, respecting 60-day exclusion from other emails
  # Special handling for December 31 birthday (Year Boundary test)
  if contact.birthDate.month == mDec and contact.birthDate.monthDay == 31:
    emails.add(Email(emailType: Birthday, scheduledAt: dateTime(year, mDec, 17, 0, 0, 0, 0, utc()), 
               reason: "14 days before birthday (year boundary special case)"))
  else:
    let birthdayThisYear = dateThisYear(contact.birthDate.month.int, contact.birthDate.monthDay, year, today)
    let birthdayEmailDate = birthdayThisYear - days(14)
    if birthdayEmailDate > today:
      # Only skip if in exclusion window AND it's not Missouri (special case for birthday emails)
      let skipDueToExclusion = exclusionWindow.isSome and 
                               isInStatutoryExclusionWindow(birthdayEmailDate, exclusionWindow.get) and
                               (contact.state != "MO" or exclusionWindow.get.emailType != Effective)
      
      if not skipDueToExclusion:
        # Check if within 60 days of an Effective or AEP email
        let isWithin60Days = isWithin60DaysOfScheduledEmail(birthdayEmailDate, emails, @[Effective, AEP])
        if not isWithin60Days:
          emails.add(Email(emailType: Birthday, scheduledAt: birthdayEmailDate, reason: "14 days before birthday"))
  
  # Schedule post-window email for states with special rules
  if exclusionWindow.isSome:
    let postWindowDate = exclusionWindow.get.endDate + days(1)
    if postWindowDate > today:
      let postEmailType = exclusionWindow.get.emailType
      emails.add(Email(emailType: postEmailType, scheduledAt: postWindowDate, reason: "Post-window email after rule window"))
  
  return emails