# models.nim
# Defines the core data structures for contacts and emails

import times
import json

type
  Contact* = object
    id*: int
    firstName*: string
    lastName*: string
    email*: string
    currentCarrier*: string
    planType*: string
    effectiveDate*: DateTime
    birthDate*: DateTime
    tobaccoUser*: bool
    gender*: string
    state*: string
    zipCode*: string
    agentID*: int
    phoneNumber*: string
    status*: string

  EmailType* = enum
    Birthday, Effective, AEP, PostExclusion

  Email* = object
    emailType*: EmailType
    scheduledAt*: DateTime
    reason*: string
    
  # New custom type for exclusion window
  ExclusionWindow* = tuple[start: DateTime, endDate: DateTime, emailType: EmailType]
    
  Result*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      error*: string 

# Add conversion for EmailType to string for JSON serialization
proc `$`*(emailType: EmailType): string =
  case emailType:
    of Birthday: "Birthday"
    of Effective: "Effective"
    of AEP: "AEP"
    of PostExclusion: "PostExclusion"

# Convert Email to JsonNode
proc toJson*(email: Email): JsonNode =
  result = %* {
    "emailType": $email.emailType,
    "scheduledAt": email.scheduledAt.format("yyyy-MM-dd'T'HH:mm:sszzz"),
    "reason": email.reason
  }

# Convert sequence of Emails to JsonNode
proc toJson*(emails: seq[Email]): JsonNode =
  result = newJArray()
  for email in emails:
    result.add(email.toJson()) 

# Convert Contact to JsonNode
proc toJson*(contact: Contact): JsonNode =
  result = %* {
    "id": contact.id,
    "firstName": contact.firstName,
    "lastName": contact.lastName,
    "email": contact.email,
    "currentCarrier": contact.currentCarrier,
    "planType": contact.planType,
    "effectiveDate": contact.effectiveDate.format("yyyy-MM-dd'T'HH:mm:sszzz"),
    "birthDate": contact.birthDate.format("yyyy-MM-dd'T'HH:mm:sszzz"),
    "tobaccoUser": contact.tobaccoUser,
    "gender": contact.gender,
    "state": contact.state,
    "zipCode": contact.zipCode,
    "agentID": contact.agentID,
    "phoneNumber": contact.phoneNumber,
    "status": contact.status
  } 