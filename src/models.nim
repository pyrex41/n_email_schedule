import times

type
  Contact* = object
    id*: int
    firstName*, lastName*, email*: string
    currentCarrier*, planType*: string
    effectiveDate*, birthDate*: DateTime
    tobaccoUser*: bool
    gender*, state*, zipCode*, phoneNumber*, status*: string
    agentID*: int

  Email* = object
    emailType*, status*: string
    scheduledAt*: DateTime
    reason*: string 