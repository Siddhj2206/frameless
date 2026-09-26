# Mission: BuildStream for frameless

## Why

I maintain frameless, a BuildStream-based template for building OS images — to
dakota what finpilot is to Bluefin. I want to build and maintain it confidently
rather than depending on agents or guesswork.

## Success looks like

- Author and edit `project.conf` and `.bst` elements without hand-holding
- Read a build graph (`bst show`) and reason about cache keys and what will rebuild
- Debug a failed `bst build` down to the element and the cause
- Make frameless's architecture decisions and explain the trade-offs
- Explain BuildStream to someone else well enough to onboard them

## Constraints

- Learning happens alongside the work, not as a separate course
- Research lives in `docs/research/`; learning artifacts in `docs/learning/`
- Prefer primary sources (`docs.buildstream.build`, `apache/buildstream`)
- Everything lands on `main` — no separate branches

## Out of scope

- Becoming a BuildStream core contributor (revisit if it becomes a goal)
- freedesktop-sdk / gnome-build-meta internals beyond what frameless needs
- BuildStream 1
