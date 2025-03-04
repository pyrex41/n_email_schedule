#!/bin/sh

# This script is a simple wrapper around test_nim.sh
# It's kept for backward compatibility

echo "Running all Medicare Email Scheduler tests..."

# Run all tests using test_nim.sh
exec ./test_nim.sh "$@" 