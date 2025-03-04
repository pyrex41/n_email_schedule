#!/bin/sh

# Compile and run the direct scheduler tests
echo "Compiling and running Email Rules tests..."

# Check for nim in common locations
if command -v nim >/dev/null 2>&1; then
  NIM_CMD="nim"
elif command -v /Users/reuben/.choosenim/toolchains/nim-2.2.2/bin/nim >/dev/null 2>&1; then
  NIM_CMD="/Users/reuben/.choosenim/toolchains/nim-2.2.2/bin/nim"
elif command -v /usr/local/bin/nim >/dev/null 2>&1; then
  NIM_CMD="/usr/local/bin/nim"
elif command -v "$HOME/.choosenim/toolchains/nim-2.2.2/bin/nim" >/dev/null 2>&1; then
  NIM_CMD="$HOME/.choosenim/toolchains/nim-2.2.2/bin/nim"
else
  echo "Error: Nim compiler not found"
  echo "Please ensure nim is installed and in your PATH"
  exit 1
fi

# Run the tests
"$NIM_CMD" c -r tests/test_email_rules.nim

echo "\nTests completed."

# Note: The following test is currently not working due to missing dependencies
# nim c -r tests/test_scheduler.nim 