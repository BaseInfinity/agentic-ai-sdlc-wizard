# SDLC Harness - Claude Instructions

> **Part of the [XDLC ecosystem](https://github.com/BaseInfinity/xdlc)** — this is the SDLC sibling, installed into every project as the code quality layer.
>
> **Skills first → wizard later.** Build skills on real work; only graduate to a self-improving wizard once re-use proves what's portable. sdlc-wizard earned the wizard form — it didn't start there.

## Project Overview

This is a **meta-repository** - it contains the SDLC Harness documentation and automation, not traditional application code.

### What This Repo Contains

Ships to consumers (the `files` list in `package.json` — keep these in sync):
- `CLAUDE_CODE_SDLC_WIZARD.md` - The main wizard document
- `AI_SETUP_LANES.md` - Setup lane guidance
- `CHANGELOG.md` - Release history (ships; consumers read it on `/update`)
- `cli/` - The zero-dependency `sdlc-wizard` installer CLI (`bin` entrypoint)
- `skills/` - Skills installed into consumer repos
- `hooks/` - Executable bash hooks installed into consumer repos
- `.claude-plugin/` - Plugin + marketplace manifests

Repo-local only (never shipped):
- `.github/workflows/` - Automation for self-updating
- `.github/prompts/` - Claude analysis prompts
- `.claude/` - Hooks, skills, settings for *this* repo
- `scripts/` - Repo-local enforcement (`merge-pr.sh`) that deliberately
  does not ship, so consumers never inherit a gate wired to our stack
- `cowork/` - Cowork-flavored copies, byte-parity enforced against `skills/`
- `tests/` - Test scripts and fixtures

### What This Repo Does NOT Have
- No `/src/` directory. The package's CLI entrypoint lives under `cli/`;
  `hooks/` also ships executable bash. Neither is "no source code"
- No build step
- No runtime or dev dependencies (`npm install` installs nothing)
- No traditional unit tests (bash scripts only)

### Test Dependencies
- `bash` (3.x+ on macOS, 4.x+ on Linux)
- `python3` with `yaml` module (used for YAML parsing in tests)
- `jq` (used for JSON processing in tests and workflows)

## Commands

There is no runner script and no `npm test`. `.github/workflows/ci.yml` invokes
each suite as its own step — **it is the authority on what must pass**, not this
table. Run any suite directly; a few common ones:

| Command | Purpose |
|---------|---------|
| `./tests/test-version-logic.sh` | Run version comparison tests |
| `./tests/test-analysis-schema.sh` | Run schema validation tests |
| `./tests/test-doc-consistency.sh` | Guard docs against drifting from reality |
| `./tests/e2e/test-json-extraction.sh` | Run JSON extraction tests |
| `./tests/e2e/run-simulation.sh` | Run E2E simulation (needs API key) |

Run the whole suite before any release. It takes minutes, not seconds, and
some fixtures need `dangerouslyDisableSandbox` to create their temp dirs.

**Release verification (Cowork plugin)** — GH #561. Install the working-tree
plugin from the local marketplace, then:

```
claude plugin details sdlc-wizard-cowork
```

It must report exactly `Hooks (1)  PreToolUse`.

This verifies the **installed artifact's manifest-registered hooks**
(`hooks/hooks.json` and manifest `hooks` fields — the surface the #561 hook
lived on). It does **not** see skill-frontmatter hooks: verified empirically
2026-08-10, an active frontmatter `UserPromptSubmit` hook did not appear in the
inventory. Those are guarded at source by the shipped-file walk in
`tests/test-cowork-drift.sh`.

**No non-interactive, install-time command inventories dormant hooks across
every skill.** The interactive `/hooks` command does see them — verified
2026-08-10: activating a skill-frontmatter `UserPromptSubmit` hook moved it
24 → 25 total and 3 → 4 `UserPromptSubmit`. It is interactive and session-bound,
so it cannot serve as a release gate, but it is the tool to reach for when
diagnosing what is actually live in a session.

An undocumented future registration mechanism is uncovered by any check here —
cross-model diff review is the guard, and it found every missing surface to
date.

**Update commands — run both, at release time (#573).** Every command this repo
tells a reader to run must itself have been run. These are the ones the shipped
docs instruct, so they belong in this list.

```
claude plugin update sdlc-wizard-cowork@sdlc-wizard-marketplace
claude plugin update sdlc-wizard-cowork
```

Observed 2026-08-10 on an install already at the latest version:

```
$ claude plugin update sdlc-wizard-cowork@sdlc-wizard-marketplace
Checking for updates for plugin "sdlc-wizard-cowork@sdlc-wizard-marketplace" at user scope…
✔ sdlc-wizard-cowork is already at the latest version (1.97.0).

$ claude plugin update sdlc-wizard-cowork
Checking for updates for plugin "sdlc-wizard-cowork" at user scope…
✘ Failed to update plugin "sdlc-wizard-cowork": Plugin "sdlc-wizard-cowork" not found
```

**The marketplace-qualified form is the only one that resolves. The bare name
fails.** That is what the second command is here to keep proving.

**Known unknown, and the docs must not overstate it:** the qualified form has
been observed to *resolve*, never to *move a version*. Confirming movement needs
a genuinely stale install. Until someone runs it against one, `cowork/README.md`
says exactly that and names `/reload-plugins` as the only step observed to move
a version (1.93.0 → 1.97.0, `Hooks (2)` → `Hooks (1)`).

The version is on the **header line** of `claude plugin details`
(`sdlc-wizard-cowork 1.97.0`) — that command prints no `Version:` field.
`claude plugin list` is where the `Version:` label lives.

Note it reads the installed cache, not the working tree, so installing first is
mandatory: run it against an unupdated cache and it reports the OLD plugin.

## Code Style

### Markdown
- Use ATX headers (`#`, `##`, etc.)
- Tables for structured data
- Code blocks with language hints
- Keep lines under 100 chars when practical

### YAML (Workflows)
- Use 2-space indentation
- Quote strings with special characters
- Use `|` for multi-line scripts
- Add comments for non-obvious logic

### Bash (Hooks/Tests)
- Use `set -e` for fail-fast
- Quote variables: `"$VAR"` not `$VAR`
- Use `$(command)` not backticks
- Add `#!/bin/bash` shebang

## Architecture

See `ARCHITECTURE.md` for full details.

Key concepts:
- **Wizard**: Main document users copy to their repos
- **Auto-update**: Weekly workflow checks Claude Code releases
- **Hooks**: Enforce SDLC on every interaction
- **Skills**: Provide detailed guidance when invoked

## Git Workflow

- **Never commit directly to `main`** — since 2026-08-22 the forge enforces
  this for everyone, admins included. It was a working agreement until then.
  See the live settings below.
- Create a feature branch, commit there, and open a PR
- E2E signal is advisory-only now, via `tests/e2e/local-shepherd.sh` run locally on maintainer's Max subscription (ROADMAP #212 Option 1)

**What `main` actually enforces**, read from the API on 2026-08-22, after the
owner turned on admin enforcement that same day. This block once claimed 1
approving review and admin enforcement when neither was on; the review claim is
still false and the admin one is now true because it was **changed**, not
because the old text was right. A false protection claim is worse than none —
it is relied on:

| Setting | Live value |
|---|---|
| Required status checks | `validate`, strict, pinned to app_id 15368 (GitHub Actions) |
| Required approving reviews | **none** |
| `enforce_admins` | **true** — flipped 2026-08-22, see #679 |
| `allow_force_pushes` | false — force pushes are blocked |
| `allow_deletions` | false — the branch cannot be deleted |
| `required_signatures` | false |
| `required_linear_history` | false |
| `required_conversation_resolution` | false |
| `block_creations` | false |
| `lock_branch` | false |
| `allow_fork_syncing` | false |
| Rulesets | **none** |

Those are the protection endpoint's own fields, so the rows are the whole rule
and not a selection from it. The status-check row folds in one subfield:
`required_status_checks.checks[0].app_id` is 15368, which pins `validate` to
GitHub Actions, so another app cannot satisfy the check by reporting a context
of the same name.

**`main` IS a protected branch, and every row above now binds everyone.** Force
push and deletion always did: GitHub groups `allow_force_pushes` and
`allow_deletions` under a section titled *"Rules applied to everyone including
administrators"*, and says force push applies "including those with admin
permissions". As of 2026-08-22 `enforce_admins` is on, so `validate` and the
strict up-to-date requirement bind admins too. There is no bypass.

**What is still not enforced is a reviewer.** Required approving reviews are
`none`, so a merge needs a green check and nothing else. On a solo-maintainer
repo that is deliberate — GitHub refuses self-approval, so requiring one review
would deadlock every merge rather than add a reviewer.

**And admin enforcement does not make `validate` trustworthy.** It stops an
admin skipping the check; it does nothing about the check being definable by
the branch under review. See the note below.

If you edit this block, read the live API first, and check the claim in both
directions — this section has been wrong by overclaiming and by underclaiming,
in roughly equal measure.

Everything above is what the forge enforces. Everything the SDLC process
requires beyond it — the review rounds, the two SHA-bound clearances, the path
tiers, the test-deletion check — lives in `scripts/merge-pr.sh`, which is
repo-local and voluntary. The forge now blocks a direct push to `main`; it
still cannot tell a reviewed change from an unreviewed one. #679 tracks moving
that authority to the forge, and the `enforce_admins` flip was one of its
preconditions, not the redesign.

Note also that `validate` is defined in `.github/workflows/`, which a candidate
branch can modify. The merge gate blocks that via `HARD_DENY`; branch
protection does not.
- **Fable is the primary reviewer/advisor** (via `advisor()` or Fable subagent fallback when advisor is down). Codex (GPT-5.6 Sol) `high` is the **cross-model safety check** — default to running before committing and pushing. Skip only with logged justification (e.g., single-line typo fix). Incident 2026-06-09: 4 PRs shipped without cross-model check, all had issues

## Special Notes

This is a **recursive/meta project**:
- The wizard sets up other repos
- We dogfood the wizard on this repo itself
- Changes here affect what gets installed everywhere

When modifying:
- Test changes with actual wizard installation
- Consider impact on repos that use the wizard
- Update version tracking in `SDLC.md`
