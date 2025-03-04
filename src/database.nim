import httpclient, json, asyncdispatch, os, times, strutils
import models, dotenv

type
  DbConfig* = object
    baseUrl*: string
    authToken*: string

proc newDbConfig*(url: string, token: string): DbConfig =
  result = DbConfig(
    baseUrl: url.strip(trailing = true),
    authToken: token
  )

proc getConfigFromEnv*(): DbConfig =
  # Try to load from .env file first (won't override existing env vars)
  loadEnv()
  
  result = DbConfig(
    baseUrl: getEnv("TURSO_DB_URL", "https://medicare-portal-pyrex41.turso.io"),
    authToken: getEnv("TURSO_AUTH_TOKEN", "")
  )

proc parseIsoDate(dateStr: string): DateTime =
  # Parse ISO date format like "2023-04-15T00:00:00Z"
  try:
    result = parse(dateStr, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
  except:
    # Fallback for simpler date format
    try:
      result = parse(dateStr, "yyyy-MM-dd", utc())
    except:
      # Default to current date if parsing fails
      result = now()

proc execQuery*(config: DbConfig, sql: string, args: JsonNode = newJArray()): Future[JsonNode] {.async.} =
  let client = newAsyncHttpClient()
  let endpoint = config.baseUrl & "/v2/pipeline"
  
  client.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Authorization": "Bearer " & config.authToken
  })
  
  let reqBody = %*{
    "requests": [
      {
        "type": "execute",
        "stmt": {
          "sql": sql,
          "args": args
        }
      },
      {"type": "close"}
    ]
  }
  
  let response = await client.request(endpoint, httpMethod = HttpPost, body = $reqBody)
  let body = await response.body
  result = parseJson(body)
  client.close()

proc getContacts*(config: DbConfig): Future[seq[Contact]] {.async.} =
  let query = """
    SELECT 
      id, first_name, last_name, email, 
      current_carrier, plan_type, effective_date, birth_date,
      tobacco_user, gender, state, zip_code, agent_id, 
      phone_number, status 
    FROM contacts
  """
  
  let response = await execQuery(config, query)
  var contacts: seq[Contact] = @[]
  
  if "results" in response and response["results"].len > 0:
    let result = response["results"][0]
    if "rows" in result:
      for row in result["rows"]:
        let contact = Contact(
          id: row[0].getInt,
          firstName: row[1].getStr,
          lastName: row[2].getStr,
          email: row[3].getStr,
          currentCarrier: row[4].getStr,
          planType: row[5].getStr,
          effectiveDate: parseIsoDate(row[6].getStr),
          birthDate: parseIsoDate(row[7].getStr),
          tobaccoUser: row[8].getBool,
          gender: row[9].getStr,
          state: row[10].getStr,
          zipCode: row[11].getStr,
          agentID: row[12].getInt,
          phoneNumber: row[13].getStr,
          status: row[14].getStr
        )
        contacts.add(contact)
  
  return contacts

proc saveEmail*(config: DbConfig, email: Email, contactId: int): Future[bool] {.async.} =
  let query = """
    INSERT INTO contact_events
    (contact_id, event_type, metadata, created_at)
    VALUES (?, ?, ?, ?)
  """
  
  let metadata = %*{
    "type": email.emailType,
    "status": email.status,
    "reason": email.reason
  }
  
  let args = %*[
    {"type": "integer", "value": contactId},
    {"type": "text", "value": "email_scheduled"},
    {"type": "text", "value": $metadata},
    {"type": "text", "value": email.scheduledAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'")}
  ]
  
  let response = await execQuery(config, query, args)
  return "results" in response 