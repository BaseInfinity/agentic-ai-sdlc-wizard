<!-- SDLC Wizard Version: 1.72.0 -->
<!-- Setup Date: 2026-01-24 -->
<!-- Completed Steps: step-0.1, step-0.2, step-1, step-2, step-3, step-4, step-5, step-6, step-7, step-8, step-9 -->
# SDLC Configuration

## Wizard Version Tracking

| Property | Value |
|----------|-------|
| Wizard Version | 1.72.0 |
| Last Updated | 2026-05-04 |
| Claude Code Baseline | v2.1.111+ (required for Opus 4.7 / `opus[1m]`) |
| Recommended Model | `opus[1m]` (Opus 4.7, 1M context) — run `/model opus[1m]` |
| Recommended Effort | `max` (preferred) / `xhigh` (floor) — run `/effort max` |

> **Effort warning (Opus 4.7):** `max` is the recommended default, `xhigh` is the absolute floor. Anything below `xhigh` (`high`, `medium`, `low`) causes Opus 4.7 to scope work tighter — shallow reasoning, skipped TDD, dropped self-review, SDLC non-compliance in practice. Use `high` or below only for trivial grep/search subagents, never for real SDLC work.

See `CLAUDE_CODE_SDLC_WIZARD.md` → "1M vs 200K Context Window" for the rationale and pricing notes.

## SDLC Enforcement

This repository uses the SDLC Wizard to enforce:

### 1. Planning Before Coding
- Complex tasks require planning before coding
- Multi-step tasks use `TodoWrite` or `TaskCreate`
- Confidence levels stated before implementation

### 2. TDD Approach
- Write failing tests first
- Implement to pass tests
- Refactor while keeping green

### 3. Self-Review
- Review changes before presenting
- Verify tests pass
- Check for obvious issues

## Hooks Installed

| Hook | Trigger | Purpose |
|------|---------|---------|
| `sdlc-prompt-check.sh` | Every prompt | SDLC baseline reminder |
| `tdd-pretool-check.sh` | Before Write/Edit | TDD reminder for workflows |
| `instructions-loaded-check.sh` | Session start | Validates SDLC.md/TESTING.md exist, effort/model check |
| `model-effort-check.sh` | Session start | Nudges upgrade when effort/model is behind recommended |
| `precompact-seam-check.sh` | Before manual `/compact` | Blocks compact mid-Codex-review or mid-rebase/merge/cherry-pick (requires CC v2.1.105+) |
| `token-spike-check.sh` | Session start | Warns when last session's token burn >2σ above rolling median (catches CC caching regressions; opt-in via `.metrics/`) |

## Skills Available

| Skill | Invocation | Purpose |
|-------|------------|---------|
| SDLC | `/sdlc` | Full SDLC workflow guidance |
| Setup | `/setup` | Confidence-driven project setup wizard |
| Update | `/update` | Smart update with drift detection |
| Feedback | `/feedback` | Privacy-first community feedback |

## Compliance Verification

To verify SDLC compliance:

1. **Manual check**: Start new Claude session, observe hook output
2. **E2E test (advisory)**: `gh pr checkout <PR>` then `bash tests/e2e/local-shepherd.sh <PR>` — scores the PR on your Max subscription, posts PR comment + check-run. **Advisory-only since ROADMAP #212 Option 1 (2026-04-24); not a required merge check**. The legacy `tests/e2e/run-simulation.sh` is still runnable locally but has no CI role.
3. **PR review**: Non-trivial PRs trigger AI code review workflow after `validate` passes (e2e is no longer a required check)

## Updating the Wizard

When Claude Code releases new features:

1. Weekly workflow checks for updates
2. HIGH/MEDIUM relevance creates PR
3. Review and merge if valuable
4. Update version tracking here

## Configuration Files

```
.claude/
├── settings.json                  # Hook configuration
├── hooks/
│   ├── _find-sdlc-root.sh        # Shared helper (sourced by other hooks, not a CC hook entrypoint)
│   ├── sdlc-prompt-check.sh      # SDLC baseline
│   ├── tdd-pretool-check.sh      # TDD reminder
│   ├── instructions-loaded-check.sh  # Session start validation + effort/model
│   ├── model-effort-check.sh     # SessionStart upgrade nudge
│   ├── precompact-seam-check.sh  # PreCompact seam gate (CC v2.1.105+)
│   └── token-spike-check.sh      # SessionStart token-burn anomaly detector (#220)
└── skills/
    ├── sdlc/SKILL.md             # SDLC workflow
    ├── setup/SKILL.md            # Setup wizard
    ├── update/SKILL.md           # Update wizard
    └── feedback/SKILL.md         # Community feedback
```

