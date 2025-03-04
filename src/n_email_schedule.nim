# Medicare Email Scheduler
# 
# Schedules emails based on Medicare enrollment rules

import asyncdispatch, times, strutils, logging, parseopt
import models, scheduler, database, dotenv

# Forward declare the API module
when defined(withApi):
  import api

type
  AppConfig = object
    isDryRun: bool
    logLevel: Level
    apiMode: bool
    apiPort: int

proc setupLogging(level: Level = lvlInfo) =
  let consoleLogger = newConsoleLogger()
  let fileLogger = newFileLogger("scheduler.log",
      fmtStr = "$datetime $levelname: $message")
  addHandler(consoleLogger)
  addHandler(fileLogger)
  setLogFilter(level)

proc parseCommandLine(): AppConfig =
  var
    p = initOptParser()
    appConfig = AppConfig(
      isDryRun: false,
      logLevel: lvlInfo,
      apiMode: false,
      apiPort: 5000
    )

  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "d", "dry-run":
        appConfig.isDryRun = true
      of "v", "verbose":
        appConfig.logLevel = lvlDebug
      of "q", "quiet":
        appConfig.logLevel = lvlWarn
      of "a", "api":
        appConfig.apiMode = true
      of "p", "port":
        try:
          appConfig.apiPort = parseInt(p.val)
        except:
          appConfig.apiPort = 5000
      of "h", "help":
        echo "Medicare Email Scheduler"
        echo "Usage: n_email_schedule [options]"
        echo "Options:"
        echo "  -d, --dry-run      Run without saving emails to database"
        echo "  -v, --verbose      Enable verbose logging"
        echo "  -q, --quiet        Reduce log output"
        echo "  -a, --api          Run as API server"
        echo "  -p, --port PORT    Specify API server port (default: 5000)"
        echo "  -h, --help         Show this help message"
        quit(0)
      else:
        echo "Unknown option: ", p.key
        quit(1)
    of cmdArgument:
      echo "Unknown argument: ", p.key
      quit(1)

  return appConfig

proc getTestContacts(): seq[Contact] =
  # Create test contacts for dry-run mode or fallback
  result = @[
    Contact(
      id: 1,
      firstName: "John",
      lastName: "Doe",
      email: "john@example.com",
      currentCarrier: "Test Carrier",
      planType: "Medicare",
      effectiveDate: some(now().utc), # Current date
      birthDate: some(now().utc), # Current date (will be adjusted in the try block)
      tobaccoUser: false,
      gender: "M",
      state: "TX",
      zipCode: "12345",
      agentID: 1,
      phoneNumber: some("555-1234"),
      status: some("Active")
    ),
    Contact(
      id: 2,
      firstName: "Jane",
      lastName: "Smith",
      email: "jane@example.com",
      currentCarrier: "Test Carrier",
      planType: "Medicare",
      effectiveDate: some(now().utc), # Current date
      birthDate: some(now().utc), # Current date (will be adjusted in the try block)
      tobaccoUser: false,
      gender: "F",
      state: "OR",
      zipCode: "97123",
      agentID: 2,
      phoneNumber: some("555-5678"),
      status: some("Active")
    ),
    Contact(
      id: 3,
      firstName: "Bob",
      lastName: "Johnson",
      email: "bob@example.com",
      currentCarrier: "Test Carrier",
      planType: "Medicare",
      effectiveDate: some(now().utc), # Current date
      birthDate: some(now().utc), # Current date (will be adjusted in the try block)
      tobaccoUser: false,
      gender: "M",
      state: "CT",
      zipCode: "06001",
      agentID: 3,
      phoneNumber: some("555-9012"),
      status: some("Active")
    )
  ]

  # Set the birthdates to reasonable values (adjust the current date)
  try:
    # Get the current year
    let currentYear = now().utc.year

    # Test contact 1: 70 years old, born on Jan 1
    var bd1 = dateTime(1, mJan, currentYear - 70, 0, 0, 0, zone = utc())
    result[0].birthDate = some(bd1)

    # Test contact 2: 72 years old, born on May 15
    var bd2 = dateTime(15, mMay, currentYear - 72, 0, 0, 0, zone = utc())
    result[1].birthDate = some(bd2)

    # Test contact 3: 68 years old, born on June 10
    var bd3 = dateTime(10, mJun, currentYear - 68, 0, 0, 0, zone = utc())
    result[2].birthDate = some(bd3)

    # Set effective dates 5 years ago
    result[0].effectiveDate = some(dateTime(1, mFeb, currentYear - 5, 0, 0, 0, zone = utc()))
    result[1].effectiveDate = some(dateTime(1, mJun, currentYear - 5, 0, 0, 0, zone = utc()))
    result[2].effectiveDate = some(dateTime(1, mJul, currentYear - 5, 0, 0, 0, zone = utc()))
  except:
    # If there's any error, leave the dates as current date
    debug "Failed to set custom dates for test contacts"

