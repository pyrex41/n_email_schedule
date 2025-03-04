#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

NIM_BIN="/Users/reuben/.choosenim/toolchains/nim-2.2.2/bin/nim"
API_PORT=5001
API_URL="http://localhost:$API_PORT"
VERBOSE=false

# Parse command line arguments
for arg in "$@"; do
  case $arg in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      echo "Usage: ./test_api.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -v, --verbose    Enable verbose output with detailed test information"
      echo "  -h, --help       Display this help message"
      exit 0
      ;;
  esac
done

# Function to print colored output
print_status() {
  local result=$1
  local message=$2
  local details=$3
  
  if [ $result -eq 0 ]; then
    echo -e "${GREEN}PASS${NC}: $message"
  else
    echo -e "${RED}FAIL${NC}: $message"
  fi
  
  if $VERBOSE && [ -n "$details" ]; then
    echo -e "${CYAN}$details${NC}"
  fi
}

# Function to show verbose comparison
verbose_compare() {
  local expected=$1
  local actual=$2
  local field=$3
  
  if $VERBOSE; then
    echo -e "  ${MAGENTA}EXPECTED${NC}: $field = $expected"
    echo -e "  ${BLUE}ACTUAL${NC}:   $field = $actual"
    echo ""
  fi
}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo -e "${RED}Error${NC}: jq is required but not installed. Please install jq to parse JSON responses."
  exit 1
fi

# Check if API server is running
check_server_running() {
  if lsof -i :$API_PORT &> /dev/null; then
    return 0
  else
    return 1
  fi
}

# Start API server if not running
start_server() {
  echo -e "${YELLOW}Starting API server...${NC}"
  $NIM_BIN c -r simple_api.nim &
  
  # Wait for server to start (up to 5 seconds)
  for i in {1..10}; do
    if check_server_running; then
      echo -e "${GREEN}API server started successfully.${NC}"
      sleep 1 # Give it a moment to initialize
      return 0
    fi
    sleep 0.5
  done
  
  echo -e "${RED}Failed to start API server.${NC}"
  return 1
}

# Setup: Ensure API server is running
if ! check_server_running; then
  start_server
  if [ $? -ne 0 ]; then
    exit 1
  fi
fi

echo -e "\n${YELLOW}Running Medicare Email Scheduler API Tests${NC}"
if $VERBOSE; then
  echo -e "${CYAN}Running in verbose mode - detailed test information will be displayed${NC}"
fi
echo "============================================="

# Test 1: Health endpoint
echo -e "\n${YELLOW}Test 1: Health endpoint${NC}"
HEALTH_RESPONSE=$(curl -s "$API_URL/health")
echo "Response: $HEALTH_RESPONSE"

STATUS=$(echo $HEALTH_RESPONSE | jq -r '.status')
echo $HEALTH_RESPONSE | jq -e '.status == "ok"' &> /dev/null
RESULT=$?
DETAILS=$(cat << EOF
Test: Health endpoint should return status "ok"
URL: $API_URL/health
Expected: status = "ok"
Actual: status = "$STATUS"
EOF
)
print_status $RESULT "Health endpoint should return status: ok" "$DETAILS"

# Test 2: API info endpoint
echo -e "\n${YELLOW}Test 2: API info endpoint${NC}"
INFO_RESPONSE=$(curl -s "$API_URL/api-info")
echo "Response: $INFO_RESPONSE"

API_NAME=$(echo $INFO_RESPONSE | jq -r '.name')
echo $INFO_RESPONSE | jq -e '.name == "Medicare Email Scheduler API"' &> /dev/null
RESULT=$?
DETAILS=$(cat << EOF
Test: API info should return correct API name
URL: $API_URL/api-info
Expected: name = "Medicare Email Scheduler API"
Actual: name = "$API_NAME"
EOF
)
print_status $RESULT "API info should return correct API name" "$DETAILS"

ROUTES_COUNT=$(echo $INFO_RESPONSE | jq '.routes | length')
echo $INFO_RESPONSE | jq -e '.routes | length >= 5' &> /dev/null
RESULT=$?
DETAILS=$(cat << EOF
Test: API info should list at least 5 routes
URL: $API_URL/api-info
Expected: routes.length >= 5
Actual: routes.length = $ROUTES_COUNT
Routes: $(echo $INFO_RESPONSE | jq -c '.routes')
EOF
)
print_status $RESULT "API info should list at least 5 routes" "$DETAILS"

