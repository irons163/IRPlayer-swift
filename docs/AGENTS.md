# AGENTS.md — docs

Documentation directory for design specifications and implementation plans.

## Structure

- `superpowers/specs/` — Design intent documents: goals, non-goals, acceptance criteria.
- `superpowers/plans/` — Executable step-by-step implementation plans with validation commands.

## Current Documents

| Document | Path |
|----------|------|
| Lifecycle Policy Design | `superpowers/specs/2026-05-26-player-lifecycle-policy-design.md` |
| Lifecycle Policy Plan   | `superpowers/plans/2026-05-26-player-lifecycle-policy.md`        |

## Agent Workflow

1. **Read the spec first** — understand boundaries, goals, and non-goals.
2. **Follow the plan** — execute tasks in order with small diffs.
3. **Run listed tests** — validate before broad test runs.
4. **Report status** — state what was completed and what remains.

## Agent Notes

- New features should have a matching spec + plan pair before implementation begins.
- File naming convention: `YYYY-MM-DD-<feature-name>.md`.
- Specs define *what* and *why*; plans define *how* and *what to validate*.
