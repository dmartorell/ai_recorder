---
description: Implement one task from the active implementation plan
argument-hint: "[task number or instructions]"
---
Read `AGENTS.md`, the approved design in `docs/plans/`, and the active implementation plan in `docs/` completely before editing.

Implement only ${ARGUMENTS:-the first unchecked task} from the implementation plan.

Requirements:
- Inspect existing code and conventions before editing.
- Follow the plan's file boundaries and test-first sequence.
- Preserve all product invariants in `AGENTS.md`.
- Run the task's narrow tests and the full affected test suite.
- Report changed files, commands run, results, and remaining risks.
- Do not start another task.
- Do not create a git commit without explicit user approval.

If no implementation plan exists or the requested task is ambiguous, stop and identify exactly what is missing.