# Test 3: Schedule emails for Texas contact (non-year-round state)
echo -e "\n${YELLOW}Test 3: Schedule emails for Texas contact${NC}"
TEXAS_RESPONSE=$(curl -s -X POST "$API_URL/schedule-emails" \
  -H "Content-Type: application/json" \
  -d '{
    "contact": {
      "id": 1,
      "firstName": "John",
      "lastName": "Doe",
      "email": "john@example.com",
      "currentCarrier": "Test Carrier",
      "planType": "Medicare",
      "effectiveDate": "2025-12-15",
      "birthDate": "1950-02-01",
      "tobaccoUser": false,
      "gender": "M",
      "state": "TX",
      "zipCode": "12345",
      "agentID": 1,
      "phoneNumber": "555-1234",
      "status": "Active"
    },
    "today": "2025-01-01"
  }')

echo "Response: $TEXAS_RESPONSE"
TX_EMAIL_COUNT=$(echo $TEXAS_RESPONSE | jq '.scheduledEmails | length')
echo $TEXAS_RESPONSE | jq -e '.scheduledEmails | length == 4' &> /dev/null
RESULT=$?
DETAILS=$(cat << EOF
Test: Texas contact should have 4 scheduled emails
URL: $API_URL/schedule-emails (POST)
Contact: State = TX, DOB = 1950-02-01, Effective = 2025-12-15
Expected: scheduledEmails.length = 4
Actual: scheduledEmails.length = $TX_EMAIL_COUNT
Emails: $(echo $TEXAS_RESPONSE | jq -c '.scheduledEmails[] | {type, scheduledAt, reason}')
EOF
)
print_status $RESULT "Texas contact should have 4 scheduled emails" "$DETAILS"

# Check for specific email types
# CarrierUpdate email
HAS_CARRIER_UPDATE=$(echo $TEXAS_RESPONSE | jq -r '.scheduledEmails[] | select(.type == "CarrierUpdate") | .type')
echo $TEXAS_RESPONSE | jq -e '.scheduledEmails[] | select(.type == "CarrierUpdate")' &> /dev/null
RESULT=$?
DETAILS=$(cat << EOF
Test: Texas contact should have a CarrierUpdate email
Expected: One email with type = "CarrierUpdate"
Actual: $(if [ -n "$HAS_CARRIER_UPDATE" ]; then echo "Found CarrierUpdate email"; else echo "No CarrierUpdate email found"; fi)
Details: $(echo $TEXAS_RESPONSE | jq -c '.scheduledEmails[] | select(.type == "CarrierUpdate")')
EOF
)
print_status $RESULT "Texas contact should have a CarrierUpdate email" "$DETAILS"

# AEP email
HAS_AEP=$(echo $TEXAS_RESPONSE | jq -r '.scheduledEmails[] | select(.type == "AEP") | .type')
echo $TEXAS_RESPONSE | jq -e '.scheduledEmails[] | select(.type == "AEP")' &> /dev/null
RESULT=$?
DETAILS=$(cat << EOF
Test: Texas contact should have an AEP email
Expected: One email with type = "AEP"
Actual: $(if [ -n "$HAS_AEP" ]; then echo "Found AEP email"; else echo "No AEP email found"; fi)
Details: $(echo $TEXAS_RESPONSE | jq -c '.scheduledEmails[] | select(.type == "AEP")')
EOF
)
print_status $RESULT "Texas contact should have an AEP email" "$DETAILS"

# Effective email
HAS_EFFECTIVE=$(echo $TEXAS_RESPONSE | jq -r '.scheduledEmails[] | select(.type == "Effective") | .type')
echo $TEXAS_RESPONSE | jq -e '.scheduledEmails[] | select(.type == "Effective")' &> /dev/null
RESULT=$?
DETAILS=$(cat << EOF
Test: Texas contact should have an Effective email
Expected: One email with type = "Effective"
Actual: $(if [ -n "$HAS_EFFECTIVE" ]; then echo "Found Effective email"; else echo "No Effective email found"; fi)
Details: $(echo $TEXAS_RESPONSE | jq -c '.scheduledEmails[] | select(.type == "Effective")')
EOF
)
print_status $RESULT "Texas contact should have an Effective email" "$DETAILS"

