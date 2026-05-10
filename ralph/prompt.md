# GITHUB REPO

The GitHub repo name is provided at start of context. You MUST use `--repo <repo>` with ALL `gh` commands (issue view, issue close, issue comment, etc.). Never run `gh` commands without `--repo` — the sandbox may resolve to the wrong repository otherwise.

# ISSUES

GitHub issues are provided at start of context. Parse it to get open issues with their bodies and comments.

You will work on the AFK issues only, not the HITL ones.

You've also been passed a file containing the last few commits. Review these to understand what work has been done.

If all AFK tasks are complete, output <promise>NO MORE TASKS</promise>.

# TASK SELECTION

Pick the next task. Prioritize tasks in this order:

1. Critical bugfixes
2. Development infrastructure

Getting development infrastructure like tests and types and dev scripts ready is an important precursor to building features.

3. Tracer bullets for new features

Tracer bullets are small slices of functionality that go through all layers of the system, allowing you to test and validate your approach early. This helps in identifying potential issues and ensures that the overall architecture is sound before investing significant time in development.

TL;DR - build a tiny, end-to-end slice of the feature first, then expand it out.

4. Polish and quick wins
5. Refactors

# EXPLORATION

Explore the repo.

# IMPLEMENTATION

Complete the task.

# FEEDBACK LOOPS

Before committing, run the feedback loops:

- `godot --headless -s addons/gut/gut_cmdln.gd -gconfig=gut_config.json` to run the GUT test suite

# COMMIT

Make a git commit. The commit message must:

1. Include key decisions made
2. Include files changed
3. Blockers or notes for next iteration

# THE ISSUE

If the task is complete, close the original GitHub issue using `gh issue close <number> --repo <repo>`.

If the task is not complete, leave a comment on the GitHub issue using `gh issue comment <number> --repo <repo>` with what was done.

# FINAL RULES

ONLY WORK ON A SINGLE TASK.
