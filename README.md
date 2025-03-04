# Medicare Email Scheduler (Nim)

A concise and robust implementation of a Medicare email scheduler in Nim. This application schedules emails for Medicare enrollees based on their birthdate, effective date, and state-specific Medicare enrollment rules.

## Features

- Supports state-specific Medicare enrollment rules
- Handles exclusion windows for email scheduling
- Schedules birthday, effective date, AEP, and carrier update emails
- Uses the Turso database API for data storage
- Asynchronous database operations
- Comprehensive logging
- Supports configuration via .env file
- Dry-run mode for testing without a database
- RESTful API with Swagger documentation

## Structure

The application is organized into several modules:

- `models.nim`: Defines the core data structures (Contact and Email)
- `rules.nim`: Contains state-specific Medicare enrollment rules and helper functions
- `scheduler.nim`: Implements the email scheduling logic
- `database.nim`: Handles Turso database interaction
- `dotenv.nim`: Handles loading environment variables from .env file
- `api.nim`: Implements REST API with Swagger documentation
- `n_email_schedule.nim`: Main application entry point

## Configuration

The application can be configured using environment variables or a .env file:

### Using a .env File (Recommended)

1. Copy the sample .env file:
   ```bash
   cp .env.sample .env
   ```

2. Edit the .env file and fill in your Turso database credentials:
   ```
   TURSO_DB_URL=https://your-database-name-org.turso.io
   TURSO_AUTH_TOKEN=your_turso_auth_token
   ```

3. The application will automatically load variables from the .env file when it starts.

### Getting a Turso Auth Token

If you don't have a Turso auth token yet:

1. Install the Turso CLI:
   ```bash
   curl -sSfL https://get.tur.so/install.sh | bash
   ```

2. Login to Turso:
   ```bash
   turso auth login
   ```

3. Create an auth token for your database:
   ```bash
   turso db tokens create medicare-portal
   ```

4. Copy the generated token to your .env file.

If you're using an organization-specific database:
   ```bash
   turso db tokens create org-37
   ```

### Using Environment Variables

You can also set environment variables directly:

```bash
export TURSO_DB_URL="https://your-database-name-org.turso.io"
export TURSO_AUTH_TOKEN="your-turso-auth-token"
```

## Installation

Make sure you have Nim 2.2.0+ installed. You can install dependencies with:

```bash
nimble install
```

## Running the Application

### Using the run.sh Script (Recommended)

The easiest way to run the application is to use the provided script:

```bash
./run.sh
```

This script will:
- Check for a .env file and create one from the sample if needed
- Verify your Turso auth token is set
- Compile and run the application

### Command Line Options

The application supports several command line options:

```bash
./run.sh --dry-run    # Run without saving emails to database
./run.sh --verbose    # Enable more detailed logging
./run.sh --quiet      # Reduce log output
./run.sh --api        # Run as API server
./run.sh --port=5000  # Specify API server port (default: 5000)
./run.sh --help       # Show help message
```

You can also compile and run the application directly:

```bash
nim c -r src/n_email_schedule.nim
```

### Dry-Run Mode

If you want to test the application without connecting to a database:

```bash
./run.sh --dry-run
```

In dry-run mode:
- No database connection is required
- Test contacts are generated automatically
- Emails are calculated but not saved to the database
- Perfect for testing scheduling logic

### API Mode

Run the application as an API server:

```bash
./run.sh --api
```

This starts a RESTful API server with the following endpoints:

- `POST /schedule-emails`: Calculate scheduled emails for a single contact
- `GET /contacts/{contactId}/scheduled-emails`: Get scheduled emails for a specific contact
- `POST /schedule-emails/batch`: Calculate scheduled emails for multiple contacts with AEP distribution
- `GET /api-docs`: OpenAPI/Swagger JSON specification
- `GET /docs`: Interactive Swagger UI documentation

#### API Documentation

Interactive API documentation is available at http://localhost:5000/docs when running in API mode.

## Testing

The application includes comprehensive testing tools to verify the scheduling logic and API functionality:

### Nim Tests

Run the Nim unit tests to verify the scheduling logic:

```bash
# Run all tests
./test_nim.sh

# Run with verbose output
./test_nim.sh -v

# Run a specific test file
./test_nim.sh test_scheduler_simple.nim
```

### API Tests

Test the API endpoints with the provided script:

```bash
# Run all API tests
./test_api.sh

# Run with verbose output
./test_api.sh -v
```

### Test Scripts

The project includes two powerful testing scripts:

1. **API Test Script (`test_api.sh`)**
   - Tests all API endpoints using curl commands
   - Includes verbose mode (`-v` or `--verbose`)
   - Automatically starts the API server if not running
   - Verifies state-specific behavior, including year-round enrollment states
   - Validates both single-contact and batch scheduling

2. **Nim Test Script (`test_nim.sh`)**
   - Runs Nim tests with formatted, colorized output
   - Includes verbose mode for detailed test information
   - Can run specific test files or all tests
   - Formats output differently based on test type

Both scripts provide clear PASS/FAIL indicators and detailed information in verbose mode, making it easy to diagnose issues.

#### Output Format Features

Both scripts use color-coded output for better readability:
- **Green**: PASS indicators and successful test results
- **Red**: FAIL indicators and error messages
- **Yellow**: Test names and section headers
- **Cyan**: Detailed test information
- **Magenta**: Expected values
- **Blue**: Actual values

In verbose mode, they provide additional information:
- Expected vs. actual values for each test
- Detailed explanation of test conditions
- Complete test output for failed tests
- Summary of tests run

## Debugging

The application generates detailed logs in `scheduler.log` that you can monitor:

```bash
tail -f scheduler.log
```

## Database Schema Requirements

The application expects the following database schema:

### `contacts` table
```sql
CREATE TABLE contacts (
  id INTEGER PRIMARY KEY,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  email TEXT NOT NULL,
  current_carrier TEXT NOT NULL,
  plan_type TEXT NOT NULL,
  effective_date TEXT NOT NULL,
  birth_date TEXT NOT NULL,
  tobacco_user BOOLEAN NOT NULL,
  gender TEXT NOT NULL,
  state TEXT NOT NULL,
  zip_code TEXT NOT NULL,
  agent_id INTEGER,
  phone_number TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT ''
);
```

### `contact_events` table
```sql
CREATE TABLE contact_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  contact_id INTEGER,
  lead_id INTEGER,
  event_type TEXT NOT NULL,
  metadata TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (contact_id) REFERENCES contacts(id)
);
```

## AEP Distribution Logic

For multiple contacts, emails are distributed across four weeks in August-September:
1. **Week 1**: Last week of August (around August 22)
2. **Week 2**: Fourth week of August (around August 29)
3. **Week 3**: First week of September (around September 5)
4. **Week 4**: Second week of September (around September 12)

Contacts are distributed evenly across these weeks, accounting for exclusion windows for each contact.

## State-specific Rules

The application handles different types of Medicare enrollment rules:

1. **Birthday Rule**: Enrollment window around the enrollee's birthday
2. **Effective Date Rule**: Enrollment window around the policy's effective date
3. **Year-Round Enrollment**: States with continuous enrollment opportunities 