# Birthday email
HAS_BIRTHDAY=$(echo $TEXAS_RESPONSE | jq -r '.scheduledEmails[] | select(.type == "Birthday") | .type')
echo $TEXAS_RESPONSE | jq -e '.scheduledEmails[] | select(.type == "Birthday")' &> /dev/null
RESULT=$?
DETAILS=$(cat << EOF
Test: Texas contact should have a Birthday email
Expected: One email with type = "Birthday"
Actual: $(if [ -n "$HAS_BIRTHDAY" ]; then echo "Found Birthday email"; else echo "No Birthday email found"; fi)
Details: $(echo $TEXAS_RESPONSE | jq -c '.scheduledEmails[] | select(.type == "Birthday")')
EOF
)
print_status $RESULT "Texas contact should have a Birthday email" "$DETAILS"

# Test 4: Schedule emails for Connecticut contact (year-round state)
echo -e "\n${YELLOW}Test 4: Schedule emails for Connecticut contact${NC}"
CT_RESPONSE=$(curl -s -X POST "$API_URL/schedule-emails" \
  -H "Content-Type: application/json" \
  -d '{
    "contact": {
      "id": 2,
      "firstName": "Jane",
      "lastName": "Smith",
      "email": "jane@example.com",
      "currentCarrier": "Another Carrier",
      "planType": "Medicare",
      "effectiveDate": "2025-12-15",
      "birthDate": "1950-02-01",
      "tobaccoUser": false,
      "gender": "F",
      "state": "CT",
      "zipCode": "54321",
      "agentID": 1,
      "phoneNumber": "555-5678",
      "status": "Active"
    },
    "today": "2025-01-01"
  }')

echo "Response: $CT_RESPONSE"
CT_EMAIL_COUNT=$(echo $CT_RESPONSE | jq '.scheduledEmails | length')
echo $CT_RESPONSE | jq -e '.scheduledEmails | length == 0' &> /dev/null
RESULT=$?
DETAILS=$(cat << EOF
Test: Connecticut contact should have 0 scheduled emails (year-round enrollment state)
URL: $API_URL/schedule-emails (POST)
Contact: State = CT, DOB = 1950-02-01, Effective = 2025-12-15
Expected: scheduledEmails.length = 0
Actual: scheduledEmails.length = $CT_EMAIL_COUNT
Emails: $(echo $CT_RESPONSE | jq -c '.scheduledEmails')
EOF
)
print_status $RESULT "Connecticut contact should have 0 scheduled emails" "$DETAILS"

# Test 5: Batch scheduling for multiple contacts
echo -e "\n${YELLOW}Test 5: Batch scheduling for multiple contacts${NC}"
BATCH_RESPONSE=$(curl -s -X POST "$API_URL/schedule-emails/batch" \
  -H "Content-Type: application/json" \
  -d '{
    "contacts": [
      {
        "id": 1,
        "firstName": "John",
        "lastName": "Doe",
        "email": "john@example.com",
        "currentCarrier": "Test Carrier",
        "planType": "Medicare",
        "effectiveDate": "2025-12-15",
        "birthDate": "1950-02-01",
        "tobaccoUser": false,
        "gender": "M",
        "state": "TX",
        "zipCode": "12345",
        "agentID": 1,
        "phoneNumber": "555-1234",
        "status": "Active"
      },
      {
        "id": 2,
        "firstName": "Jane",
        "lastName": "Smith",
        "email": "jane@example.com",
        "currentCarrier": "Another Carrier",
        "planType": "Medicare",
        "effectiveDate": "2025-12-15",
        "birthDate": "1950-02-01",
        "tobaccoUser": false,
        "gender": "F",
        "state": "CT",
        "zipCode": "54321",
        "agentID": 1,
        "phoneNumber": "555-5678",
        "status": "Active"
      }
    ],
    "today": "2025-01-01"
  }')