proc showEmailInfo(email: Email, contact: Contact, isDryRun: bool): string =
  # Helper function to format email info message
  var action = if isDryRun: "Would schedule" else: "Scheduled"
  var date = email.scheduledAt.format("yyyy-MM-dd")
  return action & " " & email.emailType & " email for " & contact.email &
      " on " & date

proc runScheduler() {.async.} =
  # Parse command line options
  let config = parseCommandLine()

  # Setup logging
  setupLogging(config.logLevel)

  # Load environment variables from .env file if it exists
  loadEnv()

  info "Starting Medicare Email Scheduler"

  # If API mode is enabled, start the API server
  when defined(withApi):
    if config.apiMode:
      info "Starting API server on port " & $config.apiPort
      try:
        await startApiServer(config.apiPort)
        return
      except Exception as e:
        error "Error starting API server: " & e.msg
        quit(1)

  # Otherwise run in CLI mode
  if config.isDryRun:
    info "Running in dry-run mode (no emails will be saved to database)"

  let
    dbConfig = getConfigFromEnv()
    today = now()

  info "Using database URL: " & dbConfig.baseUrl

  try:
    # Get contacts - from test data or database
    var contacts: seq[Contact]

    if config.isDryRun:
      contacts = getTestContacts()
      info "Using test contacts for dry run"
    else:
      try:
        contacts = await getContacts(dbConfig)
        info "Retrieved " & $contacts.len & " contacts from database"
      except Exception as e:
        error "Failed to connect to database, falling back to test contacts: " & e.msg
        contacts = getTestContacts()

    info "Processing " & $contacts.len & " contacts"

    # Count total emails scheduled
    var totalEmails = 0

    # Process contacts based on size
    if contacts.len > 1:
      # For multiple contacts, try batch processing first
      try:
        # Calculate emails with AEP distribution
        let emailsBatch = calculateBatchScheduledEmails(contacts, today)

        # Process each contact's emails
        for i, emails in emailsBatch:
          if i < contacts.len: # Safety check
            let contact = contacts[i]

            info "Generated " & $emails.len & " emails for " &
                contact.firstName & " " & contact.lastName
            totalEmails += emails.len

            # Save or log the emails
            for email in emails:
              if config.isDryRun:
                info showEmailInfo(email, contact, true)
              elif await saveEmail(dbConfig, email, contact.id):
                info showEmailInfo(email, contact, false)
              else:
                error "Failed to schedule " & email.emailType & " email for " & contact.email
      except Exception as e:
        error "Error in batch processing: " & e.msg

        # Fall back to individual processing
        for contact in contacts:
          try:
            let emails = calculateScheduledEmails(contact, today)

            info "Generated " & $emails.len & " emails for " &
                contact.firstName & " " & contact.lastName
            totalEmails += emails.len

            # Save or log the emails
            for email in emails:
              if config.isDryRun:
                info showEmailInfo(email, contact, true)
              elif await saveEmail(dbConfig, email, contact.id):
                info showEmailInfo(email, contact, false)
              else:
                error "Failed to schedule " & email.emailType & " email for " & contact.email
          except Exception as e:
            error "Error processing contact " & contact.firstName & " " &
                contact.lastName & ": " & e.msg
    else:
      # For a single contact, process normally
      for contact in contacts:
        try:
          let emails = calculateScheduledEmails(contact, today)

          info "Generated " & $emails.len & " emails for " & contact.firstName &
              " " & contact.lastName
          totalEmails += emails.len

          # Save or log the emails
          for email in emails:
            if config.isDryRun:
              info showEmailInfo(email, contact, true)
            elif await saveEmail(dbConfig, email, contact.id):
              info showEmailInfo(email, contact, false)
            else:
              error "Failed to schedule " & email.emailType & " email for " & contact.email
        except Exception as e:
          error "Error processing contact " & contact.firstName & " " &
              contact.lastName & ": " & e.msg

    # Log completion
    info "Email scheduling completed: " & $totalEmails & " emails " &
         (if config.isDryRun: "would be " else: "") & "scheduled"
  except Exception as e:
    let msg = e.msg
    error "Error during email scheduling: " & msg
    # Stacktrace for debug mode
    debug getStackTrace(e)

proc main() =
  waitFor runScheduler()

when isMainModule:
  main()
