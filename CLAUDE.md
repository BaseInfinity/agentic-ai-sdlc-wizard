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

**No native command enumerates all effective hooks.** An undocumented future
registration mechanism is uncovered by any check here — cross-model diff review
is the guard, and it found every missing surface to date.

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

- **Never commit directly to `main`** — branch protection requires PRs
- Create a feature branch, commit there, and open a PR
- PRs require 1 approving review and passing CI (`validate`)
- E2E signal is advisory-only now, via `tests/e2e/local-shepherd.sh` run locally on maintainer's Max subscription (ROADMAP #212 Option 1)
- Admin enforcement is on — no bypassing, even for repo owners
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
