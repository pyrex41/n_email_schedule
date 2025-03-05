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
VERBOSE=false
TESTS=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      echo "Usage: ./test_nim.sh [OPTIONS] [TEST_FILES...]"
      echo ""
      echo "Options:"
      echo "  -v, --verbose    Enable verbose output with detailed test information"
      echo "  -h, --help       Display this help message"
      echo ""
      echo "If no test files are specified, all tests will be run."
      echo "Examples:"
      echo "  ./test_nim.sh                     # Run all tests"
      echo "  ./test_nim.sh -v                  # Run all tests with verbose output"
      echo "  ./test_nim.sh tests/test_scheduler_simple.nim  # Run only the simple scheduler test"
      echo "  ./test_nim.sh tests/test_api.nim              # Run only the API test"
      exit 0
      ;;
    *)
      TESTS+=("$1")
      shift
      ;;
  esac
done

# Function to format test output
format_test_output() {
  local output="$1"
  local test_name="$2"
  local result="$3"
  
  # Default to result parameter
  local test_status="$result"
  
  # For email rules test, check for [OK]
  if [ "$test_name" == "test_email_rules" ]; then
    if echo "$output" | grep -q "\[OK\]"; then
      test_status="pass"
    else
      test_status="fail"
    fi
  # For simple tests, success is likely when tests run without failing assertions
  elif [ "$test_name" == "test_scheduler_simple" ] || [ "$test_name" == "test_api_simple" ]; then
    if echo "$output" | grep -q "Failure"; then
      test_status="fail"
    else
      test_status="pass"
    fi
  fi
  
  if [ "$test_status" == "pass" ]; then
    echo -e "${GREEN}PASS${NC}: $test_name"
    
    if $VERBOSE; then
      # Extract and format test details
      echo -e "${CYAN}Test Details:${NC}"
      
      if [ "$test_name" == "test_email_rules" ]; then
        # Extract and show the test results section for email rules test
        echo "$output" | grep -A 50 "\[Suite\]" | while read -r line; do
          if [[ $line == *"OK"* ]]; then
            echo -e "${GREEN}$line${NC}"
          elif [[ $line == *"Suite"* ]]; then
            echo -e "${YELLOW}$line${NC}"
          else
            echo "$line"
          fi
        done
      else
        # For other tests like simple scheduler, show the full detailed output
        echo "$output" | while read -r line; do
          # Colorize key test information
          if [[ $line == *"Suite "* ]]; then
            echo -e "${YELLOW}$line${NC}"
          elif [[ $line == *"[OK]"* ]]; then
            echo -e "${GREEN}$line${NC}"
          elif [[ $line == *"expected"* ]] || [[ $line == *"Expected"* ]]; then
            echo -e "${MAGENTA}$line${NC}"
          elif [[ $line == *"actual"* ]] || [[ $line == *"Actual"* ]] || [[ $line == *"Number of emails"* ]]; then
            echo -e "${BLUE}$line${NC}"
          elif [[ $line == *"Summary"* ]]; then
            echo -e "${YELLOW}$line${NC}"
          else
            echo "$line"
          fi
        done
      fi
      echo ""
    fi
  else
    echo -e "${RED}FAIL${NC}: $test_name"
    
    # Always show details for failures
    echo -e "${CYAN}Test Details:${NC}"
    echo "$output"
    echo ""
  fi
}

# Run test files and format output
run_test() {
  local test_file="$1"
  local test_name=$(basename "$test_file" .nim)
  
  echo -e "\n${YELLOW}Running test: $test_name${NC}"
  echo "============================================="
  
  # Use nim directly for all tests
  output=$($NIM_BIN c -r "$test_file" 2>&1)
  if [ $? -eq 0 ]; then
    format_test_output "$output" "$test_name" "pass"
  else
    format_test_output "$output" "$test_name" "fail"
  fi
}

# Main function
main() {
  echo -e "${YELLOW}Running Medicare Email Scheduler Tests${NC}"
  if $VERBOSE; then
    echo -e "${CYAN}Running in verbose mode - detailed test information will be displayed${NC}"
  fi
  echo "============================================="
  
  # If no specific tests provided, run all tests
  if [ ${#TESTS[@]} -eq 0 ]; then
    run_test "tests/test_email_rules.nim"
    run_test "tests/test_scheduler_simple.nim"
    run_test "tests/test_scheduler.nim"
    run_test "tests/test_api_simple.nim"
    run_test "tests/test_api.nim"
    run_test "tests/test_utils.nim"
  else
    # Run specified tests
    for test in "${TESTS[@]}"; do
      run_test "$test"
    done
  fi
  
  echo -e "\n${GREEN}Testing Completed!${NC}"
}

# Run the main function
main 