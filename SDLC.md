<!-- SDLC Wizard Version: 1.80.0 -->
<!-- Setup Date: 2026-01-24 -->
<!-- Completed Steps: step-0.1, step-0.2, step-1, step-2, step-3, step-4, step-5, step-6, step-7, step-8, step-9 -->
<!-- Claude Code Baseline: v2.1.159 -->
<!-- ROADMAP #350: this single-line anchor is the source of truth for cc-version-drift.yml. -->
<!-- Update both this comment AND the "Claude Code Recommended" row when bumping CC support. -->
# SDLC Configuration

## Wizard Version Tracking

| Property | Value |
|----------|-------|
| Wizard Version | 1.80.0 |
| Last Updated | 2026-06-09 |
| Claude Code Minimum | v2.1.154+ (required for `opus[1m]` alias resolution); v2.1.105+ for `PreCompact` hook |
| Claude Code Recommended | v2.1.159+ (latest at 2026-06-02) — `.claude/skills` plugin auto-load (v2.1.157), enriched `tool_decision` telemetry via `OTEL_LOG_TOOL_DETAILS=1` (v2.1.157), native `/goal` (v2.1.139), `/code-review --comment` (v2.1.147), per-category `/usage` (v2.1.149), `$CLAUDE_EFFORT` env var for hooks (v2.1.133) |
| Recommended Model | `claude-opus-4-6` or `opusplan` — run `/model claude-opus-4-6` or `/model opusplan` |
| Recommended Effort | `max` — persist via `CLAUDE_CODE_EFFORT_LEVEL=max` in settings env block |

