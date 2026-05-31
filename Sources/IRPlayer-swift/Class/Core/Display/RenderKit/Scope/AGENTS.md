# AGENTS.md — Scope

Viewport scope definitions that define bounds for 2D and 3D rendering.

## Files

| File                  | Purpose                                  |
|-----------------------|------------------------------------------|
| `IRGLScope2D.swift`   | 2D viewport bounds (pan/zoom limits)     |
| `IRGLScope3D.swift`   | 3D viewport bounds (rotation/FOV limits) |

## Agent Notes

- Scopes enforce viewport limits — they prevent over-scrolling and invalid zoom levels.
- Consumed by transform controllers and bounce controllers.
- Tests: `IRGLScopeTests.swift`.
