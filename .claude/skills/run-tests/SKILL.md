---
name: run-tests
description: Run GUT unit tests for this Godot project. Use when the user wants to run tests, check if tests pass, verify a fix with tests, or mentions "gut", "run tests", "test suite", or asks to validate code with tests.
---

# Run Tests

## Godot binary

```
/Users/ryankolsen/Downloads/Godot.app/Contents/MacOS/Godot
```

## Reimport before testing a newly-added `class_name`

`res://.godot/global_script_class_cache.cfg` is where Godot registers every
script's `class_name` for global lookup. It is only refreshed by a project
scan — the editor does this automatically, but `-s addons/gut/gut_cmdln.gd`
headless test runs do not, so a `class_name` added (or renamed) since the
cache was last written resolves as an undeclared identifier even though the
script is syntactically correct. This bit issues #597/#598/#613: two already
green-verified test files silently contributed 0 tests for an entire session
because nobody's headless invocation refreshed the cache after `TutorialCatalog`
and `TutorialProgress` were added, and the resulting `Parse error` text never
made it into any grep pattern being used to judge the run.

The symptom is `Parse Error: Identifier "<ClassName>" not declared in the
current scope` where `<ClassName>` genuinely has `class_name <ClassName>` in
its script — this is a stale-cache problem, not a real GDScript error, so
"fix the GDScript error" (below) is the wrong response to it. Reimporting is
cheap and safe to run unconditionally before any test run that matters (a
gate check, a qa-verifier pass, a pre-commit hook run):

```bash
/Users/ryankolsen/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --import
```

## Run all tests

`gut_config.json` (repo root) holds GUT's directory config, but GUT only
auto-loads a file named `.gutconfig.json`. This repo's file is named
`gut_config.json`, so it must be passed explicitly with `-gconfig`, or GUT
errors with "You do not have any directories configured" and silently runs
zero tests. `-gexit` makes GUT exit when the run finishes instead of hanging
in the GUI.

```bash
GUT_LOG=$(mktemp -t gut_output)
/Users/ryankolsen/Downloads/Godot.app/Contents/MacOS/Godot \
  --headless --path . -s addons/gut/gut_cmdln.gd \
  -gconfig=res://gut_config.json -gexit 2>&1 \
  | tee "$GUT_LOG" \
  | grep -E "passed|failed|FAIL|Totals|directories configured"
grep -A 10 "^Totals" "$GUT_LOG"
```

Do not rely on `grep` alone to judge the run. A `grep` matching only
`passed|failed|FAIL|Totals` silently discards GUT's own fatal error text
(e.g. "You do not have any directories configured"), since that text matches
none of those patterns — producing empty grep output that reads as "no
failures" when the run never started at all. So keep the full log via `tee`
and confirm a `Totals` block with a real test count actually appears.

The two `grep` passes do different jobs and both are needed: the first pulls
per-script signal lines out of the stream, the second prints the `Totals`
block on its own. Do not merge them by adding `-A 10` to the first — that
would append ten lines of context to every one of the 258 `N/N passed`
lines. Keep the log in a per-run `mktemp` file rather than a fixed path, so
two runs sharing `/tmp` (say, parallel worktrees) cannot interleave into one
log or read each other's stale output.

## Run a single test file

Do **not** add `-gconfig=res://gut_config.json` here. `gut_config.json`
unconditionally sets `"dirs": ["res://tests/unit"]`, and GUT's config loader
always merges `opts.dirs` in alongside any `-gtest` script, so `-gconfig`
makes `-gtest` stop narrowing the run at all — you get the full suite
(all 258 scripts / 3394 tests) with no indication the scoping was lost.
Leaving `-gconfig` out keeps `-gtest` scoped to just the named file. `-gexit`
is still included so the process exits instead of hanging in the GUI.

This means a run with no `-gconfig` and no scripts configured any other way
is deliberately how GUT stays correctly scoped here — but it is also the
exact shape of the original zero-tests-look-green defect, so still confirm
a real, non-zero `Totals` block for just that one file (not an empty run and
not the full 3394). If GUT instead prints
"You do not have any directories configured", that means `-gtest` itself was
omitted or malformed, not that `-gconfig` should be added back.

```bash
GUT_LOG=$(mktemp -t gut_output)
/Users/ryankolsen/Downloads/Godot.app/Contents/MacOS/Godot \
  --headless --path . -s addons/gut/gut_cmdln.gd \
  -gexit \
  -gtest=res://tests/unit/test_foo.gd 2>&1 \
  | tee "$GUT_LOG" \
  | grep -E "passed|failed|FAIL|Totals|directories configured"
grep -A 10 "^Totals" "$GUT_LOG"
```

## Workflow

1. Run the relevant test file (or all tests if scope is unclear)
2. Read failing test names from `[FAIL]` lines
3. Fix the issue; re-run to confirm green
4. If a **parse error** blocks the file from loading, fix the GDScript error first — GUT silently skips files that don't parse
5. Before calling anything green, confirm a real, non-zero test count was reported (e.g. `Tests   3394` in the Totals block) — never accept an empty or missing Totals block as a pass

## Reading output

| Line pattern | Meaning |
|---|---|
| `10/10 passed` | All tests in file passed |
| `[Failed]: ...` | Specific assertion that failed |
| `---- N failing tests ----` | Summary count |
| `Parse error` + `does not extend GutTest` | GDScript syntax error in the file — fix it first |
| Empty output / no `Totals` block | The run failed to start (e.g. missing `-gconfig`) — this is **not** a pass and must never be read as green |
| `You do not have any directories configured` | The run never started — **the fix differs by command**. In *run all tests*, `-gconfig=res://gut_config.json` is missing. In *run a single test file*, `-gtest` is missing or malformed; do **not** add `-gconfig` there, it silently un-scopes the run to the full suite |

## Test file locations

All unit tests live in `res://tests/unit/`. File naming: `test_<subject>.gd`.

## Timeout

Add `--timeout 60000` (ms) to the Bash call for slow suites.
