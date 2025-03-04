# Email Scheduler Tests

This directory contains tests for the email scheduling functionality, focusing on verifying the implementation of the email rules as defined in `EmailRules.md`.

## Test Files

- `test_email_rules.nim` - Direct tests for the core scheduler logic
- `test_scheduler.nim` - Original scheduler tests (currently has dependencies issues)

## Running Tests

To run the tests, use the `run_tests.sh` script in the root directory:

```bash
./run_tests.sh
```

Or run individual test files with:

```bash
nim c -r tests/test_email_rules.nim
```

### Using the Test Scripts

The project now includes two specialized test scripts:

#### Nim Test Script

The `test_nim.sh` script provides a more user-friendly way to run and view Nim tests:

```bash
# Run all tests
./test_nim.sh

# Run with verbose output (detailed test information)
./test_nim.sh -v

# Run a specific test
./test_nim.sh test_scheduler_simple.nim

# Show help
./test_nim.sh -h
```

This script:
- Formats test output with colorized PASS/FAIL indicators
- Shows detailed test information in verbose mode
- Adapts output formatting to different test types
- Can run all tests or specific test files

#### API Test Script

The `test_api.sh` script tests the API endpoints:

```bash
# Run all API tests
./test_api.sh

# Run with verbose output
./test_api.sh -v

# Show help
./test_api.sh -h
```

This script:
- Tests all API endpoints using curl commands
- Automatically starts the API server if not running
- Validates response contents and formats
- Tests state-specific rules, including year-round enrollment states
- Verifies both single-contact and batch scheduling

For API testing, ensure:
1. The API server is running (or let the script start it for you)
2. The `jq` command is installed for JSON formatting

### Color-Coded Output Format

Both test scripts use color-coded output for better readability:
- **Green**: PASS indicators and successful test results 
- **Red**: FAIL indicators and error messages
- **Yellow**: Test names and section headers
- **Cyan**: Detailed test information
- **Magenta**: Expected values in verbose mode
- **Blue**: Actual values in verbose mode

In verbose mode, they provide additional information:
- Side-by-side comparison of expected vs. actual values
- Detailed explanation of test conditions
- Complete test output for failed tests
- Summary of all tests run

This makes it easier to quickly identify issues when tests fail and understand what's being tested.

## Test Coverage

The `test_email_rules.nim` file contains various test scenarios that validate compliance with the email scheduling rules, including:

### Basic Email Types
- Birthday emails (14 days before birthday)
- Effective date emails (30 days before effective date)
- AEP emails (third week of August for single contacts)

### Email Distribution Rules
- AEP distribution across four weeks for multiple contacts
- 60-day exclusion window between emails
- State-specific rule windows
- Post-rule window emails

### Special Cases
- Year-round enrollment states (no emails)
- Emails crossing year boundaries
- Emails suppressed due to exclusion rules
- Uneven distribution of contacts for batch AEP emails

## Expected Workflow

The tests verify that:
1. The correct email types are scheduled based on contact information
2. Emails are scheduled on the correct dates
3. Exclusion windows are properly enforced
4. State rules are correctly applied
5. Batch distribution works as expected 