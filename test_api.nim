import jester, json, asyncdispatch, times
import src/models, src/scheduler

# Setup routes
routes:
  get "/health":
    resp %*{"status": "ok", "time": $now()}
    
  post "/schedule-emails":
    # Create a mock contact for testing
    let contact = Contact(
      id: 1,
      firstName: "Test",
      lastName: "User",
      email: "test@example.com",
      currentCarrier: "Test Carrier",
      planType: "Medicare",
      effectiveDate: parse("2025-03-15", "yyyy-MM-dd", utc()),
      birthDate: parse("1950-02-01", "yyyy-MM-dd", utc()),
      tobaccoUser: false,
      gender: "M",
      state: "TX",
      zipCode: "12345",
      agentID: 1,
      phoneNumber: "555-1234",
      status: "Active"
    )
    
    # Use current date for calculation
    let today = now().utc
    
    # Calculate scheduled emails
    let emails = calculateScheduledEmails(contact, today)
    
    # Convert emails to JSON
    var emailsJson = newJArray()
    for email in emails:
      emailsJson.add(%*{
        "type": email.emailType,
        "status": email.status,
        "scheduledAt": email.scheduledAt.format("yyyy-MM-dd"),
        "reason": email.reason
      })
    
    # Return response
    resp %*{"scheduledEmails": emailsJson}
    
  get "/contacts/@id/scheduled-emails":
    # Create a mock contact for testing
    let contactId = parseInt(@"id")
    let contact = Contact(
      id: contactId,
      firstName: "Test",
      lastName: "User",
      email: "test@example.com",
      currentCarrier: "Test Carrier",
      planType: "Medicare",
      effectiveDate: parse("2025-03-15", "yyyy-MM-dd", utc()),
      birthDate: parse("1950-02-01", "yyyy-MM-dd", utc()),
      tobaccoUser: false,
      gender: "M",
      state: "TX",
      zipCode: "12345",
      agentID: 1,
      phoneNumber: "555-1234",
      status: "Active"
    )
    
    # Use current date for calculation
    let today = now().utc
    
    # Calculate scheduled emails
    let emails = calculateScheduledEmails(contact, today)
    
    # Convert emails to JSON
    var emailsJson = newJArray()
    for email in emails:
      emailsJson.add(%*{
        "type": email.emailType,
        "status": email.status,
        "scheduledAt": email.scheduledAt.format("yyyy-MM-dd"),
        "reason": email.reason
      })
    
    # Return response
    resp %*{"scheduledEmails": emailsJson}

echo "Starting test API on port 5001..."
let settings = newSettings(port=Port(5001))
runForever() 