# Codex Review Guidelines

## Project Overview

Meta-repository — SDLC Wizard documentation, automation, and a zero-dep Node.js CLI (`cli/`). Primary codebase is bash scripts + YAML workflows. The CLI distributes hooks, skills, and settings via `npx agentic-sdlc-wizard init`.

- `CLAUDE_CODE_SDLC_WIZARD.md` — The main wizard document
- `.github/workflows/` — CI, PR review, weekly/monthly automation
- `.claude/hooks/` — SDLC enforcement hooks (fire every interaction, ~100 tokens each)
- `.claude/skills/` — Detailed guidance invoked by Claude (sdlc, setup)
- `tests/` — Bash test scripts (Layer 1 logic + Layer 5 E2E)
- `cli/` — npx distribution CLI (zero-dep Node.js)

## AI Setup Lanes

This repo recommends three setup lanes — Setup A (Claude Premium: Opus 4.6 max all three roles + GPT-5.5 reviewer), Setup B (Claude Saver: Opus 4.6 max planner + Sonnet driver + GPT-5.5 reviewer), and Setup C (Claude Lite: Haiku 4.5 driver, no reviewer — for grunt/deploy/ops work). See [`AI_SETUP_LANES.md`](AI_SETUP_LANES.md) for the full pick list.

The lanes are guidance, not a hard rule — maintainer override is always allowed.

## Review Focus Areas

### 1. SDLC Compliance
- Does the change follow SDLC principles (plan, test, review)?
- Is there evidence of planning for complex changes?
- Are tests included or updated?

### 2. Security
- Shell injection in bash scripts (unquoted variables, eval, backtick expansion)
- YAML injection in workflow files (untrusted `${{ }}` in `run:` blocks)
- Secrets exposure (API keys, tokens in logs or comments)
- Unsafe variable interpolation (use `env:` blocks for LLM-generated content)

### 3. Code Quality
- Simple and readable?
- Over-engineered? (KISS principle — this project deletes legacy code aggressively)
- Follows existing patterns? (check similar files before suggesting new approaches)

### 4. Testing
- New features tested?
- Tests are meaningful (not just for coverage)?
- Testing diamond: integration > unit with mocks
- Test scripts use `set -e`, `pass()`/`fail()` helpers, exit 1 on failure

### 5. E2E Coverage Awareness
- Changes to `.claude/hooks/` → SDLC enforcement affected
- Changes to `.claude/skills/` → SDLC guidance affected
- Changes to `CLAUDE_CODE_SDLC_WIZARD.md` → Wizard behavior affected
- Changes to `.github/workflows/` → CI/auto-update behavior affected
- Changes to `tests/e2e/` → E2E test infrastructure affected

If changes affect SDLC behavior, check if relevant E2E scenarios exist in `tests/e2e/scenarios/`.

## Review Exceptions

Read `CODE_REVIEW_EXCEPTIONS.md` before flagging findings. If your finding matches a documented exception, skip it — it has already been evaluated and explicitly accepted.

## Severity

- **P0 (Critical):** Security vulnerabilities, data loss, CI breakage, silent failures
- **P1 (Must fix):** Logic bugs, missing tests for new behavior, broken E2E coverage
- **P2 (Suggestion):** Style, readability, minor improvements

## Meta-Repo Awareness

- Docs ARE code — changes to `.md` files can break tests (tests validate doc content)
- `.github/workflows/` is the most execution-critical path
- `continue-on-error: true` and `|| echo "fallback"` patterns mask real failures — always flag these
- `${{ }}` in bash `run:` blocks with LLM/user content → command injection risk (use `env:` block instead)
- macOS ships bash 3.x — no `declare -A`, no `head -n -1`
