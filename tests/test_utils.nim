import unittest, json, times, strutils, options
import ../src/utils, ../src/models

suite "Result Type Tests":
  test "Result ok":
    let result = ok(10)
    check result.isOk
    check result.value == 10

  test "Result err":
    let result = err[int]("error message", 400)
    check not result.isOk
    check result.error.message == "error message"
    check result.error.code == 400

suite "Template Tests":
  test "validateRequired - all fields present":
    let jsonNode = %*{"id": 1, "name": "test", "value": 10}
    let validation = validateRequired(jsonNode, "id", "name", "value")
    check validation.valid
    check validation.missingFields.len == 0

  test "validateRequired - missing fields":
    let jsonNode = %*{"id": 1, "value": 10}
    let validation = validateRequired(jsonNode, "id", "name", "value")
    check not validation.valid
    check validation.missingFields == @["name"]

  test "safeParseDate - valid date":
    let date = safeParseDate("2025-01-01")
    check date.isSome()
    check date.get().year == 2025
    check date.get().month == mJan
    check date.get().monthday == 1

  test "safeParseDate - invalid date":
    let date = safeParseDate("invalid-date")
    check date.isNone()

  test "safeAddDays - with valid date":
    # Parse a date and then add days to it
    let originalDate = parse("2025-01-01", "yyyy-MM-dd", utc())
    let optDate = some(originalDate)
    let daysToAdd = 5
    
    # Use the safeAddDays template
    let newDate = safeAddDays(optDate, daysToAdd)
    
    # Check the result
    check newDate.isSome()
    let resultDate = newDate.get()
    check resultDate.year == 2025
    check resultDate.month == mJan
    check resultDate.monthday == 1

  test "safeAddDays - with none date":
    let date = none(DateTime)
    let newDate = safeAddDays(date, 5)
    check newDate.isNone()

  test "safeYearlyDate - with valid date":
    let date = safeParseDate("2025-01-01")
    let newDate = safeYearlyDate(date, 2026)
    check newDate.isSome()
    check newDate.get().year == 2026
    check newDate.get().month == mJan
    check newDate.get().monthday == 1

  test "safeYearlyDate - with none date":
    let date = none(DateTime)
    let newDate = safeYearlyDate(date, 2026)
    check newDate.isNone()

suite "Contact Parsing Tests":
  test "parseContact - valid contact":
    let jsonNode = %*{
      "id": 1,
      "firstName": "John",
      "lastName": "Doe",
      "state": "TX",
      "email": "john@example.com",
      "effectiveDate": "2025-01-01",
      "birthDate": "1950-01-01"
    }
    
    let result = parseContact(jsonNode)
    check result.isOk
    check result.value.id == 1
    check result.value.firstName == "John"
    check result.value.lastName == "Doe"
    check result.value.state == "TX"
    check result.value.email == "john@example.com"
    check result.value.effectiveDate.isSome()
    check result.value.effectiveDate.get().year == 2025
    check result.value.birthDate.isSome()
    check result.value.birthDate.get().year == 1950

  test "parseContact - missing required fields":
    let jsonNode = %*{
      "id": 1,
      "firstName": "John"
    }
    
    let result = parseContact(jsonNode)
    check not result.isOk
    check result.error.code == 400
    check "Missing required fields" in result.error.message 