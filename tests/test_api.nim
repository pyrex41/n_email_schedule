import unittest, json, times, options, strutils, sequtils
import ../src/models, ../src/scheduler, ../src/utils

suite "API Tests":
  # Define a reference date for testing
  let today = parse("2025-01-01", "yyyy-MM-dd", utc())
  
  test "Email JSON conversion":
    let email = Email(
      emailType: "Birthday",
      status: "Pending",
      scheduledAt: parse("2025-02-01", "yyyy-MM-dd", utc()),
      reason: "Test reason"
    )
    
    # Manual JSON conversion for testing
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
  
  test "Contact parsing with required fields":
    let jsonNode = %*{
      "id": 1,
      "firstName": "John",
      "lastName": "Doe",
      "state": "TX"
    }
    
    let result = parseContact(jsonNode)
    check result.isOk
    check result.value.id == 1
    check result.value.firstName == "John"
    check result.value.lastName == "Doe"
    check result.value.state == "TX"
  
  test "Contact parsing with missing required fields":
    let jsonNode = %*{
      "id": 1,
      "firstName": "John"
    }
    
    let result = parseContact(jsonNode)
    check not result.isOk
    check result.error.code == 400
    check "Missing required fields" in result.error.message
    check "lastName" in result.error.message
    check "state" in result.error.message
  
  test "Contact parsing with all fields":
    let jsonNode = %*{
      "id": 1,
      "firstName": "John",
      "lastName": "Doe",
      "state": "TX",
      "email": "john@example.com",
      "currentCarrier": "Test Carrier",
      "planType": "Medicare",
      "effectiveDate": "2025-03-15",
      "birthDate": "1950-02-01",
      "tobaccoUser": false,
      "gender": "M",
      "zipCode": "12345",
      "agentID": 123,
      "phoneNumber": "555-1234",
      "status": "Active"
    }
    
    let result = parseContact(jsonNode)
    check result.isOk
    let contact = result.value
    
    check contact.id == 1
    check contact.firstName == "John"
    check contact.lastName == "Doe"
    check contact.state == "TX"
    check contact.email == "john@example.com"
    check contact.currentCarrier == "Test Carrier"
    check contact.planType == "Medicare"
    check contact.effectiveDate.isSome
    check contact.effectiveDate.get().year == 2025
    check contact.effectiveDate.get().month == mMar
    check contact.effectiveDate.get().monthday == 15
    check contact.birthDate.isSome
    check contact.birthDate.get().year == 1950
    check contact.birthDate.get().month == mFeb
    check contact.birthDate.get().monthday == 1
    check contact.tobaccoUser == false
    check contact.gender == "M"
    check contact.zipCode == "12345"
    check contact.agentID == 123
    check contact.phoneNumber.isSome
    check contact.phoneNumber.get() == "555-1234"
    check contact.status.isSome
    check contact.status.get() == "Active"
  
  test "validateRequired template":
    let jsonNode = %*{"name": "test", "age": 25}
    
    let validation1 = validateRequired(jsonNode, "name", "age")
    check validation1.valid
    check validation1.missingFields.len == 0
    
    let validation2 = validateRequired(jsonNode, "name", "age", "email")
    check not validation2.valid
    check validation2.missingFields == @["email"]
  
  test "Date parsing templates":
    let jsonNode = %*{"date1": "2025-01-15", "emptyDate": ""}
    
    let date1 = parseDate(jsonNode, "date1")
    check date1.year == 2025
    check date1.month == mJan
    check date1.monthday == 15
    
    let defaultDate = now().utc
    let date2 = parseDate(jsonNode, "missingDate", defaultDate)
    check date2 == defaultDate
    
    let date3 = parseDate(jsonNode, "emptyDate", defaultDate)
    check date3 == defaultDate

  test "Result type success":
    let result = ok(42)
    check result.isOk
    check result.value == 42

  test "Result type error":
    let result = err[int]("Test error", 400)
    check not result.isOk
    check result.error.message == "Test error"
    check result.error.code == 400 