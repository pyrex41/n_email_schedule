import asyncdispatch, times, strutils, sequtils, logging, os, tables
import jester
import json
import models, scheduler, database, dotenv, utils

# Set up logging
var consoleLogger = newConsoleLogger(fmtStr="[$time] - $levelname: ")
addHandler(consoleLogger)

# Forward declaration for Jester (will be imported dynamically)
type Jester = object
proc resp(data: JsonNode) {.importc.}
proc resp(status: int, data: JsonNode) {.importc.}

# Forward declaration for Jester callbacks
type CallbackAction = enum
  TCActionSend, # Send the data and headers as provided
  TCActionPass, # Pass to the next matching route
  TCActionRaw   # Send the raw body data with the headers

# Helper functions for JSON conversion
proc toJson*(email: Email): JsonNode =
  result = %*{
    "type": email.emailType,
    "status": email.status,
    "scheduledAt": email.scheduledAt.format("yyyy-MM-dd"),
    "reason": email.reason
  }

proc emailsToJson(emails: seq[Email]): JsonNode =
  result = newJArray()
  for email in emails:
    result.add(toJson(email))

# Swagger JSON definition
const swaggerJson = """
{
  "openapi": "3.0.0",
  "info": {
    "title": "Medicare Email Scheduler API",
    "description": "API for scheduling Medicare enrollment emails",
    "version": "1.0.0"
  },
  "servers": [
    {
      "url": "http://localhost:5000",
      "description": "Local server"
    }
  ],
  "paths": {
    "/schedule-emails": {
      "post": {
        "summary": "Schedule emails for a contact",
        "description": "Calculate scheduled emails for a single contact",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "contact": {
                    "$ref": "#/components/schemas/Contact"
                  },
                  "today": {
                    "type": "string",
                    "format": "date",
                    "example": "2025-01-15"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful operation",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "scheduledEmails": {
                      "type": "array",
                      "items": {
                        "$ref": "#/components/schemas/Email"
                      }
                    }
                  }
                }
              }
            }
          },
          "400": {
            "description": "Invalid input"
          },
          "500": {
            "description": "Server error"
          }
        }
      }
    },
    "/contacts/{contactId}/scheduled-emails": {
      "get": {
        "summary": "Get scheduled emails by contact ID",
        "description": "Retrieve scheduled emails for a contact by ID",
        "parameters": [
          {
            "name": "contactId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "integer"
            },
            "description": "ID of the contact"
          },
          {
            "name": "today",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string",
              "format": "date"
            },
            "description": "Reference date for calculations (defaults to today)"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful operation",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "scheduledEmails": {
                      "type": "array",
                      "items": {
                        "$ref": "#/components/schemas/Email"
                      }
                    }
                  }
                }
              }
            }
          },
          "404": {
            "description": "Contact not found"
          },
          "500": {
            "description": "Server error"
          }
        }
      }
    },
    "/schedule-emails/batch": {
      "post": {
        "summary": "Schedule emails for multiple contacts",
        "description": "Calculate scheduled emails for multiple contacts with AEP distribution",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "contacts": {
                    "type": "array",
                    "items": {
                      "$ref": "#/components/schemas/Contact"
                    }
                  },
                  "today": {
                    "type": "string",
                    "format": "date",
                    "example": "2025-01-15"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful operation",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "results": {
                      "type": "array",
                      "items": {
                        "type": "object",
                        "properties": {
                          "contactId": {
                            "type": "integer"
                          },
                          "scheduledEmails": {
                            "type": "array",
                            "items": {
                              "$ref": "#/components/schemas/Email"
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          },
          "400": {
            "description": "Invalid input"
          },
          "500": {
            "description": "Server error"
          }
        }
      }
    },
    "/api-docs": {
      "get": {
        "summary": "API Documentation",
        "description": "OpenAPI specification",
        "responses": {
          "200": {
            "description": "Successful operation",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object"
                }
              }
            }
          }
        }
      }
    },
    "/docs": {
      "get": {
        "summary": "API Documentation UI",
        "description": "Swagger UI for interactive API documentation",
        "responses": {
          "200": {
            "description": "Successful operation",
            "content": {
              "text/html": {
                "schema": {
                  "type": "string"
                }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "Contact": {
        "type": "object",
        "properties": {
          "id": {
            "type": "integer"
          },
          "firstName": {
            "type": "string"
          },
          "lastName": {
            "type": "string"
          },
          "email": {
            "type": "string"
          },
          "currentCarrier": {
            "type": "string"
          },
          "planType": {
            "type": "string"
          },
          "effectiveDate": {
            "type": "string",
            "format": "date"
          },
          "birthDate": {
            "type": "string",
            "format": "date"
          },
          "tobaccoUser": {
            "type": "boolean"
          },
          "gender": {
            "type": "string"
          },
          "state": {
            "type": "string"
          },
          "zipCode": {
            "type": "string"
          },
          "agentID": {
            "type": "integer"
          },
          "phoneNumber": {
            "type": "string"
          },
          "status": {
            "type": "string"
          }
        }
      },
      "Email": {
        "type": "object",
        "properties": {
          "type": {
            "type": "string",
            "enum": ["Birthday", "Effective", "AEP", "CarrierUpdate"]
          },
          "status": {
            "type": "string",
            "enum": ["Pending", "Sent", "Failed"]
          },
          "scheduledAt": {
            "type": "string",
            "format": "date"
          },
          "reason": {
            "type": "string"
          }
        }
      }
    }
  }
}
"""