## Lessons Learned

Portable technical gotchas promoted from private memory via the Memory Audit Protocol (see `skills/sdlc/SKILL.md` → "After Session (Capture Learnings)" → "Memory Audit Protocol"). Entries are verified against runnable examples or repo history before being promoted; each cites the originating PR or incident date where traceable.

### GitHub CLI + Actions

- **`gh api` writes JSON errors to stdout, not stderr.** On non-2xx responses, the error body JSON lands on stdout; stderr only gets the one-line `gh: ... (HTTP 4xx)` prefix. Redirecting `2>"$err"` and grepping for tokens like `already_exists` silently misses them. Capture both: `gh api ... >"$out" 2>&1`, then grep `$out`. Verified 2026-04-17 against `gh api repos/BaseInfinity/nonexistent-xyz` — JSON body on stdout, `gh: Not Found (HTTP 404)` on stderr. (Source: PR #187 prod hotfix)
- **`workflows` is NOT a valid YAML `permissions:` scope.** Including it causes the parser to silently fail on the entire workflow file — triggers break, name shows the file path, `workflow_run` never fires. Run `actionlint` before committing workflow edits. Pushing workflow files requires a PAT with `workflow` scope or a GitHub App, not YAML permissions. (Source: `ci-autofix.yml` → `ci-self-heal.yml` rename incident, 2026-02-16)
- **GITHUB_TOKEN pushes do NOT trigger workflow events.** GitHub's anti-loop protection blocks `push`, `pull_request`, and `workflow_run` for commits pushed with the default `GITHUB_TOKEN`. Workarounds: `gh workflow run` dispatch (needs `actions: write`), a PAT/GitHub App token, or label-based re-triggers (`gh pr edit --add-label needs-review`). (Source: self-heal live-fire, PR #52, 2026-02-17)
- **GitHub Actions `${{ }}` in bash `run:` blocks command-substitutes backticks.** LLM-generated evidence text with backtick-quoted commands (``` `npm test` ```) gets executed as command substitution — npm ENOENT + exit 129. Pass untrusted content via step `env:` block instead of inline `${{ }}`. (Source: CI comment backtick injection, 2026-02-11)

### Bash

- **macOS ships bash 3.x by default** — no `declare -A` (associative arrays), no `${var@Q}` quoting. Use `case` statements for lookups; require `#!/usr/bin/env bash` + brew-installed bash 4+ if you genuinely need the newer features.

### Testing

- **Separate stderr from stdout when capturing output for JSON parsing.** `2>&1` mixes stderr into stdout, causing silent JSON parse failures that defaulted scores to 0. Use `2>"$err_file"` and check exit code separately. (Source: 2026-02-06 E2E silent-zero bug)
- **`continue-on-error: true` + `|| echo "fallback"` masks real failures.** Always audit these patterns for silent bugs — they convert step failures into green checks while hiding the underlying incident.

### Evaluation & Benchmarking

- **Disambiguate infra errors from legitimate low scores by payload, not by exit code.** When an evaluation script exits non-zero for *both* "infra broken" (no JSON produced) and "scored low / critical miss" (valid JSON, PASS=false), any wrapper that aborts on `exit != 0` will throw away perfectly good data points. `tests/e2e/run-tier2-evaluation.sh` did this: the 2026-04-13 weekly run hit `CRITICAL MISS: ["self_review"]`, `evaluate.sh` exited 1 with a valid score payload, and the wrapper aborted before appending the trial — a usable data point lost. (Note: this bug was only one half of the longer `tests/e2e/score-history.jsonl` stall after 2026-03-30; a separate PR-branch push race accounted for the remaining missing appends. See ROADMAP item on PR-branch push races.) Fix: branch on `jq -e '.error == true'` first, record the trial if a numeric `.score` is present regardless of exit code, and only abort on true infra failure. (Source: PR #193, 2026-04-18)

