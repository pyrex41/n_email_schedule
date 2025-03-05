import json, times, options, strutils, strformat
import jester
import models
import logging

# Result type for error handling
type
  Error* = object
    message*: string
    code*: int

  Result*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      error*: Error

# Helper functions for Result type
proc ok*[T](value: T): Result[T] =
  Result[T](isOk: true, value: value)

proc err*[T](message: string, code: int = 500): Result[T] =
  Result[T](isOk: false, error: Error(message: message, code: code))

# Templates for API handlers
template handleJsonRequest*(body: untyped): untyped =
  ## Template for handling JSON API requests.
  ## Automatically parses the request body as JSON and handles errors.
  try:
    let reqJson = parseJson(request.body)
    body
  except Exception as e:
    resp Http400, %*{"error": "Invalid JSON: " & e.msg}

template parseDate*(jsonNode: JsonNode, key: string, defaultDate: DateTime = now().utc): DateTime =
  ## Template for parsing dates from JSON with a default fallback
  block:
    var result: DateTime
    try:
      if jsonNode.hasKey(key):
        result = parse(jsonNode[key].getStr, "yyyy-MM-dd", utc())
      else:
        result = defaultDate
    except:
      result = defaultDate
    result

# Logging utilities for consistent error handling
var logger* = newConsoleLogger(fmtStr="[$time] - $levelname: ")
var fileLogger* = newFileLogger("scheduler.log", fmtStr="[$time] - $levelname: ")

# Configure logging
proc setupLogging*(logLevel: Level = lvlInfo) =
  addHandler(logger)
  addHandler(fileLogger)
  setLogFilter(logLevel)

# Convenience logging functions that work with Result[T]
template logResult*[T](res: Result[T], context: string): untyped =
  if not res.isOk:
    error context & ": " & res.error.message
    res
  else:
    debug context & ": Success"
    res

# Template for ensuring all errors are logged
template ensureLogged*(body: untyped): untyped =
  try:
    body
  except Exception as e:
    error getCurrentExceptionMsg()
    raise e

# Enhanced Result templates that include logging
template okWithLog*[T](value: T, context: string): Result[T] =
  debug context & ": Success"
  ok(value)

template errWithLog*[T](message: string, code: int = 500, context: string): Result[T] =
  error context & ": " & message
  err[T](message, code)

# Extended templates for API routes with better error handling and logging
template withErrorHandlingAndLogging*(responseType: typedesc, context: string, body: untyped): untyped =
  ## Enhanced template for handling errors with logging
  try:
    debug context & ": Starting operation"
    body
  except Exception as e:
    error context & ": " & e.msg
    when responseType is void:
      resp Http500, %*{"error": e.msg}
    else:
      err(responseType, e.msg, 500)
  finally:
    debug context & ": Operation completed"

# Result helper for executing a function with automatic error logging
template tryWithLogging*[T](context: string, fn: untyped): Result[T] =
  try:
    debug context & ": Attempting operation"
    let result = fn
    debug context & ": Operation successful"
    ok(result)
  except Exception as e:
    let errorMsg = getCurrentExceptionMsg()
    error context & ": " & errorMsg
    err[T](errorMsg, 500)

# Template for sending API responses based on Result
template apiResponse*[T](result: Result[T]): untyped =
  if result.isOk:
    resp %*{"data": result.value}
  else:
    resp HttpCode(result.error.code), %*{"error": result.error.message}

# Template for validating required JSON fields
template validateRequired*(jsonNode: JsonNode, fields: varargs[string]): tuple[valid: bool, missingFields: seq[string]] =
  ## Template for validating required JSON fields.
  ## Returns a tuple with a boolean indicating if all required fields are present,
  ## and a sequence of missing field names.
  block:
    var missingFields: seq[string] = @[]
    for field in fields:
      if not jsonNode.hasKey(field):
        missingFields.add(field)
    
    (valid: missingFields.len == 0, missingFields: missingFields)

