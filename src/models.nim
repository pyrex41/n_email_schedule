import times
import options

type
  Contact* = object
    id*: int
    firstName*, lastName*, email*: string
    currentCarrier*, planType*: string
    effectiveDate*, birthDate*: Option[DateTime]  # Optional dates
    tobaccoUser*: bool
    gender*, state*, zipCode*: string
    phoneNumber*, status*: Option[string]  # Optional strings
    agentID*: int

  Email* = object
    emailType*, status*: string
    scheduledAt*: DateTime
    reason*: string
    contactId*: int  # Add contactId field to match what tests expect 