# Swagger UI HTML template
const swaggerUiHtml = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Medicare Email Scheduler API Documentation</title>
  <link rel="stylesheet" type="text/css" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.9.0/swagger-ui.css">
  <style>
    html { box-sizing: border-box; overflow: -moz-scrollbars-vertical; overflow-y: scroll; }
    *, *:before, *:after { box-sizing: inherit; }
    body { margin: 0; background: #fafafa; }
    .topbar { display: none; }
  </style>
</head>
<body>
  <div id="swagger-ui"></div>

  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.9.0/swagger-ui-bundle.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.9.0/swagger-ui-standalone-preset.js"></script>
  <script>
    window.onload = function() {
      const ui = SwaggerUIBundle({
        url: "/api-docs",
        dom_id: '#swagger-ui',
        deepLinking: true,
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIStandalonePreset
        ],
        layout: "StandaloneLayout"
      });
    };
  </script>
</body>
</html>
"""

# Utility functions for API responses
proc successResponse(data: JsonNode): ResponseData =
  return (TCActionSend, HttpCode(200), {"Content-Type": "application/json"}.newHttpHeaders(), $data, true)

proc errorResponse(status: HttpCode, message: string): ResponseData =
  return (TCActionSend, status, {"Content-Type": "application/json"}.newHttpHeaders(), $(%*{
      "error": message}), true)

# Handle API requests
proc handleScheduleEmails(request: Request, dbConfig: DbConfig): Future[
    ResponseData] {.async.} =
  try:
    let reqJson = parseJson(request.body)
    let contact = toContact(reqJson["contact"])

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

    # Return response
    return successResponse(%*{"scheduledEmails": emailsToJson(emails)})
  except Exception as e:
    error "Error scheduling emails: " & e.msg
    return errorResponse(Http500, e.msg)

proc handleGetContactEmails(request: Request, params: Table[string, string],
    dbConfig: DbConfig): Future[ResponseData] {.async.} =
  try:
    let contactId = parseInt(params["contactId"])

    # Get date parameter or use today
    var today: DateTime
    try:
      if request.params.hasKey("today"):
        today = parse(request.params["today"], "yyyy-MM-dd", utc())
      else:
        today = now().utc
    except:
      today = now().utc

    # Get contacts from database
    let contacts = await getContacts(dbConfig)

    # Find requested contact
    var contactFound = false
    var scheduledEmails: seq[Email]

    for contact in contacts:
      if contact.id == contactId:
        contactFound = true
        scheduledEmails = calculateScheduledEmails(contact, today)
        break

    if not contactFound:
      return errorResponse(Http404, "Contact not found")
    else:
      return successResponse(%*{"scheduledEmails": emailsToJson(
          scheduledEmails)})
  except Exception as e:
    error "Error retrieving scheduled emails: " & e.msg
    return errorResponse(Http500, e.msg)

proc handleBatchScheduleEmails(request: Request, dbConfig: DbConfig): Future[
    ResponseData] {.async.} =
  try:
    let reqJson = parseJson(request.body)

    # Validate required fields
    let validation = validateRequired(reqJson, "contacts")
    if not validation.valid:
      resp Http400, %*{"error": "Missing required fields: " & validation.missingFields.join(", ")}
      return
    
    # Parse contacts array
    var contacts: seq[Contact] = @[]
    var errors: seq[string] = @[]
    
    for i, contactNode in reqJson["contacts"]:
      let contactResult = toContact(contactNode)
      if contactResult.isOk:
        contacts.add(contactResult.value)
      else:
        errors.add("Contact #" & $i & ": " & contactResult.error.message)
    
    if errors.len > 0:
      resp Http400, %*{"errors": errors}
      return
    
    # Parse date parameter  
    let today = parseDate(reqJson, "today")
    
    # Calculate batch emails
    let emailsBatch = calculateBatchScheduledEmails(contacts, today)
    
    # Build response
    var results = newJArray()
    for i, contactEmails in emailsBatch:
      if i < contacts.len:  # Safety check
        results.add(%*{
          "contactId": contacts[i].id,
          "scheduledEmails": emailsToJson(contactEmails)
        })
        
    # Return response
    resp %*{"results": results}
  except Exception as e:
    error "Error batch scheduling emails: " & e.msg
    return errorResponse(Http500, e.msg)

# Main entry point for API server
when isMainModule:
  # Load environment variables
  loadDotEnv()
  
  # Get port from env or use default
  var port = 5000
  if existsEnv("API_PORT"):
    try:
      port = parseInt(getEnv("API_PORT"))
    except:
      echo "Invalid API_PORT, using default port 5000"
  
  echo "Starting API server on port ", port
  
  # Create routes
  routes:
    get "/health":
      resp %*{"status": "ok", "time": $now()}
      
    get "/api-docs":
      resp swaggerJson
      
    get "/docs":
      resp Http200, {"Content-Type": "text/html"}.newHttpHeaders(), swaggerUiHtml
      
    post "/schedule-emails":
      handleJsonRequest:
        # Validate required fields
        let validation = validateRequired(reqJson, "contact")
        if not validation.valid:
          errorJson("Missing required fields: " & validation.missingFields.join(", "))
          return
        
        # Parse contact using the template
        let contactResult = parseContact(reqJson["contact"])
        if not contactResult.isOk:
          errorJson(contactResult.error.message, contactResult.error.code)
          return
        
        let contact = contactResult.value
        
        # Parse date parameter
        let today = parseDate(reqJson, "today")
        
        # Calculate emails
        let emails = calculateScheduledEmails(contact, today)
        
        # Return response
        jsonResponse({"scheduledEmails": emailsToJson(emails)})
      
    post "/schedule-emails/batch":
      handleJsonRequest:
        # Validate required fields
        let validation = validateRequired(reqJson, "contacts")
        if not validation.valid:
          errorJson("Missing required fields: " & validation.missingFields.join(", "))
          return
        
        # Parse contacts array
        var contacts: seq[Contact] = @[]
        var errors: seq[string] = @[]
        
        for i, contactNode in reqJson["contacts"]:
          let contactResult = parseContact(contactNode)
          if contactResult.isOk:
            contacts.add(contactResult.value)
          else:
            errors.add("Contact #" & $i & ": " & contactResult.error.message)
        
        if errors.len > 0:
          jsonResponse({"errors": errors}, Http400)
          return
        
        # Parse date parameter  
        let today = parseDate(reqJson, "today")
        
        # Calculate batch emails
        let emailsBatch = calculateBatchScheduledEmails(contacts, today)
        
        # Build response
        var results = newJArray()
        for i, contactEmails in emailsBatch:
          if i < contacts.len:  # Safety check
            results.add(%*{
              "contactId": contacts[i].id,
              "scheduledEmails": emailsToJson(contactEmails)
            })
            
        # Return response
        jsonResponse({"results": results})
        
    get "/contacts/@contactId/scheduled-emails":
      withErrorHandling(void):
        let contactId = parseInt(@"contactId")
        
        # Parse date param using our template
        let today = parseDate(request.params.table, "today", now().utc)
          
        # Here you would typically load the contact from a database
        # For testing, we'll create a mock contact
        let contact = Contact(
          id: contactId,
          firstName: "Test",
          lastName: "User",
          email: "test@example.com",
          currentCarrier: "Test Carrier",
          planType: "Medicare",
          effectiveDate: some(parse("2025-03-15", "yyyy-MM-dd", utc())),
          birthDate: some(parse("1950-02-01", "yyyy-MM-dd", utc())),
          tobaccoUser: false,
          gender: "M",
          state: "TX",
          zipCode: "12345",
          agentID: 1,
          phoneNumber: some("555-1234"),
          status: some("Active")
        )
          
        # Calculate scheduled emails
        let emails = calculateScheduledEmails(contact, today)
        
        # Return response
        jsonResponse({"scheduledEmails": emailsToJson(emails)})

  # Start the server
  let settings = newSettings(port=Port(port))
  var jester = initJester(routes, settings=settings)
  jester.serve()
