# CLAUDE.md - Assistant Guidelines for n_email_schedule

## Build & Run Commands
- Install dependencies: `nimble install`
- Compile: `nim c src/n_email_schedule.nim`
- Compile and run: `nim c -r src/n_email_schedule.nim`
- Recommended run method: `./run.sh [options]`
- Run options: `--dry-run`, `--verbose`, `--quiet`

## Test Commands
- Run all tests: `./run_tests.sh --verbose`
- Run single test: `./run_tests.sh -v "Test Name"`

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

## Claude-Optimized Repository Structure
This repository includes Claude-specific metadata to enhance AI assistance:

- `.claude/metadata/`: Component dependency graphs and codebase structure
- `.claude/code_index/`: Function call graphs and semantic relationships
- `.claude/debug_history/`: Logs of previous debugging sessions and solutions
- `.claude/patterns/`: Implementation patterns with examples (async, Result types)
- `.claude/cheatsheets/`: Quick reference guides for code patterns
- `.claude/qa/`: Database of previously solved problems
- `.claude/docs/`: Model-friendly component documentation
- `.claude/delta/`: Semantic change logs for major implementations
- `.claude/feedback/`: Performance metrics and optimization suggestions

Key memory anchors in code:
- `MEMORY_ANCHOR: EXCLUSION-WINDOW-FUNCTION`: In scheduler.nim - Calculates exclusion windows with caching
- `MEMORY_ANCHOR: PARALLEL-BATCH-PROCESSING`: In scheduler.nim - Processes multiple contacts in parallel
- `MEMORY_ANCHOR: PARALLEL-SINGLE-CONTACT`: In scheduler.nim - Processes email types in parallel

## Maintaining Claude-Optimized Structure

When making significant changes to the codebase, please help maintain the Claude-optimized structure:

1. **After Adding New Components**:
   - Update `.claude/metadata/component_graph.json` with the new component
   - Add relevant memory anchors to key functions with `## MEMORY_ANCHOR: COMPONENT-NAME`

2. **After Fixing Bugs**:
   - Add an entry to `.claude/debug_history/` with the error and solution
   - Use format: `bug_name_error.json` and follow existing structure

3. **After Adding New Patterns**:
   - Document in `.claude/patterns/` or update existing pattern files
   - Add examples from the actual codebase

4. **After Performance Improvements**:
   - Update `.claude/feedback/performance_metrics.json` with new measurements
   - Document any new optimization techniques

5. **After Major Features**:
   - Add a new file to `.claude/delta/` describing the semantic changes
   - Update `.claude/docs/` for affected components

6. **When Solving Difficult Problems**:
   - Add to `.claude/qa/solved_problems.json` for future reference
   - Include error messages, root causes, and solutions

7. **Updating Function Indexes**:
   - After significant API changes, update `.claude/code_index/function_calls.json`
   - Focus on documenting exported functions and their relationships

8. **Memory Anchor Conventions**:
   - Use ALL-CAPS for memory anchor names
   - Keep names short but descriptive 
   - Place at the start of key functions and critical code blocks

By maintaining these files, you'll ensure Claude can provide increasingly better assistance over time. When asking Claude for help, remember to reference the relevant directories to get enhanced context.
