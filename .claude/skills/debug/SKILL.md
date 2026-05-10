---
name: debug
description: Systematically debug Godot/GDScript bugs using code inspection, targeted logging, and GUT regression tests. Use when the user reports a visual glitch, interaction bug, or unexpected behavior and wants to find and fix the root cause. Covers node lifecycle issues, signal timing bugs, null reference errors, state machine problems, and scene tree quirks.
---

# Debug

Diagnose a bug systematically: read the code, form a hypothesis, instrument if needed, fix, then lock it in with a GUT regression test.

## Workflow

### 1. Understand the bug

Collect from the user:
- What they expected vs. what actually happened
- Reproduction steps (which scene, which action)
- Any error messages from the Godot debugger output

### 2. Read the relevant code

Find and read the script(s) involved. Look for:
- Null node references — accessing a node before `_ready()` fires or after it's been freed
- Signal timing — `connect()` called after `emit()`, or connected to wrong target
- Wrong lifecycle hook — using `_process()` instead of `_physics_process()` for physics
- Autoload access before the singleton is ready
- State that gets reset when a node re-enters the scene tree (`_ready()` fires again)

### 3. Form a hypothesis before adding logs

State the suspected root cause clearly. If code reading is sufficient to confirm it, skip straight to the fix. Only instrument when call order or timing is genuinely ambiguous.

**Examples where code alone is enough:**
- A node accessed at class level but used before the scene is loaded → move to `_ready()`
- A signal connected after the emitter already fired (one-shot timing issue)

**Examples where logging is needed:**
- Unclear which `_process()` call is clobbering state
- Uncertain whether a signal is connected at the point it fires

### 4. Add targeted logging (if needed)

Instrument at the key decision points — not everywhere. Use `print()` with a node prefix:

```gdscript
# Node lifecycle
print("[MyNode] _ready - hp=%d" % hp)
print("[MyNode] _enter_tree")

# Signal handlers
print("[MyNode] on_enemy_died - enemy=%s" % str(enemy))
print("[MyNode] on_attack_hit - damage=%d target=%s" % [damage, str(target)])

# State transitions
print("[MyNode] state -> %s (was %s)" % [new_state, current_state])

# Conditional branches
print("[MyNode] apply_damage - shield=%d, incoming=%d" % [shield, incoming])
```

Ask the user to run the scene, reproduce the bug, and paste the Godot output panel text.

### 5. Interpret the logs

Read the sequence carefully. Look for:
- A signal handler firing before the node is ready
- State being overwritten by a second `_ready()` call (node re-added to scene)
- An `await` resuming after a node was freed
- `get_node()` returning null because the path changed

State the root cause as a single sentence before writing the fix.

### 6. Fix

Make the minimal change. Common patterns:

| Symptom | Likely cause | Fix |
|---|---|---|
| `Invalid get index on base 'Nil'` on node access | Node not in tree or path wrong | Move access into `_ready()`, verify node path |
| Signal handler never runs | `connect()` called after `emit()`, or wrong callable | Verify `connect()` happens before emit; check method name |
| Physics behavior inconsistent | Physics code in `_process()` | Move to `_physics_process()` |
| Freed object crash after `await` | Node freed while coroutine suspended | Check `is_instance_valid()` after every `await` |
| State reset unexpectedly | Node removed/re-added, `_ready()` fires again | Guard `_ready()` with an `_initialized` flag |
| Autoload returns null | Accessed before scene tree is ready | Defer access to `_ready()` or use `call_deferred()` |

### 7. Write a GUT regression test

**Always write a test.** It must simulate the exact condition that caused the bug.

```gdscript
# Good: simulates the actual timing/state that triggered the bug
func test_signal_does_not_crash_after_node_freed():
    var emitter = MyEmitter.new()
    add_child_autofree(emitter)
    var receiver = MyReceiver.new()
    add_child_autofree(receiver)
    emitter.thing_happened.connect(receiver.on_thing_happened)
    receiver.queue_free()
    await get_tree().process_frame
    emitter.fire()  # must not crash
    assert_true(true, "no crash after receiver freed")

# Bad: tests the happy path but not the failure condition
func test_signal_works():
    var emitter = MyEmitter.new()
    emitter.fire()
    assert_eq(emitter.count, 1)
```

Test checklist:
- [ ] One test that would have caught this bug before the fix
- [ ] One test for the happy path (normal behavior still works)
- [ ] One test per edge case introduced by the fix

Run GUT and verify all pass:

```
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=gut_config.json
```

### 8. Remove logging and commit

Strip every `print()` added in step 4. Then commit with a message that covers:
1. What the symptom was
2. The root cause (one sentence)
3. What the fix does

```
Fix [node/script] [symptom]

Root cause: [one sentence].
Fix: [what changed and why].
Adds regression test for [specific behavior].
```
