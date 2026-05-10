---
name: prd-to-plan
description: Turn a PRD into a multi-phase implementation plan using tracer-bullet vertical slices, submitted as a GitHub issue. Use when user wants to break down a PRD, create an implementation plan, plan phases from a PRD, or mentions "tracer bullets".
---

# PRD to Plan

Break a PRD into a phased implementation plan using vertical slices (tracer bullets). Output is submitted as a **GitHub issue** linked back to the source PRD issue.

## Process

### 1. Confirm the PRD is in context

The PRD should already be in the conversation. If it isn't, ask the user to paste it or point you to the file.

### 2. Explore the codebase

If you have not already explored the codebase, do so to understand the current scene structure, GDScript classes, autoloads, and Nakama integration points.

### 3. Identify durable architectural decisions

Before slicing, identify high-level decisions that are unlikely to change throughout implementation:

- Scene entry points and root scene structure
- Autoload singletons and their responsibilities
- Key GDScript classes / Resource shapes
- Signal contracts (which signals exist, what data they carry)
- Nakama storage key layout and auth approach
- Third-party service boundaries (Nakama, Google Play Billing)

These go in the plan header so every phase can reference them.

### 4. Draft vertical slices

Break the PRD into **tracer bullet** phases. Each phase is a thin vertical slice that cuts through ALL layers end-to-end (GUT test → GDScript logic → scene wiring), NOT a horizontal slice of one layer.

**Every phase MUST follow red-green-refactor order:**
1. **Red** — Write failing GUT tests first that define the behavior of the new slice
2. **Green** — Implement the minimum GDScript code to make those tests pass
3. **Refactor** — Clean up without changing behavior, keeping tests green

This is non-negotiable. Tests are never written after the implementation.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (GUT test, GDScript logic, scene/signal wiring)
- Each slice begins with failing GUT tests (red) before any production code is written
- Tests define the behavior contract for the slice — implementation follows the tests
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones — a slice that takes more than a few hours is too thick
- Do NOT include specific node paths or implementation details that are likely to change
- DO include durable decisions: scene names, autoload names, signal names, Nakama collection keys
- The first slice should be the thinnest possible end-to-end path ("walking skeleton") — just enough to prove all layers connect
</vertical-slice-rules>

### 5. Quiz the user

Present the proposed breakdown as a numbered list. For each phase show:

- **Title**: short descriptive name
- **Red step**: what failing GUT tests will be written first
- **Green step**: what implementation makes those tests pass
- **User stories covered**: which user stories from the PRD this addresses

Ask the user:

- Does the red-green-refactor ordering feel right for each phase?
- Does the granularity feel right? (too coarse / too fine)
- Should any phases be merged or split further?

Iterate until the user approves the breakdown.

### 6. Submit the plan as a GitHub issue

Submit the plan as a GitHub issue using `gh issue create --repo Ryankolsen/wizard-kittenz`. Title the issue `Plan: {Feature Name}`. Link back to the source PRD issue in the body. Use the template below.

<plan-template>
# Plan: {Feature Name}

> Source PRD: {brief identifier or link}

## Architectural decisions

Durable decisions that apply across all phases:

- **Scene structure**: ...
- **Autoloads**: ...
- **Key classes / Resources**: ...
- **Signal contracts**: ...
- **Nakama storage keys**: ...
- (add/remove sections as appropriate)

---

## Phase 1: {Title}

**User stories**: {list from PRD}

### Red — Write failing GUT tests first

Describe the specific failing tests to write before touching production code. Tests go in `tests/unit/test_*.gd` and ordered from thinnest to widest:

1. {Test description — what behavior it asserts}
2. {Test description}
3. {Test description}

### Green — Implement to pass

A concise description of the minimum GDScript implementation needed to make the tests above pass. Describe end-to-end behavior, not layer-by-layer details.

### Refactor

Note any cleanup or structural improvements to make once the tests are green, without changing behavior.

### Acceptance criteria

- [ ] All GUT tests from the Red step are passing
- [ ] Criterion 2
- [ ] Criterion 3

---

## Phase 2: {Title}

**User stories**: {list from PRD}

### Red — Write failing GUT tests first

1. {Test description}
2. {Test description}

### Green — Implement to pass

...

### Refactor

...

### Acceptance criteria

- [ ] All GUT tests from the Red step are passing
- [ ] ...

(Repeat for each phase)
</plan-template>
