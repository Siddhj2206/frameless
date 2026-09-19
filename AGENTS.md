# AGENTS.md

Working notes for agents in this repository. `overview` maps how the image is
assembled and says which skill covers what; the procedures live under
`.agents/skills/`.

## Gates

These hold for every change:

- **Conventional Commits** — `<type>[scope]: <description>`.
- **Validate before committing.** `just lint` shellchecks every tracked shell
  script, `just check` verifies Justfile syntax, and `just test-unit` runs the
  suite. `just validate-brewfiles` and `just validate-flatpaks` cover those
  files. The `validate` status check runs shellcheck and hadolint on a pull
  request.
- **Confirm before pushing** — show the diff and wait.

## Branches and releases

`main` is the testing branch: pushes publish `:stable-testing`. `stable` is
production, and it never rebuilds — `execute-release.yml` promotes the exact
digest `main` already built. Promotion is `main` → `stable` through the
auto-opened squash PR, and `stable` hotfixes sync back to `main`. `stable` takes
no direct commits. The README owns the release table and the promotion gate's
current limits.

## Pull request comments

One comment per PR event; fold new findings into the existing one. Report what
ran, whether it passed, and what blocked — nothing else. When the only finding
is "tests pass", post nothing. Mention someone only to ask for a specific
action, and do it inside the combined comment.

## Attribution

End every commit with:

    Assisted-by: <Model> via <Tool>

## Self-improvement

Ship the work and update the owning skill in the same PR, not a follow-up. A
skill is the home for durable learning; a changelog, a session note, or an
"append here" section is not. When a workaround or convention surprised you,
the next agent needs it.

## Development memory

While frameless is being written, GitHub issues are the memory layer. Record
what BuildStream is and how it works, how frameless maps onto it, design
decisions, open questions, and the full write-up of the project as issues and
their comments, so the thread survives across sessions and agents instead of
living in a chat or a scratch file.

Open issues sparingly — decisions consolidate into the plan issue or a doc
rather than getting one issue each. Search the tracker before adding.

Research lives in `docs/research/`, one markdown file per topic, cited to its
sources. Scouting passes, source reading, and comparisons write there so the
findings are reviewable rather than trapped in a session. Research and learning
land on `main` — no separate branches.

Learning lives in `docs/learning/` (mission, resources, notes, reference,
lessons, learning records), and `CONTEXT.md` at the root is the canonical
glossary. See `docs/learning/NOTES.md`.

**Direction.** finpilot is legacy — a reference for feature scope, not code to
preserve. frameless replaces it wholesale, removing the bootc/RPM structure as
the BuildStream replacement lands. Where frameless follows a pattern, the
pattern is dakota's: frameless is to dakota what finpilot is to Bluefin, and
`~/Projects/dakota` is the parent project to read first. Keep finpilot's
conveniences, but prefer BuildStream best practice even where that changes
behaviour.

This is temporary: it holds for the development period only, and it does not
replace Self-improvement above. When a finding is durable, move it into the
owning skill and close the issue.

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues in this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

Triage roles map onto projectbluefin's seven-label contract (`1-triage`, `2-discussing`, `3-human-queue`, `3-clanker-queue`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Ownership

Humans triage and approve; agents work only on assigned or `3-clanker-queue`
issues. Keep changes to this repository: `ublue-os/*` is read-only. The shared
lifecycle and labels are in
[projectbluefin/common's label workflow](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md).
