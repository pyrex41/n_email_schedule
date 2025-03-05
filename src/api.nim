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
        "parameters": [
          {
            "name": "X-Organization-ID",
            "in": "header",
            "required": false,
            "schema": {
              "type": "string"
            },
            "description": "Organization ID to specify database"
          }
        ],
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
                  },
                  "organizationId": {
                    "type": "string",
                    "description": "Organization ID to specify database"
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
                    "organizationId": {
                      "type": "string"
                    },
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
          },
          {
            "name": "orgId",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            },
            "description": "Organization ID to specify database"
          },
          {
            "name": "X-Organization-ID",
            "in": "header",
            "required": false,
            "schema": {
              "type": "string"
            },
            "description": "Organization ID to specify database (alternative to query parameter)"
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
    "/organizations/{orgId}/contacts/{contactId}/scheduled-emails": {
      "get": {
        "summary": "Get scheduled emails by organization ID and contact ID",
        "description": "Retrieve scheduled emails for a contact in a specific organization",
        "parameters": [
          {
            "name": "orgId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Organization ID to specify database"
          },
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
        "parameters": [
          {
            "name": "X-Organization-ID",
            "in": "header",
            "required": false,
            "schema": {
              "type": "string"
            },
            "description": "Organization ID to specify database"
          }
        ],
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
                  },
                  "organizationId": {
                    "type": "string",
                    "description": "Organization ID to specify database"
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
                          "organizationId": {
                            "type": "string"
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
    "/organizations/{orgId}/schedule-emails/batch": {
      "post": {
        "summary": "Schedule emails for multiple contacts in a specific organization",
        "description": "Calculate scheduled emails for multiple contacts with AEP distribution",
        "parameters": [
          {
            "name": "orgId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Organization ID to specify database"
          }
        ],
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
                          "organizationId": {
                            "type": "string"
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
  # Use the withErrorHandling template for consistent error handling
  withErrorHandling(ResponseData):
    # Parse the request body
    let reqJson = parseJson(request.body)
    
    # Validate required fields
    let validation = validateRequired(reqJson, "contact")
    if not validation.valid:
      return errorResponse(Http400, "Missing required fields: " & validation.missingFields.join(", "))
    
    # Get organization ID (from request body, parameters or headers)
    var orgId = ""
    if reqJson.hasKey("organizationId"):
      orgId = reqJson["organizationId"].getStr
    elif request.params.hasKey("orgId"):
      orgId = request.params["orgId"]
    elif "X-Organization-ID" in request.headers:
      orgId = request.headers["X-Organization-ID"]
    
    if orgId == "":
      info "No organization ID provided for contact scheduling, using default database"
    else:
      info "Using organization ID for contact scheduling: " & orgId
    
    # Get database config for this organization
    let orgDbConfig = getOrgDbConfig(orgId)
    
    # Parse contact
    let contactResult = parseContact(reqJson["contact"])
    if not contactResult.isOk:
      return errorResponse(HttpCode(contactResult.error.code), contactResult.error.message)
    
    let contact = contactResult.value
    
    # Parse date or use current date
    let today = parseDate(reqJson, "today")
    
    # Calculate emails
    let emailsResult = calculateScheduledEmails(contact, today)
    if not emailsResult.isOk:
      return errorResponse(HttpCode(emailsResult.error.code), emailsResult.error.message)
    
    # Return response with organization ID
    return successResponse(%*{
      "organizationId": orgId, 
      "contactId": contact.id,
      "scheduledEmails": emailsToJson(emailsResult.value)
    })

proc handleGetContactEmails(request: Request, params: Table[string, string],
    dbConfig: DbConfig): Future[ResponseData] {.async.} =
  # Use the withErrorHandling template for consistent error handling
  withErrorHandling(ResponseData):
    # Validate contactId parameter
    let contactIdStr = params.getOrDefault("contactId")
    var contactId: int
    try:
      contactId = parseInt(contactIdStr)
    except:
      return errorResponse(Http400, "Invalid contact ID: " & contactIdStr)
      
    # Get organization ID (from request parameters or headers)
    var orgId = ""
    if request.params.hasKey("orgId"):
      orgId = request.params["orgId"]
    elif "X-Organization-ID" in request.headers:
      orgId = request.headers["X-Organization-ID"]
    
    if orgId == "":
      info "No organization ID provided, using default database"
    else:
      info "Using organization ID: " & orgId
    
    # Get database config for this organization
    let orgDbConfig = getOrgDbConfig(orgId)

    # Get date parameter or use today
    let today = 
      if request.params.hasKey("today"):
        try:
          parse(request.params["today"], "yyyy-MM-dd", utc())
        except:
          now().utc
      else:
        now().utc

    # Get contact directly by ID from the database
    let contactsResult = await getContacts(orgDbConfig, contactId)
    if not contactsResult.isOk:
      return errorResponse(HttpCode(contactsResult.error.code), contactsResult.error.message)
      
    let contacts = contactsResult.value
    
    # Check if contact was found
    if contacts.len == 0:
      return errorResponse(Http404, "Contact not found with ID: " & $contactId)
      
    # Calculate emails for the contact
    let targetContact = contacts[0]  # We should only have one contact
    let emailsResult = calculateScheduledEmails(targetContact, today)
    if not emailsResult.isOk:
      return errorResponse(HttpCode(emailsResult.error.code), emailsResult.error.message)
      
    # Return response
    return successResponse(%*{"scheduledEmails": emailsToJson(emailsResult.value)})

proc handleBatchScheduleEmails(request: Request, dbConfig: DbConfig): Future[
    ResponseData] {.async.} =
  # Use the withErrorHandling template for consistent error handling
  withErrorHandling(ResponseData):
    let reqJson = parseJson(request.body)

    # Validate required fields
    let validation = validateRequired(reqJson, "contacts")
    if not validation.valid:
      return errorResponse(Http400, "Missing required fields: " & validation.missingFields.join(", "))
    
    # Get organization ID (from request body, parameters or headers)
    var orgId = ""
    if reqJson.hasKey("organizationId"):
      orgId = reqJson["organizationId"].getStr
    elif request.params.hasKey("orgId"):
      orgId = request.params["orgId"]
    elif "X-Organization-ID" in request.headers:
      orgId = request.headers["X-Organization-ID"]
    
    if orgId == "":
      info "No organization ID provided for batch processing, using default database"
    else:
      info "Using organization ID for batch processing: " & orgId
    
    # Get database config for this organization
    let orgDbConfig = getOrgDbConfig(orgId)
    
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
      return errorResponse(Http400, "Invalid contact data: " & errors.join("; "))
      
    if contacts.len == 0:
      return errorResponse(Http400, "No valid contacts provided")
    
    # Parse date parameter  
    let today = parseDate(reqJson, "today")
    
    # Calculate batch emails
    let batchResult = calculateBatchScheduledEmails(contacts, today)
    if not batchResult.isOk:
      return errorResponse(HttpCode(batchResult.error.code), batchResult.error.message)
      
    let emailsBatch = batchResult.value
    
    # Build response
    var results = newJArray()
    for i, contactEmails in emailsBatch:
      if i < contacts.len:  # Safety check
        results.add(%*{
          "contactId": contacts[i].id,
          "organizationId": orgId,  # Include organization ID in response
          "scheduledEmails": emailsToJson(contactEmails)
        })
        
    # Return response
    return successResponse(%*{"results": results})

# Main entry point for API server
when isMainModule:
  # Setup logging
  setupLogging(lvlInfo)
  
  # Load environment variables
  loadDotEnv()
  
  # Get port from env or use default
  var port = 5000
  try:
    port = parseInt(getEnv("PORT", "5000"))
  except:
    error "Invalid PORT environment variable, using default 5000"
    port = 5000
  
  info "Starting Medicare Email Scheduler API on port " & $port
  
  let dbConfig = getConfigFromEnv()
  info "Connected to database at " & dbConfig.baseUrl
  
  # Define routes
  let router = router("MedicareScheduler"):
    get "/api-docs":
      ensureLogged:
        resp swaggerJson, "application/json"
        
    get "/docs":
      ensureLogged:
        resp swaggerUiHtml, "text/html"
    
    post "/schedule-emails":
      ensureLogged:
        let response = await handleScheduleEmails(request, dbConfig)
        return response
    
    # Support both with and without organization ID in the URL
    get "/contacts/@contactId/scheduled-emails":
      ensureLogged:
        let response = await handleGetContactEmails(request, @params, dbConfig)
        return response
        
    get "/organizations/@orgId/contacts/@contactId/scheduled-emails":
      ensureLogged:
        # Add orgId parameter to the request parameters
        request.params["orgId"] = @"orgId"
        let response = await handleGetContactEmails(request, @params, dbConfig)
        return response
        
    post "/schedule-emails/batch":
      ensureLogged:
        let response = await handleBatchScheduleEmails(request, dbConfig)
        return response
    
    # Organization-specific batch endpoint
    post "/organizations/@orgId/schedule-emails/batch":
      ensureLogged:
        # Add orgId parameter to the request parameters
        request.params["orgId"] = @"orgId"
        let response = await handleBatchScheduleEmails(request, dbConfig)
        return response
        
    notfound:
      resp Http404, %*{"error": "Not found"}
    
  # Start the server
  try:
    info "Medicare Email Scheduler API is running on http://localhost:" & $port
    router.run(port = port.Port)
  except Exception as e:
    error "Failed to start server: " & e.msg