echo "Response: $BATCH_RESPONSE"
# Check if we have 2 contacts in results
BATCH_RESULTS_COUNT=$(echo $BATCH_RESPONSE | jq '.results | length')
echo $BATCH_RESPONSE | jq -e '.results | length == 2' &> /dev/null
RESULT=$?
DETAILS=$(cat << EOF
Test: Batch response should contain results for 2 contacts
URL: $API_URL/schedule-emails/batch (POST)
Contacts: 2 contacts (TX and CT)
Expected: results.length = 2
Actual: results.length = $BATCH_RESULTS_COUNT
Results: $(echo $BATCH_RESPONSE | jq -c '.results[] | {contactId, emailCount: .scheduledEmails | length}')
EOF
)
print_status $RESULT "Batch response should contain results for 2 contacts" "$DETAILS"

# Check Texas contact in batch (should have emails)
TX_BATCH_EMAIL_COUNT=$(echo $BATCH_RESPONSE | jq '.results[] | select(.contactId == 1) | .scheduledEmails | length')
echo $BATCH_RESPONSE | jq -e '.results[] | select(.contactId == 1) | .scheduledEmails | length > 0' &> /dev/null
RESULT=$?
DETAILS=$(cat << EOF
Test: Texas contact in batch should have scheduled emails
URL: $API_URL/schedule-emails/batch (POST)
Contact: ID = 1, State = TX
Expected: scheduledEmails.length > 0
Actual: scheduledEmails.length = $TX_BATCH_EMAIL_COUNT
Emails: $(echo $BATCH_RESPONSE | jq -c '.results[] | select(.contactId == 1) | .scheduledEmails[] | {type, scheduledAt}')
EOF
)
print_status $RESULT "Texas contact in batch should have scheduled emails" "$DETAILS"

# Check Connecticut contact in batch (should have no emails)
CT_BATCH_EMAIL_COUNT=$(echo $BATCH_RESPONSE | jq '.results[] | select(.contactId == 2) | .scheduledEmails | length')
echo $BATCH_RESPONSE | jq -e '.results[] | select(.contactId == 2) | .scheduledEmails | length == 0' &> /dev/null
RESULT=$?
DETAILS=$(cat << EOF
Test: Connecticut contact in batch should have 0 scheduled emails
URL: $API_URL/schedule-emails/batch (POST)
Contact: ID = 2, State = CT
Expected: scheduledEmails.length = 0
Actual: scheduledEmails.length = $CT_BATCH_EMAIL_COUNT
EOF
)
print_status $RESULT "Connecticut contact in batch should have 0 scheduled emails" "$DETAILS"

# Test 6: Add a Year-Round state with a different state code to verify it's not just CT-specific
echo -e "\n${YELLOW}Test 6: Schedule emails for Massachusetts contact (another year-round state)${NC}"
MA_RESPONSE=$(curl -s -X POST "$API_URL/schedule-emails" \
  -H "Content-Type: application/json" \
  -d '{
    "contact": {
      "id": 3,
      "firstName": "Mark",
      "lastName": "Johnson",
      "email": "mark@example.com",
      "currentCarrier": "Mass Carrier",
      "planType": "Medicare",
      "effectiveDate": "2025-10-15",
      "birthDate": "1955-03-15",
      "tobaccoUser": false,
      "gender": "M",
      "state": "MA",
      "zipCode": "02108",
      "agentID": 1,
      "phoneNumber": "555-8765",
      "status": "Active"
    },
    "today": "2025-01-01"
  }')

echo "Response: $MA_RESPONSE"
MA_EMAIL_COUNT=$(echo $MA_RESPONSE | jq '.scheduledEmails | length')
echo $MA_RESPONSE | jq -e '.scheduledEmails | length == 0' &> /dev/null
RESULT=$?
DETAILS=$(cat << EOF
Test: Massachusetts contact should have 0 scheduled emails (year-round enrollment state)
URL: $API_URL/schedule-emails (POST)
Contact: State = MA, DOB = 1955-03-15, Effective = 2025-10-15
Expected: scheduledEmails.length = 0
Actual: scheduledEmails.length = $MA_EMAIL_COUNT
Emails: $(echo $MA_RESPONSE | jq -c '.scheduledEmails')
EOF
)
print_status $RESULT "Massachusetts contact should have 0 scheduled emails" "$DETAILS"

echo -e "\n${GREEN}API Testing Completed!${NC}"
echo "=============================================" 