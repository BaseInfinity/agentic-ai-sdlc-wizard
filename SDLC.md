<!-- SDLC Wizard Version: 1.87.0 -->
<!-- Setup Date: 2026-01-24 -->
<!-- Completed Steps: step-0.1, step-0.2, step-1, step-2, step-3, step-4, step-5, step-6, step-7, step-8, step-9 -->
<!-- Claude Code Baseline: v2.1.210 -->
<!-- ROADMAP #350: this single-line anchor is the source of truth for cc-version-drift.yml. -->
<!-- Update both this comment AND the "Claude Code Recommended" row when bumping CC support. -->
# SDLC Configuration

## Wizard Version Tracking

| Property | Value |
|----------|-------|
| Wizard Version | 1.87.0 |
| Last Updated | 2026-07-04 |
| Claude Code Minimum | v2.1.154+ (required for `opus[1m]` alias resolution); v2.1.105+ for `PreCompact` hook |
| Claude Code Recommended | v2.1.210+ — `SessionStart`/`Setup`/`SubagentStart` hooks no longer hide stderr on exit 2 (v2.1.199, relevant to #436's exit-code semantics), hook events no longer silently dropped during `SessionStart` in headless sessions (v2.1.204, relevant to our hooks running under `claude -p`/CI), duplicate skill-instruction context bloat on re-invocation fixed (v2.1.202), hook-callback timeouts no longer misreported as user rejection in unattended sessions (v2.1.210), `$1`/`$2` positional placeholders in skills preserved verbatim (v2.1.210, wizard skills use `$ARGUMENTS` — unaffected) |
| Recommended Model | Sonnet 5 (default) — beats Opus 4.6 on benchmarks at generally lower quota (savings vary by effort; narrows at `high`/`xhigh`). Escalate to Opus 4.8 `xhigh` when stuck. Opus 4.6 `max` remains valid for proven consistency. See `AI_SETUP_LANES.md`. |
| Recommended Effort | Model-aware — Sonnet 5: `medium` default (CodeRabbit-tested), escalate `high` → `xhigh` for hard tasks. Opus 4.8/Fable: `xhigh`/`high`. Opus 4.6: `max` only (its one `xhigh`-less sweet spot). Set per-session with `/effort`, not a shell-rc env var. |

> **Effort warning:** below your model's floor (`medium`/`high`/`xhigh`/`max` per model — see table above) = degraded reasoning, shallow TDD, weak self-review. Persisting effort via a shell-rc env var (`CLAUDE_CODE_EFFORT_LEVEL=max`) is an anti-pattern — see the Model Configuration entry under Lessons Learned below.

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
| `sdlc-prompt-check.sh` | Every prompt | SDLC baseline reminder, claude-setup-wizard redirect when SDLC.md/TESTING.md missing |
| `tdd-pretool-check.sh` | Before Write/Edit/MultiEdit | Blocks (exit 2) implementation writes to `src/**` unless a test file was touched earlier this session. This repo's own gate is scoped to `hooks/`, `cli/`, `.github/workflows/` via `SDLC_TDD_SRC_PATTERN` (no `src/` dir here) |
| `codex-gate-check.sh` | Before `git commit` (Bash) | Blocks (exit 2) commits without a REVIEWED/CERTIFIED `.reviews/handoff.json`, or with a stale (`commit_sha` mismatch) certification |
| `instructions-loaded-check.sh` | Session start | Wizard-version + CC-version staleness nudges, cross-model-review staleness check, autocompact compound-misconfig check, dual-channel-install check |
| `model-effort-check.sh` | Session start | Nudges upgrade when effort/model is behind recommended |
| `precompact-seam-check.sh` | Before manual `/compact` | Blocks compact mid-rebase/merge/cherry-pick (requires CC v2.1.105+) |
| `codex-review-stop-check.sh` | Stop | Non-blocking warning when the session ends with uncommitted changes and no REVIEWED/CERTIFIED review artifact |
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
│   ├── sdlc-prompt-check.sh      # SDLC baseline + claude-setup-wizard redirect
│   ├── tdd-pretool-check.sh      # TDD RED enforcement (blocks src/** writes)
│   ├── codex-gate-check.sh       # Blocks git commit without cross-model review
│   ├── instructions-loaded-check.sh  # Session start: version/staleness/misconfig nudges
│   ├── model-effort-check.sh     # SessionStart upgrade nudge
│   ├── precompact-seam-check.sh  # PreCompact git-op gate (CC v2.1.105+)
│   ├── codex-review-stop-check.sh # Stop: warns on uncommitted + unreviewed work
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

- **Version-bump checklist: grep ALL `SDLC Wizard Version` meta-comments, not just the obvious file.** The string lives in (a) `package.json`, (b) `SDLC.md` (top comment + table row), (c) `.claude-plugin/plugin.json`, (d) `.claude-plugin/marketplace.json`, (e) `CLAUDE_CODE_SDLC_WIZARD.md` line ~2984 (template inside the wizard doc), (f) `skills/update/SKILL.md` (changelog example block), (g) `cowork/.claude-plugin/plugin.json`, (h) `cowork/README.md`'s "Version" section, (i) `ROADMAP.md`'s "Built With SDLC Wizard" living-tracker table (this repo's own row). Missing any one trips a different test: (e) trips `tests/test-hooks.sh::test_sdlc_version_matches_wizard`; (f) trips `tests/test-docs-usability.sh`; (g)/(h)/(i) have no dedicated test yet — caught only by a Codex cross-model review round at v1.85.0, because neither matches the canonical command's string patterns (no literal "SDLC Wizard Version:" prefix, no `"version": "..."` JSON key — they read as prose like "Dogfooded, v1.84.0" or "Tracks the main wizard version: **1.84.0**"). **Better canonical command** (catches (g)/(h)/(i) too, not just (a)-(f)): `grep -rn "<previous-version>" . --include="*.md" --include="*.json"`, then manually confirm every hit is either a tracked pointer (bump it) or genuinely historical narrative (leave it) — don't rely solely on the two fixed string-pattern greps below, they have blind spots. Caught at v1.76.0 (missed wizard doc template), v1.77.0 (missed update skill example), and v1.85.0 (missed the ROADMAP living-tracker row and cowork/README.md — both prose, not either tracked string pattern). Old (narrower) command, still useful as a first pass: `grep -rn "SDLC Wizard Version: <previous>" .` and `grep -rn '"version": "<previous>"' .`. (Source: v1.76.0 + v1.77.0 release arc, 2026-05-24; v1.85.0 Codex round 1, 2026-07-05)
- **Merging to main does NOT trigger npm publish.** You must create and push a git tag (`git tag v<version> && git push origin v<version>`) to trigger `release.yml`. Verify with `npm view agentic-sdlc-wizard version`. (Source: v1.82.0 incident, 2026-06-11)
- **Self-managed CC install vs npm install coexist invisibly until `which claude` differs from `npm root -g`.** The `curl install.sh` path puts CC at `~/.local/share/claude/versions/X.Y.Z` with a `~/.local/bin/claude` symlink; npm puts it at `/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/`. If `~/.local/bin` is earlier on PATH, `claude` resolves to the self-managed binary and `npm i -g @anthropic-ai/claude-code@latest` silently updates a parallel install that nothing invokes. Diagnosis: `which claude` vs `ls /opt/homebrew/bin/claude`. Self-managed bumps via `claude update` (not npm). To consolidate to one install: `rm ~/.local/bin/claude && rm -rf ~/.local/share/claude` (frees the version cache directory); npm install on PATH takes over. Also clean stale `installMethod: "native"` in `~/.claude.json` afterward. (Source: v2.1.118 → v2.1.150 upgrade debug, 2026-05-24)

### Model Configuration

- **A blanket `CLAUDE_CODE_EFFORT_LEVEL=max` in shell rc files (`.zshrc`/`.bashrc`) silently overrides per-project and per-session effort settings, and becomes actively harmful when you switch models.** `max` was the correct default only for Opus 4.6 (the one model without `xhigh` support, where `max` is the sweet spot). On Opus 4.8 and Sonnet 5, `max` "adds significant cost for relatively small quality gains" (Anthropic effort docs) — CodeRabbit measured Sonnet 5 at max roughly doubling cost with no meaningful quality gain over `high`/`xhigh`. Symptom: running `/effort xhigh` inside a session has no visible effect because the env var wins. Fix: `unset CLAUDE_CODE_EFFORT_LEVEL` per-terminal, or remove the shell rc export entirely and set effort per-session with `/effort`, matched to the active model (see AI_SETUP_LANES.md). (Source: Sonnet 5 migration session, 2026-07-04)

### Cross-Model Review

- **A repo-wide policy migration hides in more places than the docs you set out to fix — check hooks, skill menus/logic, tutorial/template code blocks, and user-facing guidance snippets too, not just prose sections.** The v1.84.0 "Opus-4.6-flagship → Sonnet-5-model-aware" migration was scoped as "3 doc sections," but a double-digit-round Codex review kept finding it elsewhere: round 2 found it in `skills/sdlc/SKILL.md`'s own frontmatter; round 4 found the actual live `/claude-setup-wizard` and `/update` skill menus/logic had never been touched at all (a new user would never be offered the new default); round 5 found a live `SessionStart` hook (`model-effort-check.sh`) actively contradicting the new policy; round 6 found a "copy this into your CLAUDE.md" guidance snippet still asserting the old policy; round 8 found the wizard doc's "Step 5: Create the TDD Hook" — a literal, mandatory-reading template `/claude-setup-wizard` copies verbatim — still showed the pre-#436 advisory-only (non-blocking) hook, meaning a manual setup would have shipped a broken TDD gate. Rule: when migrating a blanket recommendation, explicitly check all of: prose docs, skill frontmatter, skill body logic/menus, hooks, tutorial/template code blocks that get copied verbatim, tests (which can bake in the old policy as an assertion and mask a regression), and any user-facing copy-paste snippets — before the first review round, not discovered one category per round. (Source: v1.84.0 release review, 2026-07-04)
- **Cross-model review convergence should be judged by finding-quality-per-token, not a fixed round cap or wall-clock time.** The default "2 rounds sweet spot, 3 max, escalate after" guidance (see "Cross-Model Review" above) assumes findings taper off quickly. For a genuinely large-scope migration, that assumption can be wrong for many rounds in a row — round 8 above was more consequential than rounds 1-3 combined, and time spent was never the constraint. Maintainer's own framing: "i dont care how long it takes if its efficient and effective its not about time, its about quality and tokens." Keep iterating as long as each round's finding is independently verified as real and worth fixing; stop on CERTIFIED, when consecutive rounds return nothing but nitpicks, or explicitly flag (don't silently fix) anything genuinely out of scope so tokens aren't spent chasing it. (Source: same session, 2026-07-04)
- **When a review finds a live-behavior bug (not just stale prose), turn it into a test, not just a CHANGELOG entry.** Round 8's tutorial-template-vs-real-hook drift is exactly the class of bug this repo's own Post-Mortem discipline (`Incident → Root Cause → New Rule → Test That Proves the Rule → Ship`) exists for — a human/reviewer had to read prose to catch it, when a mechanical check could: for every "Create `.claude/hooks/X.sh`" tutorial code block in `CLAUDE_CODE_SDLC_WIZARD.md`, if the real `hooks/X.sh` contains `exit 2` (blocks), the tutorial block must too. See `tests/test-wizard-doc-hook-templates.sh` (added same session) for the shipped version of this check. (Source: same session, 2026-07-04)

### Research

- **Negative-feature-existence claims need explicit citation of the source that ruled it out.** An LLM "research" tool saying "feature X does NOT exist" is much easier to fake than "feature X exists at <url>." Twice in two sessions our claude-code-guide research asserted native `/goal` had no CC equivalent — `/goal` had shipped in v2.1.139 weeks earlier, confirmed by `curl -s https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md | grep -i '/goal'`. Rule: any "X doesn't exist" claim in a research result must cite the authoritative source the search ruled it out against (docs index URL, raw changelog grep, official roadmap). Without that citation, treat as "we didn't find X" not "X doesn't exist." (Source: #347 research correction, PR #350, 2026-05-24)

### Testing

- **Separate stderr from stdout when capturing output for JSON parsing.** `2>&1` mixes stderr into stdout, causing silent JSON parse failures that defaulted scores to 0. Use `2>"$err_file"` and check exit code separately. (Source: 2026-02-06 E2E silent-zero bug)
- **`continue-on-error: true` + `|| echo "fallback"` masks real failures.** Always audit these patterns for silent bugs — they convert step failures into green checks while hiding the underlying incident.
- **`/goal` evaluator does not verify enumerated-test-name fidelity in goal conditions.** When a `/goal` condition lists specific test cases by name (e.g. `nudge-fires-when-stale + silent-when-current + silent-when-offline`), the Haiku evaluator checks that *enough* tests exist but does not verify each named test exists by BEHAVIOR. PR #361 shipped 3 tests where Test C was silent-when-cache-poisoned rather than the goal-named silent-when-offline; evaluator approved completion. Caught only at post-merge self-review and fixed in PR #362 (added the real offline test via PATH-override fault injection on `npm`). Rule: when a `/goal` condition enumerates test cases, self-review must walk each named case and verify by reading the test's assertions, not by counting matching `test_` functions. This is the per-test-fidelity layer beneath PR #355's HIGH-95%-confidence and DLC-binding gates — those work at the macro level, but enumerated-condition fidelity is the author's responsibility. (Source: PR #361 + PR #362 incident, 2026-05-25)

### Evaluation & Benchmarking

- **Disambiguate infra errors from legitimate low scores by payload, not by exit code.** When an evaluation script exits non-zero for *both* "infra broken" (no JSON produced) and "scored low / critical miss" (valid JSON, PASS=false), any wrapper that aborts on `exit != 0` will throw away perfectly good data points. `tests/e2e/run-tier2-evaluation.sh` did this: the 2026-04-13 weekly run hit `CRITICAL MISS: ["self_review"]`, `evaluate.sh` exited 1 with a valid score payload, and the wrapper aborted before appending the trial — a usable data point lost. (Note: this bug was only one half of the longer `tests/e2e/score-history.jsonl` stall after 2026-03-30; a separate PR-branch push race accounted for the remaining missing appends. See ROADMAP item on PR-branch push races.) Fix: branch on `jq -e '.error == true'` first, record the trial if a numeric `.score` is present regardless of exit code, and only abort on true infra failure. (Source: PR #193, 2026-04-18)