# Template for parsing Contact objects
template parseContact*(jsonNode: JsonNode): untyped =
  ## Template for parsing a Contact object from JSON.
  ## Returns a Result[Contact].
  block:
    # Validate required fields
    let requiredFields = ["id", "firstName", "lastName", "state"]
    var missingFields: seq[string] = @[]
    
    for field in requiredFields:
      if not jsonNode.hasKey(field):
        missingFields.add(field)
    
    if missingFields.len > 0:
      err[Contact]("Missing required fields: " & missingFields.join(", "), 400)
    else:
      # Create contact with required fields
      var contact = Contact(
        id: jsonNode["id"].getInt,
        firstName: jsonNode["firstName"].getStr,
        lastName: jsonNode["lastName"].getStr,
        email: if jsonNode.hasKey("email"): jsonNode["email"].getStr else: "",
        currentCarrier: if jsonNode.hasKey("currentCarrier"): jsonNode["currentCarrier"].getStr else: "",
        planType: if jsonNode.hasKey("planType"): jsonNode["planType"].getStr else: "",
        tobaccoUser: if jsonNode.hasKey("tobaccoUser"): jsonNode["tobaccoUser"].getBool else: false,
        gender: if jsonNode.hasKey("gender"): jsonNode["gender"].getStr else: "",
        state: jsonNode["state"].getStr,
        zipCode: if jsonNode.hasKey("zipCode"): jsonNode["zipCode"].getStr else: "",
        agentID: if jsonNode.hasKey("agentID"): jsonNode["agentID"].getInt else: 0,
        phoneNumber: if jsonNode.hasKey("phoneNumber"): some(jsonNode["phoneNumber"].getStr) else: none(string),
        status: if jsonNode.hasKey("status"): some(jsonNode["status"].getStr) else: none(string)
      )

      # Parse dates with safe date templates
      contact.effectiveDate = 
        if jsonNode.hasKey("effectiveDate"):
          safeParseDate(jsonNode["effectiveDate"].getStr)
        else:
          none(DateTime)
          
      contact.birthDate = 
        if jsonNode.hasKey("birthDate"):
          safeParseDate(jsonNode["birthDate"].getStr)
        else:
          none(DateTime)
        
      ok(contact)

# Templates for API responses
template jsonResponse*(data: untyped, status: HttpCode = Http200) =
  ## Template for sending JSON responses
  resp status, %*data

template errorJson*(message: string, code: int = 400) =
  ## Template for sending error JSON responses
  jsonResponse({"error": message}, HttpCode(code))

# Templates for date operations
template safeParseDate*(dateStr: string, format: string = "yyyy-MM-dd"): Option[DateTime] =
  ## Safely parse a date string, returning an Option[DateTime]
  block:
    try:
      some(parse(dateStr, format, utc()))
    except:
      none(DateTime)

template safeAddDays*(date: Option[DateTime], days: int): Option[DateTime] =
  ## Safely add days to an Option[DateTime]
  block:
    if date.isSome():
      try:
        # Create a new DateTime with the days added
        let dt = date.get()
        let newDate = dt + initTimeInterval(0, 0, 0, days, 0, 0, 0, 0)
        some(newDate)
      except:
        date
    else:
      none(DateTime)

template safeYearlyDate*(date: Option[DateTime], year: int): Option[DateTime] =
  ## Safely get the same date in another year
  block:
    if not date.isSome():
      none(DateTime)
    else:
      try:
        let d = date.get()
        let monthInt = ord(d.month)
        let dayInt = min(d.monthday, 28) # Safe value for all months
        let dateStr = $year & "-" & (if monthInt < 10: "0" & $monthInt else: $monthInt) & "-" & (if dayInt < 10: "0" & $dayInt else: $dayInt)
        some(parse(dateStr, "yyyy-MM-dd", utc()))
      except:
        none(DateTime) 