> **Effort warning:** `max` is required on all Claude models (#395). CC docs: `effortLevel: "max"` in settings.json is session-only — use the env var to persist. Below max = degraded reasoning, shallow TDD, weak self-review.

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

- **`gh pr merge --auto` silently waits forever when the branch is BEHIND base.** It does NOT auto-rebase. The PR sits with `mergeStateStatus: BEHIND` and no error surfaces. After enabling auto-merge, check `gh pr view <N> --json mergeStateStatus`; if `BEHIND`, rebase + force-push locally to wake the auto-merge trigger. Hit twice today (PR-B #353 and PR-D #355 in the same arc); both were waiting on a sibling PR that merged first and moved main. (Source: v1.77.0 release arc, 2026-05-24)
- **`gh api` writes JSON errors to stdout, not stderr.** On non-2xx responses, the error body JSON lands on stdout; stderr only gets the one-line `gh: ... (HTTP 4xx)` prefix. Redirecting `2>"$err"` and grepping for tokens like `already_exists` silently misses them. Capture both: `gh api ... >"$out" 2>&1`, then grep `$out`. Verified 2026-04-17 against `gh api repos/BaseInfinity/nonexistent-xyz` — JSON body on stdout, `gh: Not Found (HTTP 404)` on stderr. (Source: PR #187 prod hotfix)
- **`workflows` is NOT a valid YAML `permissions:` scope.** Including it causes the parser to silently fail on the entire workflow file — triggers break, name shows the file path, `workflow_run` never fires. Run `actionlint` before committing workflow edits. Pushing workflow files requires a PAT with `workflow` scope or a GitHub App, not YAML permissions. (Source: `ci-autofix.yml` → `ci-self-heal.yml` rename incident, 2026-02-16)
- **GITHUB_TOKEN pushes do NOT trigger workflow events.** GitHub's anti-loop protection blocks `push`, `pull_request`, and `workflow_run` for commits pushed with the default `GITHUB_TOKEN`. Workarounds: `gh workflow run` dispatch (needs `actions: write`), a PAT/GitHub App token, or label-based re-triggers (`gh pr edit --add-label needs-review`). (Source: self-heal live-fire, PR #52, 2026-02-17)
- **GitHub Actions `${{ }}` in bash `run:` blocks command-substitutes backticks.** LLM-generated evidence text with backtick-quoted commands (``` `npm test` ```) gets executed as command substitution — npm ENOENT + exit 129. Pass untrusted content via step `env:` block instead of inline `${{ }}`. (Source: CI comment backtick injection, 2026-02-11)

### Bash

- **macOS ships bash 3.x by default** — no `declare -A` (associative arrays), no `${var@Q}` quoting. Use `case` statements for lookups; require `#!/usr/bin/env bash` + brew-installed bash 4+ if you genuinely need the newer features.
- **State-change-on-update monitor loops: compare ONE prev string, not concatenated parts.** A bash `until`-loop that builds `cur="A=$a B=$b"` then checks `[ "$cur" != "$prev_a$prev_b" ]` will always be true on the first iteration because `$prev_a$prev_b` is concatenation, not the prior `$cur`. The monitor re-emits the same "no change" event repeatedly. Fix: single `prev=""` variable, assign `prev="$cur"` after each emit. (Source: PR #353 + PR #354 CI Monitor, 2026-05-24)

### Versioning + Releases

- **Version-bump checklist: grep ALL `SDLC Wizard Version` meta-comments, not just the obvious file.** The string lives in (a) `package.json`, (b) `SDLC.md` (top comment + table row), (c) `.claude-plugin/plugin.json`, (d) `.claude-plugin/marketplace.json`, (e) `CLAUDE_CODE_SDLC_WIZARD.md` line ~2984 (template inside the wizard doc), (f) `skills/update/SKILL.md` (changelog example block). Missing any one trips a different test: (e) trips `tests/test-hooks.sh::test_sdlc_version_matches_wizard`; (f) trips `tests/test-docs-usability.sh`. Single canonical command before tag: `grep -rn "SDLC Wizard Version: <previous>" .` and `grep -rn '"version": "<previous>"' .`. Caught at v1.76.0 (missed wizard doc template) and v1.77.0 (missed update skill example). (Source: v1.76.0 + v1.77.0 release arc, 2026-05-24)
- **Self-managed CC install vs npm install coexist invisibly until `which claude` differs from `npm root -g`.** The `curl install.sh` path puts CC at `~/.local/share/claude/versions/X.Y.Z` with a `~/.local/bin/claude` symlink; npm puts it at `/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/`. If `~/.local/bin` is earlier on PATH, `claude` resolves to the self-managed binary and `npm i -g @anthropic-ai/claude-code@latest` silently updates a parallel install that nothing invokes. Diagnosis: `which claude` vs `ls /opt/homebrew/bin/claude`. Self-managed bumps via `claude update` (not npm). To consolidate to one install: `rm ~/.local/bin/claude && rm -rf ~/.local/share/claude` (frees the version cache directory); npm install on PATH takes over. Also clean stale `installMethod: "native"` in `~/.claude.json` afterward. (Source: v2.1.118 → v2.1.150 upgrade debug, 2026-05-24)

### Research

- **Negative-feature-existence claims need explicit citation of the source that ruled it out.** An LLM "research" tool saying "feature X does NOT exist" is much easier to fake than "feature X exists at <url>." Twice in two sessions our claude-code-guide research asserted native `/goal` had no CC equivalent — `/goal` had shipped in v2.1.139 weeks earlier, confirmed by `curl -s https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md | grep -i '/goal'`. Rule: any "X doesn't exist" claim in a research result must cite the authoritative source the search ruled it out against (docs index URL, raw changelog grep, official roadmap). Without that citation, treat as "we didn't find X" not "X doesn't exist." (Source: #347 research correction, PR #350, 2026-05-24)

### Testing

- **Separate stderr from stdout when capturing output for JSON parsing.** `2>&1` mixes stderr into stdout, causing silent JSON parse failures that defaulted scores to 0. Use `2>"$err_file"` and check exit code separately. (Source: 2026-02-06 E2E silent-zero bug)
- **`continue-on-error: true` + `|| echo "fallback"` masks real failures.** Always audit these patterns for silent bugs — they convert step failures into green checks while hiding the underlying incident.
- **`/goal` evaluator does not verify enumerated-test-name fidelity in goal conditions.** When a `/goal` condition lists specific test cases by name (e.g. `nudge-fires-when-stale + silent-when-current + silent-when-offline`), the Haiku evaluator checks that *enough* tests exist but does not verify each named test exists by BEHAVIOR. PR #361 shipped 3 tests where Test C was silent-when-cache-poisoned rather than the goal-named silent-when-offline; evaluator approved completion. Caught only at post-merge self-review and fixed in PR #362 (added the real offline test via PATH-override fault injection on `npm`). Rule: when a `/goal` condition enumerates test cases, self-review must walk each named case and verify by reading the test's assertions, not by counting matching `test_` functions. This is the per-test-fidelity layer beneath PR #355's HIGH-95%-confidence and DLC-binding gates — those work at the macro level, but enumerated-condition fidelity is the author's responsibility. (Source: PR #361 + PR #362 incident, 2026-05-25)

### Evaluation & Benchmarking

- **Disambiguate infra errors from legitimate low scores by payload, not by exit code.** When an evaluation script exits non-zero for *both* "infra broken" (no JSON produced) and "scored low / critical miss" (valid JSON, PASS=false), any wrapper that aborts on `exit != 0` will throw away perfectly good data points. `tests/e2e/run-tier2-evaluation.sh` did this: the 2026-04-13 weekly run hit `CRITICAL MISS: ["self_review"]`, `evaluate.sh` exited 1 with a valid score payload, and the wrapper aborted before appending the trial — a usable data point lost. (Note: this bug was only one half of the longer `tests/e2e/score-history.jsonl` stall after 2026-03-30; a separate PR-branch push race accounted for the remaining missing appends. See ROADMAP item on PR-branch push races.) Fix: branch on `jq -e '.error == true'` first, record the trial if a numeric `.score` is present regardless of exit code, and only abort on true infra failure. (Source: PR #193, 2026-04-18)

