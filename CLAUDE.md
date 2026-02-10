# SDLC Wizard - Claude Instructions

## Project Overview

This is a **meta-repository** - it contains the SDLC Wizard documentation and automation, not traditional application code.

### What This Repo Contains
- `CLAUDE_CODE_SDLC_WIZARD.md` - The main wizard document
- `.github/workflows/` - Automation for self-updating
- `.github/prompts/` - Claude analysis prompts
- `.claude/` - Hooks, skills, settings for this repo
- `tests/` - Test scripts and fixtures

### What This Repo Does NOT Have
- No `/src/` directory (no source code)
- No build commands
- No package dependencies to install
- No traditional unit tests (bash scripts only)

## Commands

| Command | Purpose |
|---------|---------|
| `./tests/test-version-logic.sh` | Run version comparison tests |
| `./tests/test-analysis-schema.sh` | Run schema validation tests |
| `./tests/e2e/test-json-extraction.sh` | Run JSON extraction tests |
| `./tests/e2e/run-simulation.sh` | Run E2E simulation (needs API key) |

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
- **Auto-update**: Daily workflow checks Claude Code releases
- **Hooks**: Enforce SDLC on every interaction
- **Skills**: Provide detailed guidance when invoked

## Git Workflow

- **Never commit directly to `main`** — branch protection requires PRs
- Create a feature branch, commit there, and open a PR
- PRs require 1 approving review and passing CI (`validate`, `e2e-quick-check`)
- Admin enforcement is on — no bypassing, even for repo owners

## Special Notes

This is a **recursive/meta project**:
- The wizard sets up other repos
- We dogfood the wizard on this repo itself
- Changes here affect what gets installed everywhere

When modifying:
- Test changes with actual wizard installation
- Consider impact on repos that use the wizard
- Update version tracking in `SDLC.md`
