# CLAUDE.md - Assistant Guidelines for n_email_schedule

## Build & Run Commands
- Install dependencies: `nimble install`
- Compile: `nim c src/n_email_schedule.nim`
- Compile and run: `nim c -r src/n_email_schedule.nim`
- Recommended run method: `./run.sh [options]`
- Run options: `--dry-run`, `--verbose`, `--quiet`

## Test Commands
- Run all tests: `nim c -r tests/test_scheduler.nim`
- Run single test: `nim c -r tests/test_scheduler.nim "Test Name"`

## Code Style Guidelines
- Types: PascalCase (e.g., `Contact`, `Email`)
- Variables/Functions: camelCase (e.g., `firstName`, `getStateRule`)
- Exports: Mark with `*` suffix (e.g., `Email*`)
- Indentation: 2 spaces
- Imports: Group at top, stdlib first, then local modules
- Error handling: Use try-except blocks with fallbacks
- Function signatures: Include return types and `{.async.}` where needed
- File structure: Follow modular organization as in README
- Documentation: Include comments for complex logic
- Async: Use `asyncdispatch` for I/O operations, mark with `{.async.}`