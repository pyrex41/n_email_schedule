# Medicare Email Scheduler API

A RESTful API for scheduling emails for Medicare contacts based on complex scheduling rules including:
- Email Spacing Exclusion (60-day rule)
- Statutory Exclusion Window (state-specific rules)
- AEP (Annual Enrollment Period) scheduling

## Features

- Multi-tenant database architecture using organization IDs
- Fetches contact data from organization-specific databases
- Calculates optimal email schedules based on complex state-specific rules
- Supports both single contact and batch scheduling
- Provides detailed metadata on scheduling decisions (optional)

## API Endpoints

### Schedule Emails for a Single Contact

```
POST /organizations/{orgId}/schedule-emails
```

**Request:**
- Path: orgId (int) - organization ID
- Query Parameters:
  - verbose=true (optional) - Include detailed metadata in response
- Body:
```json
{
  "contactId": 1,
  "today": "2025-01-01" // optional, defaults to current date
}
```

**Response:**
```json
{
  "scheduledEmails": [
    {
      "type": "AEP",
      "scheduledAt": "2025-08-18",
      "reason": "Week 1"
    },
    {
      "type": "PostExclusion",
      "scheduledAt": "2025-04-17",
      "reason": "Post-window Birthday"
    }
  ],
  "metadata": { // only included when verbose=true
    "appliedRules": ["BirthdayRule"],
    "exclusions": ["Effective in statutory window"],
    "stateRuleType": "Birthday",
    "exclusionWindow": {
      "start": "2024-12-03",
      "end": "2025-04-16"
    }
  }
}
```

**Status Codes:**
- 200: Success
- 400: Missing contactId or invalid orgId
- 404: Contact not found
- 500: Database error or internal server error

### Schedule Emails for Multiple Contacts

```
POST /organizations/{orgId}/schedule-emails/batch
```

**Request:**
- Path: orgId (int) - organization ID
- Query Parameters:
  - verbose=true (optional) - Include detailed metadata in response
- Body:
```json
{
  "contactIds": [1, 2, 3],
  "today": "2025-01-01" // optional, defaults to current date
}
```

**Response:**
```json
{
  "results": [
    {
      "contactId": 1,
      "scheduledEmails": [
        {
          "type": "AEP",
          "scheduledAt": "2025-08-18",
          "reason": "Week 1"
        }
      ],
      "metadata": { /* if verbose=true */ }
    },
    {
      "contactId": 2,
      "scheduledEmails": [
        {
          "type": "AEP",
          "scheduledAt": "2025-08-25",
          "reason": "Week 2"
        }
      ],
      "metadata": { /* if verbose=true */ }
    },
    {
      "contactId": 3,
      "scheduledEmails": [
        {
          "type": "AEP",
          "scheduledAt": "2025-09-01",
          "reason": "Week 3"
        }
      ],
      "metadata": { /* if verbose=true */ }
    }
  ]
}
```

**Status Codes:**
- 200: Success
- 400: Missing contactIds or invalid orgId
- 404: One or more contacts not found
- 500: Database error or internal server error

## Database Architecture

### Main Database (medicare-portal)
- Table: organizations
  - id: Organization ID
  - turso_db_url: URL for the organization's tenant database
  - turso_auth_token: Auth token for accessing the tenant database

### Tenant Databases (e.g., org-37)
- Table: contacts
  - id: Contact ID
  - first_name: First name
  - last_name: Last name
  - email: Email address
  - current_carrier: Current insurance carrier
  - plan_type: Type of insurance plan
  - effective_date: When insurance coverage begins
  - birth_date: Contact's birthday
  - tobacco_user: Whether the contact uses tobacco
  - gender: Contact's gender
  - state: State of residence (critical for statutory rules)
  - zip_code: ZIP code
  - agent_id: ID of the associated agent
  - phone_number: Contact's phone number
  - status: Current status in the system

## Setup and Running

### Prerequisites
- Nim compiler
- Jester (HTTP framework for Nim)
- Turso or compatible SQL database

### Environment Variables
Create a `.env` file with the following variables:
```
TURSO_DB_URL=https://medicare-portal-pyrex41.turso.io
TURSO_AUTH_TOKEN=your_main_db_auth_token
PORT=5000 # optional, defaults to 5000
```

### Running the API
```bash
# Install dependencies
nimble install jester

# Run the API
nim c -r src/api.nim
```

## Email Scheduling Rules

### Email Types
- **Birthday Email**: Sent 14 days before contact's birthday
- **Effective Date Email**: Sent 30 days before insurance effective date
- **AEP Email**: Sent during one of four AEP weeks in August-September
- **Post-Exclusion Email**: Sent immediately after a statutory exclusion window ends

### Email Spacing Rule
- Emails (except AEP and Post-Exclusion) must be at least 60 days apart

### Statutory Exclusion Windows
- **Birthday Rule States**: CA, ID, IL, KY, LA, MD, NV, OK, OR
  - Window: 30 days before to 30 days after birthday
  - Lead time: 60 days (no emails in this period before the window)
  
- **Effective Date Rule States**: MO
  - Window: 31 days before to 31 days after effective date
  - Lead time: 60 days

- **Year-Round Enrollment States**: CT
  - No exclusion window

### AEP Weeks
1. August 18
2. August 25
3. September 1
4. September 7

For batch processing, contacts are distributed evenly across these weeks. 