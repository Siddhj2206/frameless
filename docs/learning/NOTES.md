# Teaching Notes

Preferences and working notes for the learning track. Captured so future
sessions don't have to re-ask.

## Preferences

- **Learn as we go.** Learning is tied to the wayfinder map: each resolved
  ticket emits a learning record, and a durable concept earns a reference doc
  and a lesson.
- **Markdown lessons**, not HTML (chosen over the teach skill's default for repo
  consistency and diffability).
- **Short and tied to the mission.** A lesson is one tightly-scoped thing.
- **Primary sources.** Cite `docs.buildstream.build` or the source, never
  parametric guesses.
- **Everything on `main`** — no research or lesson branches.
- **One glossary.** `CONTEXT.md` at the repo root is canonical; reference docs
  link to it and never duplicate it.

## Working notes

- The user maintains finpilot (bootc/OCI/RPM) and is new to BuildStream. Start
  from the declarative-graph mental shift, not from CLI syntax.
- `bst` is not installed; run it in the pinned freedesktop-sdk `bst2` container
  (see `docs/research/05-local-bst-runner.md`).
