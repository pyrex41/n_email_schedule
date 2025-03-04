import asynchttpserver, asyncdispatch, json, times, strutils, sequtils
import src/models, src/scheduler, src/rules

# Define the placeholder for REST routes
const RestPlaceholder = "{id}"

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
      "url": "http://localhost:5001",
      "description": "Local server"
    }
  ],
  "paths": {
    "/health": {
      "get": {
        "summary": "Health check",
        "description": "Returns the API's health status",
        "responses": {
          "200": {
            "description": "API is healthy",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "status": {
                      "type": "string",
                      "example": "ok"
                    },
                    "time": {
                      "type": "string",
                      "example": "2025-01-15T10:00:00Z"
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    "/api-info": {
      "get": {
        "summary": "API information",
        "description": "Returns information about the API",
        "responses": {
          "200": {
            "description": "API information",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "name": {
                      "type": "string"
                    },
                    "version": {
                      "type": "string"
                    },
                    "routes": {
                      "type": "array",
                      "items": {
                        "type": "string"
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
    "/api-docs": {
      "get": {
        "summary": "API Documentation",
        "description": "OpenAPI specification",
        "responses": {
          "200": {
            "description": "OpenAPI JSON"
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
            "description": "Swagger UI HTML"
          }
        }
      }
    },
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
            "description": "Scheduled emails",
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
            "description": "Bad request",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "error": {
                      "type": "string"
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    "/contacts/{id}/scheduled-emails": {
      "get": {
        "summary": "Get scheduled emails for a contact",
        "description": "Returns scheduled emails for a contact by ID",
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "schema": {
              "type": "integer"
            },
            "description": "Contact ID"
          }
        ],
        "responses": {
          "200": {
            "description": "Scheduled emails",
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
            "description": "Bad request",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "error": {
                      "type": "string"
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    "/schedule-emails/batch": {
      "post": {
        "summary": "Batch schedule emails",
        "description": "Calculate scheduled emails for multiple contacts",
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
            "description": "Batch results",
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
            "description": "Bad request",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "error": {
                      "type": "string"
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
  "components": {
    "schemas": {
      "Contact": {
        "type": "object",
        "required": ["id", "firstName", "lastName", "email", "currentCarrier", "planType", "birthDate", "effectiveDate", "gender", "state", "zipCode", "agentID"],
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
            "type": "string",
            "format": "email"
          },
          "currentCarrier": {
            "type": "string"
          },
          "planType": {
            "type": "string"
          },
          "birthDate": {
            "type": "string",
            "format": "date"
          },
          "effectiveDate": {
            "type": "string",
            "format": "date"
          },
          "tobaccoUser": {
            "type": "boolean"
          },
          "gender": {
            "type": "string",
            "enum": ["M", "F"]
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
            "type": "string",
            "enum": ["Active", "Inactive", "Pending"]
          }
        }
      },
      "Email": {
        "type": "object",
        "required": ["type", "status", "scheduledAt"],
        "properties": {
          "type": {
            "type": "string",
            "enum": ["Welcome", "Reminder", "Confirmation", "FollowUp"]
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
        "/api-docs",
        "/docs",
        "/schedule-emails",
        "/contacts/{id}/scheduled-emails",
        "/schedule-emails/batch"
      ]
    }
    await req.respond(Http200, $data, headers.newHttpHeaders())
  
  of "/api-docs":
    await req.respond(Http200, swaggerJson, headers.newHttpHeaders())
    
  of "/docs":
    await req.respond(Http200, swaggerUiHtml, {"Content-Type": "text/html"}.newHttpHeaders())
    
  of "/schedule-emails":
    if req.reqMethod == HttpPost:
      try:
        let body = parseJson(req.body)
        let contact = parseContact(body["contact"])
        var today = now()
        
        if body.hasKey("today") and body["today"].kind == JString:
          try:
            today = parse(body["today"].getStr, "yyyy-MM-dd", utc())
          except:
            let errorMsg = %*{"error": "Invalid date format for 'today'. Expected yyyy-MM-dd"}
            await req.respond(Http400, $errorMsg, headers.newHttpHeaders())
            return
        
        let emails = calculateScheduledEmails(contact, today)
        let responseData = %*{
          "scheduledEmails": emailsToJson(emails)
        }
        
        await req.respond(Http200, $responseData, headers.newHttpHeaders())
      except Exception as e:
        let errorMsg = %*{"error": "Failed to process request: " & e.msg}
        await req.respond(Http400, $errorMsg, headers.newHttpHeaders())
    else:
      let errorMsg = %*{"error": "Method not allowed. Use POST"}
      await req.respond(Http405, $errorMsg, headers.newHttpHeaders())
      
  of "/schedule-emails/batch":
    if req.reqMethod == HttpPost:
      try:
        let body = parseJson(req.body)
        var contacts: seq[Contact] = @[]
        var today = now()
        
        if body.hasKey("today") and body["today"].kind == JString:
          try:
            today = parse(body["today"].getStr, "yyyy-MM-dd", utc())
          except:
            let errorMsg = %*{"error": "Invalid date format for 'today'. Expected yyyy-MM-dd"}
            await req.respond(Http400, $errorMsg, headers.newHttpHeaders())
            return
        
        if body.hasKey("contacts") and body["contacts"].kind == JArray:
          for contactJson in body["contacts"]:
            contacts.add(parseContact(contactJson))
        else:
          let errorMsg = %*{"error": "Missing or invalid 'contacts' array in request body"}
          await req.respond(Http400, $errorMsg, headers.newHttpHeaders())
          return
        
        let results = calculateBatchScheduledEmails(contacts, today)
        var resultsJson = newJArray()
        for i, contact in contacts:
          resultsJson.add(%*{
            "contactId": contact.id,
            "scheduledEmails": emailsToJson(results[i])
          })
        
        let responseData = %*{"results": resultsJson}
        await req.respond(Http200, $responseData, headers.newHttpHeaders())
      except Exception as e:
        let errorMsg = %*{"error": "Failed to process request: " & e.msg}
        await req.respond(Http400, $errorMsg, headers.newHttpHeaders())
    else:
      let errorMsg = %*{"error": "Method not allowed. Use POST"}
      await req.respond(Http405, $errorMsg, headers.newHttpHeaders())
  
  else:
    # Handle /contacts/{id}/scheduled-emails pattern
    let path = req.url.path
    if path.startsWith("/contacts/") and path.endsWith("/scheduled-emails"):
      let parts = path.split("/")
      if parts.len == 4 and req.reqMethod == HttpGet:
        try:
          let id = parseInt(parts[2])
          # For demo purposes, we're creating a dummy contact
          let contact = Contact(
            id: id,
            firstName: "John",
            lastName: "Doe",
            email: "john.doe@example.com",
            currentCarrier: "UnitedHealthcare",
            planType: "Medicare Advantage",
            birthDate: parse("1950-01-01", "yyyy-MM-dd", utc()),
            effectiveDate: parse("2023-01-01", "yyyy-MM-dd", utc()),
            tobaccoUser: false,
            gender: "M",
            state: "NY",
            zipCode: "10001",
            agentID: 1001,
            phoneNumber: "555-123-4567",
            status: "Active"
          )
          
          let emails = calculateScheduledEmails(contact, now())
          let responseData = %*{
            "scheduledEmails": emailsToJson(emails)
          }
          
          await req.respond(Http200, $responseData, headers.newHttpHeaders())
        except Exception as e:
          let errorMsg = %*{"error": "Failed to process request: " & e.msg}
          await req.respond(Http400, $errorMsg, headers.newHttpHeaders())
      else:
        let errorMsg = %*{"error": "Method not allowed. Use GET"}
        await req.respond(Http405, $errorMsg, headers.newHttpHeaders())
    else:
      let errorMsg = %*{"error": "Not found"}
      await req.respond(Http404, $errorMsg, headers.newHttpHeaders())

# Start the server on port 5001
let server = newAsyncHttpServer()
const port = 5001
echo "Starting server on port ", port

proc serve() {.async.} =
  waitFor server.serve(Port(port), handler)

waitFor serve() 