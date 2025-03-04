import unittest, asynchttpserver, asyncdispatch, json, times, strutils, sequtils, options
import ../src/models, ../src/scheduler, ../src/rules

suite "Simple API Tests":
  # Define a reference date for testing
  let today = parse("2025-01-01", "yyyy-MM-dd", utc())
  
  test "Email JSON conversion":
    let email = Email(
      emailType: "Birthday",
      status: "Pending",
      scheduledAt: parse("2025-02-01", "yyyy-MM-dd", utc()),
      reason: "Test reason"
    )
    
    let jsonNode = %*{
      "type": email.emailType,
      "status": email.status,
      "scheduledAt": email.scheduledAt.format("yyyy-MM-dd"),
      "reason": email.reason
    }
    
    check jsonNode["type"].getStr == "Birthday"
    check jsonNode["status"].getStr == "Pending"
    check jsonNode["scheduledAt"].getStr == "2025-02-01"
    check jsonNode["reason"].getStr == "Test reason"
  
  test "Contact parsing with Option types":
    let jsonNode = %*{
      "id": 1,
      "firstName": "Jane",
      "lastName": "Doe",
      "email": "jane@example.com",
      "currentCarrier": "Test Carrier",
      "planType": "Medicare",
      "tobaccoUser": false,
      "gender": "F",
      "state": "TX",
      "zipCode": "12345",
      "agentID": 123,
      "phoneNumber": "555-1234",
      "status": "Active",
      "effectiveDate": "2025-03-15",
      "birthDate": "1950-02-01"
    }
    
    # Using our improved parseContact function (to be implemented)
    proc parseContact(jsonNode: JsonNode): Contact =
      result = Contact(
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

      # Parse dates with proper error handling
      try:
        if jsonNode.hasKey("effectiveDate"):
          result.effectiveDate = some(parse(jsonNode["effectiveDate"].getStr, "yyyy-MM-dd", utc()))
        else:
          result.effectiveDate = none(DateTime)
      except CatchableError:
        result.effectiveDate = none(DateTime)

      try:
        if jsonNode.hasKey("birthDate"):
          result.birthDate = some(parse(jsonNode["birthDate"].getStr, "yyyy-MM-dd", utc()))
        else:
          result.birthDate = none(DateTime)
      except CatchableError:
        result.birthDate = none(DateTime)
    
    let contact = parseContact(jsonNode)
    
    check contact.id == 1
    check contact.firstName == "Jane"
    check contact.lastName == "Doe"
    check contact.email == "jane@example.com"
    check contact.phoneNumber.isSome()
    check contact.phoneNumber.get() == "555-1234"
    check contact.status.isSome()
    check contact.status.get() == "Active"
    check contact.effectiveDate.isSome()
    check contact.effectiveDate.get().format("yyyy-MM-dd") == "2025-03-15"
    check contact.birthDate.isSome()
    check contact.birthDate.get().format("yyyy-MM-dd") == "1950-02-01"
  
  test "Contact parsing with missing optional fields":
    let jsonNode = %*{
      "id": 2,
      "firstName": "John",
      "lastName": "Smith",
      "email": "john@example.com",
      "currentCarrier": "Test Carrier",
      "planType": "Medicare",
      "tobaccoUser": true,
      "gender": "M",
      "state": "CA",
      "zipCode": "90210",
      "agentID": 456,
      "effectiveDate": "2025-06-15",
      "birthDate": "1955-04-01"
    }
    
    # Using the same parseContact function
    proc parseContact(jsonNode: JsonNode): Contact =
      result = Contact(
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

      # Parse dates with proper error handling
      try:
        if jsonNode.hasKey("effectiveDate"):
          result.effectiveDate = some(parse(jsonNode["effectiveDate"].getStr, "yyyy-MM-dd", utc()))
        else:
          result.effectiveDate = none(DateTime)
      except CatchableError:
        result.effectiveDate = none(DateTime)

      try:
        if jsonNode.hasKey("birthDate"):
          result.birthDate = some(parse(jsonNode["birthDate"].getStr, "yyyy-MM-dd", utc()))
        else:
          result.birthDate = none(DateTime)
      except CatchableError:
        result.birthDate = none(DateTime)
    
    let contact = parseContact(jsonNode)
    
    check contact.id == 2
    check contact.firstName == "John"
    check contact.lastName == "Smith"
    check contact.phoneNumber.isNone()
    check contact.status.isNone()
    check contact.effectiveDate.isSome()
    check contact.birthDate.isSome()

    # Test successful parsing with all fields
    test "Contact parsing with required and optional fields":
      let jsonStr = """{"id":123,"firstName":"John","lastName":"Doe","state":"CA","phoneNumber":"555-1234","status":"active","effectiveDate":"2023-01-01","birthDate":"1980-05-15"}"""
      let jsonNode = parseJson(jsonStr)
      let contact = parseContact(jsonNode)

      check contact.id == 123
      check contact.firstName == "John"
      check contact.lastName == "Doe"
      check contact.state == "CA"
      check contact.phoneNumber.isSome()
      check contact.phoneNumber.get() == "555-1234"
      check contact.status.isSome()
      check contact.status.get() == "active"
      check contact.effectiveDate.isSome()
      check contact.effectiveDate.get().year == 2023
      check contact.birthDate.isSome()
      check contact.birthDate.get().year == 1980

    # Test parsing with only required fields
    test "Contact parsing with only required fields":
      let jsonStr = """{"id":456,"firstName":"Jane","lastName":"Smith","state":"NY","effectiveDate":"2023-05-10","birthDate":"1985-10-20"}"""
      let jsonNode = parseJson(jsonStr)
      let contact = parseContact(jsonNode)

      check contact.id == 456
      check contact.firstName == "Jane"
      check contact.lastName == "Smith"
      check contact.state == "NY"
      check contact.phoneNumber.isNone()
      check contact.status.isNone()
      check contact.effectiveDate.isSome()
      check contact.birthDate.isSome() 