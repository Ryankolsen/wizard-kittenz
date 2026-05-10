---
name: do-work
description: "Execute a unit of work end-to-end: plan, implement, validate with GUT tests, then commit. Use when user wants to do work, build a feature, fix a bug, or implement a phase from a plan."
---

# Do Work

Execute a complete unit of work: plan it, build it, validate it, commit it.

## Workflow

### 1. Understand the task

Read any referenced plan or PRD. Explore the codebase to understand the relevant files, patterns, and conventions. If the task is ambiguous, ask the user to clarify scope before proceeding.

### 2. Plan the implementation (optional)

If the task has not already been planned, create a plan for it.

### 3. Implement

**For gameplay/logic code (GDScript)**: use strict red/green/refactor, one GUT test at a time in a tracer-bullet style. This means literally one test → one implementation change → verified green, before writing the next test.

#### Tracer bullet test order

Order tests from thinnest vertical slice to widest:

1. **Slice 1 — Thinnest end-to-end:** Prove the core wiring works. One assertion on the most essential outcome. Write this test, run it (red), write the minimum implementation to make it pass (green).
2. **Slice 2 — Widen the content:** Verify the details are correct (field values, signal payloads). Write this test, run it (red), adjust implementation if needed (green).
3. **Slice 3+ — Widen further:** Add one new dimension per test — error cases, edge cases, different inputs. Each time: write one test, run it (red), implement (green).

#### Red/green cycle discipline

- **Write exactly ONE test.** Do NOT write multiple tests before running them.
- **Run the GUT suite** after writing each test to confirm it fails (red).
- **Write the minimum code** to make that one test pass (green).
- **Run the GUT suite again** to confirm it passes.
- **Then and only then**, write the next test.
- After all slices are done, refactor if needed while keeping tests green.

#### What NOT to do

- Do not write all tests upfront and then implement everything at once — this is batch, not tracer bullet.
- Do not write a test that asserts on 5 different things when you haven't proven the basic wiring works yet.
- Do not skip running the test between red and green — the failing run is what proves the test has value.

**For scene/UI code**: implement directly without TDD.

### 4. Validate

Run the GUT suite and fix any failures. Repeat until all tests pass cleanly.

```
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=gut_config.json
```

Tests live in `tests/unit/test_*.gd`. New tests go there following the same prefix convention.

### 5. Commit

Once all GUT tests pass, commit the work.