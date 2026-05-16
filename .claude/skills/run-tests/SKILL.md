---
name: run-tests
description: Run GUT unit tests for this Godot project. Use when the user wants to run tests, check if tests pass, verify a fix with tests, or mentions "gut", "run tests", "test suite", or asks to validate code with tests.
---

# Run Tests

## Godot binary

```
/Users/ryankolsen/Downloads/Godot.app/Contents/MacOS/Godot
```

## Run all tests

```bash
/Users/ryankolsen/Downloads/Godot.app/Contents/MacOS/Godot \
  --headless --path . -s addons/gut/gut_cmdln.gd 2>&1 \
  | grep -E "passed|failed|FAIL|Totals"
```

## Run a single test file

```bash
/Users/ryankolsen/Downloads/Godot.app/Contents/MacOS/Godot \
  --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_foo.gd 2>&1 \
  | grep -E "passed|failed|FAIL|Totals"
```

## Workflow

1. Run the relevant test file (or all tests if scope is unclear)
2. Read failing test names from `[FAIL]` lines
3. Fix the issue; re-run to confirm green
4. If a **parse error** blocks the file from loading, fix the GDScript error first — GUT silently skips files that don't parse

## Reading output

| Line pattern | Meaning |
|---|---|
| `10/10 passed` | All tests in file passed |
| `[Failed]: ...` | Specific assertion that failed |
| `---- N failing tests ----` | Summary count |
| `Parse error` + `does not extend GutTest` | GDScript syntax error in the file — fix it first |

## Test file locations

All unit tests live in `res://tests/unit/`. File naming: `test_<subject>.gd`.

## Timeout

Add `--timeout 60000` (ms) to the Bash call for slow suites.
