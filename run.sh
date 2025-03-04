#!/bin/bash

# Run Medicare Email Scheduler

# Set path to nim compiler
NIM_PATH="/Users/reuben/.nimble/bin/nim"

# Check if nim compiler exists at specified path
if [ ! -f "$NIM_PATH" ]; then
    echo "Error: nim compiler not found at $NIM_PATH"
    echo "Please update the NIM_PATH variable in this script with the correct path"
    exit 1
fi

# Parse arguments
DRY_RUN=false
VERBOSE=false
QUIET=false
RELEASE=false
API_MODE=false
API_PORT=5000
ARGS=""
NIM_ARGS=""

for arg in "$@"; do
  case $arg in
    --dry-run|-d)
      DRY_RUN=true
      ARGS="$ARGS -d"
      ;;
    --verbose|-v)
      VERBOSE=true
      ARGS="$ARGS -v"
      ;;
    --quiet|-q)
      QUIET=true
      ARGS="$ARGS -q"
      ;;
    --release|-r)
      RELEASE=true
      NIM_ARGS="$NIM_ARGS -d:release"
      ;;
    --api|-a)
      API_MODE=true
      ARGS="$ARGS -a"
      NIM_ARGS="$NIM_ARGS -d:withApi"
      ;;
    --port=*)
      API_PORT="${arg#*=}"
      ARGS="$ARGS -p $API_PORT"
      ;;
    --help|-h)
      echo "Medicare Email Scheduler"
      echo "Usage: run.sh [options]"
      echo "Options:"
      echo "  -d, --dry-run      Run without saving emails to database"
      echo "  -v, --verbose      Enable verbose logging"
      echo "  -q, --quiet        Reduce log output"
      echo "  -r, --release      Build with optimizations (release mode)"
      echo "  -a, --api          Run as API server"
      echo "  --port=PORT        Specify API server port (default: 5000)"
      echo "  -h, --help         Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Check if .env file exists (only if not in dry-run mode)
if [ "$DRY_RUN" = false ] && [ ! -f .env ]; then
    echo "Warning: .env file not found. Creating from sample."
    if [ -f .env.sample ]; then
        cp .env.sample .env
        echo "Created .env from .env.sample. Please edit with your credentials."
    else
        echo "Error: .env.sample not found. Please create .env file manually."
        exit 1
    fi
fi

# Check for Turso auth token (only if not in dry-run mode)
if [ "$DRY_RUN" = false ]; then
    AUTH_TOKEN=$(grep TURSO_AUTH_TOKEN .env | cut -d= -f2)
    if [[ "$AUTH_TOKEN" == "your_turso_auth_token" ]]; then
        echo "Error: Please update your Turso auth token in .env file"
        echo "You can get a token with: turso db tokens create medicare-portal"
        echo "Or run with --dry-run to test without a database connection"
        exit 1
    fi
fi

# Compile step
echo "Compiling Medicare Email Scheduler..."
if [ "$RELEASE" = true ]; then
    echo "Building in release mode with optimizations"
fi
if [ "$API_MODE" = true ]; then
    echo "Building with API server support on port $API_PORT"
fi
if [ "$DRY_RUN" = true ]; then
    echo "Dry run mode - no emails will be saved to the database"
fi

# Compile with specified options
"$NIM_PATH" c $NIM_ARGS src/n_email_schedule.nim
COMPILE_CODE=$?
if [ $COMPILE_CODE -ne 0 ]; then
    echo "Error: Compilation failed with code $COMPILE_CODE"
    exit $COMPILE_CODE
fi

# Run the application
echo "Running Medicare Email Scheduler..."
./src/n_email_schedule $ARGS
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "Error: Program exited with code $EXIT_CODE"
    exit $EXIT_CODE
else
    echo "Medicare Email Scheduler completed successfully"
fi 