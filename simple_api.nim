import asynchttpserver, asyncdispatch, json, times, strutils, sequtils
import src/models, src/scheduler, src/rules

# Helper function to convert emails to JSON
proc emailsToJson(emails: seq[Email]): JsonNode =
  result = newJArray()
  for email in emails:
    result.add(%*{
      "type": email.emailType,
      "status": email.status,
      "scheduledAt": email.scheduledAt.format("yyyy-MM-dd"),
      "reason": email.reason
    })

# Helper function to parse Contact from JSON
proc parseContact(jsonNode: JsonNode): Contact =
  result = Contact(
    id: jsonNode["id"].getInt,
    firstName: jsonNode["firstName"].getStr,
    lastName: jsonNode["lastName"].getStr,
    email: jsonNode["email"].getStr,
    currentCarrier: jsonNode["currentCarrier"].getStr,
    planType: jsonNode["planType"].getStr,
    tobaccoUser: jsonNode["tobaccoUser"].getBool,
    gender: jsonNode["gender"].getStr,
    state: jsonNode["state"].getStr,
    zipCode: jsonNode["zipCode"].getStr,
    agentID: jsonNode["agentID"].getInt,
    phoneNumber: jsonNode.getOrDefault("phoneNumber").getStr(""),
    status: jsonNode.getOrDefault("status").getStr("Active")
  )

  # Parse dates
  try:
    result.effectiveDate = parse(jsonNode["effectiveDate"].getStr, "yyyy-MM-dd", utc())
  except:
    result.effectiveDate = now()

  try:
    result.birthDate = parse(jsonNode["birthDate"].getStr, "yyyy-MM-dd", utc())
  except:
    result.birthDate = now()

proc handler(req: Request): Future[void] {.async.} =
  echo "Received request: ", req.url.path, " method: ", req.reqMethod
  
  let headers = {"Content-Type": "application/json"}
  
  case req.url.path
  of "/health":
    let data = %*{
      "status": "ok",
      "time": $now()
    }
    await req.respond(Http200, $data, headers.newHttpHeaders())
    
  of "/api-info":
    let data = %*{
      "name": "Medicare Email Scheduler API",
      "version": "1.0.0",
      "routes": [
        "/health",
        "/api-info",
        "/schedule-emails",
        "/contacts/{id}/scheduled-emails",
        "/schedule-emails/batch"
      ]
    }
    await req.respond(Http200, $data, headers.newHttpHeaders())
    
  of "/schedule-emails":
    if req.reqMethod == HttpPost:
      try:
        # Parse JSON from request body
        let reqJson = parseJson(req.body)
        let contact = parseContact(reqJson["contact"])
        
        # Parse date or use current date
        var today: DateTime
        try:
          if reqJson.hasKey("today"):
            today = parse(reqJson["today"].getStr, "yyyy-MM-dd", utc())
          else:
            today = now().utc
        except:
          today = now().utc
        
        # Calculate emails
        let emails = calculateScheduledEmails(contact, today)
        
        # Create response
        let response = %*{
          "scheduledEmails": emailsToJson(emails)
        }
        
        await req.respond(Http200, $response, headers.newHttpHeaders())
      except Exception as e:
        let errorResponse = %*{
          "error": "Error processing request: " & e.msg
        }
        await req.respond(Http400, $errorResponse, headers.newHttpHeaders())
    else:
      let errorResponse = %*{
        "error": "Method not allowed",
        "allowedMethods": ["POST"]
      }
      await req.respond(Http405, $errorResponse, headers.newHttpHeaders())
      
  of "/schedule-emails/batch":
    if req.reqMethod == HttpPost:
      try:
        # Parse JSON from request body
        let reqJson = parseJson(req.body)
        
        # Parse contacts array
        var contacts: seq[Contact] = @[]
        for contactJson in reqJson["contacts"]:
          contacts.add(parseContact(contactJson))
          
        # Parse date or use current date
        var today: DateTime
        try:
          if reqJson.hasKey("today"):
            today = parse(reqJson["today"].getStr, "yyyy-MM-dd", utc())
          else:
            today = now().utc
        except:
          today = now().utc
          
        # Calculate batch emails
        let emailsBatch = calculateBatchScheduledEmails(contacts, today)
        
        # Format response
        var results = newJArray()
        for i, emails in emailsBatch:
          results.add(%*{
            "contactId": contacts[i].id,
            "scheduledEmails": emailsToJson(emails)
          })
          
        let response = %*{
          "results": results
        }
        
        await req.respond(Http200, $response, headers.newHttpHeaders())
      except Exception as e:
        let errorResponse = %*{
          "error": "Error processing batch request: " & e.msg
        }
        await req.respond(Http400, $errorResponse, headers.newHttpHeaders())
    else:
      let errorResponse = %*{
        "error": "Method not allowed",
        "allowedMethods": ["POST"]
      }
      await req.respond(Http405, $errorResponse, headers.newHttpHeaders())
      
  else:
    # Check for contact emails path
    if req.url.path.startsWith("/contacts/") and req.url.path.endsWith("/scheduled-emails"):
      let parts = req.url.path.split("/")
      if parts.len == 4:
        try:
          let contactId = parseInt(parts[2])
          
          # Create a mock contact for testing
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
          
          # Calculate scheduled emails
          let emails = calculateScheduledEmails(contact, now().utc)
          
          # Create response
          let response = %*{
            "scheduledEmails": emailsToJson(emails)
          }
          
          await req.respond(Http200, $response, headers.newHttpHeaders())
          return
        except:
          let errorResponse = %*{
            "error": "Invalid contact ID format"
          }
          await req.respond(Http400, $errorResponse, headers.newHttpHeaders())
          return
    
    # Default route not found
    let data = %*{
      "error": "Route not found",
      "path": req.url.path
    }
    await req.respond(Http404, $data, headers.newHttpHeaders())

# Create and start server
let port = 5001
var server = newAsyncHttpServer()
echo "Starting Medicare Email Scheduler API on port ", port
waitFor server.serve(Port(port), handler) 