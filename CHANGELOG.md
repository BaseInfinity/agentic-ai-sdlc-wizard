# Changelog

All notable changes to the SDLC Wizard.

> **Note:** This changelog is for humans to read. Don't manually apply these changes - just run the wizard ("Check for SDLC wizard updates") and it handles everything automatically.

## [1.43.0] - 2026-05-12

### Added (late additions, 2026-05-17)

- **#235(a) `/insights` complementary-tool guidance.** Surfaced the unshipped action from #206 research (2026-04-19). Setup skill Step 12 closing checklist + `CLAUDE_CODE_SDLC_WIZARD.md` "Complementary Tools" section now both cite `/insights` (native CC, v2.1.101+) with an explicit qualitative-only caveat: it surfaces `underlying_goal`, `outcome`, `friction_counts`, `user_satisfaction_counts`, `brief_summary` from local session history, but does NOT expose `cache_read_input_tokens` / cache-hit ratio / per-turn breakdown / model-version tracking, so it does NOT replace token-spike detection (ROADMAP #220) which needs raw session JSONL. Codex cross-model reviewed (CERTIFIED 8/10, 3 P2 corrections applied — section name fixed from "Known CC Gotchas" → "Complementary Tools" since /insights is a built-in CLI command, not a failure-mode or skill).
- **#235(b) `/insights` added to slash-command allowlist.** Appended `/insights` to `tests/e2e/known-slash-commands.txt` so the community feature-discovery scanner (#207) stops flagging it as a "new" candidate on every weekly run.
- **3 doc-presence regression tests** in `tests/test-workflow-triggers.sh` guard #235(a)+(b): setup-skill mention, wizard-doc "Complementary Tools" section content, and allowlist presence. 171/0 green.

**Deferred:** #235(c) re-research checkpoint (changelog scan + direct facet-JSON inspection on CC 2.1.140 for schema additions since 2.1.101) → v1.44.

### Fixed

- **#226 weekly-update.yml wording cleanup.** Tier 2 step previously claimed "Full Statistical (5 trials)" / "5 trials" — misleading because Tier 2 re-scores the same Tier 1 transcript 5× by the judge (a judge-consistency band, not independent-trial CI). Step renamed to "Judge-Consistency Band (5× judge re-score)" in `.github/workflows/weekly-update.yml` (lines 490, 496, 680). Matches the existing caveat at line 701 referencing this same ROADMAP entry. No statistical-language drift left in the workflow itself; true N-independent-trial scoring still tracked as ROADMAP #226.
- **#227 community-PR `.txt` churn.** Community-pattern weekly PRs were shipping empty diffs whose only change was a one-line append to `tests/e2e/score-history.txt` (legacy; canonical is `.jsonl`). Root cause: `weekly-update.yml` called `cusum.sh --add "$SCORE"` which appends to `.txt`. Both Update-CUSUM steps now call `cusum.sh --add-json "{\"score\":$SCORE}"` so writes land in `score-history.jsonl`. Regression test added to `tests/test-workflow-triggers.sh::test_weekly_update_uses_cusum_jsonl_only` — fails if any future PR re-introduces the legacy bare-score form. 166/0 workflow-trigger tests green, 17/17 cusum tests green (cusum.sh API unchanged).

### Added

- **#338 skill-precedence preamble.** `skills/sdlc/SKILL.md` now opens with a "Skill source & precedence" block clarifying that repo-local `.claude/skills/` takes precedence over global `~/.claude/skills/` when both exist, with a one-liner verification command (`head -5` comparison). Repo-local copies are the project's authoritative workflow contract; global skills are for cross-repo personal tooling (e.g. `feedback`, `revise-claude-md`). Resolves user-reported confusion when both copies of `sdlc` exist with the same name.
- **#219 model-pin re-verification (CC 2.1.117).** Confirmed CC 2.1.117 restart-persistence behavior ("a session-picked model persists across restarts even when settings.json pins a different model; startup header shows when the active model comes from a project or managed-settings pin") is **orthogonal** to our no-pin-default recommendation. Setup skill Step 9.5 now documents the interaction explicitly: project pins still apply on first launch and to new contributors, but a user's later `/model` choice sticks across restarts. No code change to the recommendation itself; the docs catch up to the new CC behavior.

### Verified clean (no code change)

- **#337 `--yolo` flag audit.** Repo-wide grep across `.md`, `.sh`, `.yml`, `.json`, `.js` (including `cli/`, `.claude/`, `hooks/`, `tests/`, `skills/`, `plans/`) returned zero hits for `--full-auto` or `--yolo`. We never recommended either flag; Codex usage in our docs is limited to `codex exec -s danger-full-access`, a different flag.
- **#339 Anthropic API changelog triage (5 entries).** Multiagent sessions (2026-05-06) → out-of-scope; Sonnet 4.5/4 1M retired (2026-04-30) → N/A, we use `sonnet[1m]` (4.6); Rate Limits API (2026-04-24) → out-of-scope (admin tooling); Managed Agents memory (2026-04-23) → out-of-scope (different from our `~/.claude/projects/<proj>/memory/` system); Haiku 3 retired (2026-04-20) → N/A, no Haiku 3 references in repo.

### Process

- Codex GPT-5.5 xhigh cross-model review on the prioritization plan itself (`.reviews/preflight-roadmap-prioritization-2026-05-12.md`) before sinking 10-15 hrs into the proposed migration. Result: NOT CERTIFIED on the original 6-release plan (2 P0 / 3 P1 findings, including "claimed $25-55/week burn is fiction — cron already disabled per #212 Option 1" and "OpenCode sibling at v0.9.0, not v0.1.0 as the plan stated"). Plan pivoted: this v1.43 ships the unambiguous quick-wins first; migration items (#220, #230, #231 Phases 2-4) deferred to subsequent intervals after a separate decision gate.

## [1.42.1] - 2026-04-26

### Fixed

- **Skip Claude PR review on wizard self-PRs** (CI hygiene). The `review` job in `pr-review.yml` calls `claude-code-action@v1` which requires `ANTHROPIC_API_KEY` with positive credit balance. The wizard maintainer keeps that key's balance dead as an "API canary" so unexpected API draws fail CI. Result: every wizard self-PR's `review` job was failing with "Credit balance is too low" — seven PRs (v1.39.0–v1.42.0) shipped to main with red CI, normalizing red and masking any real review failure. Fixed: workflow `if:` gate now skips the review job when `github.repository == 'BaseInfinity/claude-sdlc-wizard'`. Consumer projects using `pr-review.yml` are unaffected — the skip only fires on the wizard's own repo. The wizard uses Codex (`codex exec` xhigh) for cross-model review on its own PRs, so the Claude PR review is redundant on self-repo. Documented in `CI_CD.md` → "Self-PR Skip on the Wizard Repo". New `tests/test-self-pr-review-skip.sh` (6 tests) prevents regression.

## [1.42.0] - 2026-04-26

### Added

- **AGENTS.md interop detection in setup** (ROADMAP #205, phase a). Setup wizard now scans for `AGENTS.md` (cross-tool agent-instructions standard adopted by Cursor/Continue.dev/Aider, [CC issue #6235](https://github.com/anthropics/claude-code/issues/6235)) during Step 1 auto-scan. If found, new Step 4.5 surfaces a 3-way decision: dual-maintain (default), merge (manual in phase a), or skip. The choice is recorded as a one-line comment in the project's `SDLC.md` for the user's reference — `/update-wizard` does NOT yet parse this metadata (phase d). No wizard-side merge or symlink behavior in v1.42.0 — option B in the prompt is "record intent, copy by hand"; phase (b) will add the copy helper. Phase (d) drift-consistency test also deferred. New `tests/test-agents-md-interop.sh` (7 tests) asserts setup auto-scan, decision step structure, wizard doc reference + phase-scope honesty.

## [1.41.1] - 2026-04-26

### Added

- **MCP-tool hooks audit documented** (ROADMAP #218). CC 2.1.118 introduced `type: "mcp_tool"` for hooks. Audited all 5 wizard hooks (sdlc-prompt-check, instructions-loaded-check, tdd-pretool-check, model-effort-check, precompact-seam-check) against MCP-tool migration criteria: portability, gating semantics, cross-tool state. Conclusion: all 5 stay bash. Per-hook rationale documented in CLAUDE_CODE_SDLC_WIZARD.md → "Known CC Gotchas → MCP-tool hooks audit". New `tests/test-mcp-hook-audit.sh` (7 tests) ensures the audit doesn't get re-litigated by future maintainers; if a hook DOES migrate later, the test is the natural place to update with new rationale.

## [1.41.0] - 2026-04-26

### Added

- **Post-mortem 2026-04-23 lessons folded into wizard docs** (ROADMAP #221). [Anthropic's 2026-04-23 post-mortem](https://www.anthropic.com/engineering/april-23-postmortem) provides independent third-party evidence for three SDLC-relevant failure modes; this release captures all three:
  - **Don't rely on CC default effort** — the post-mortem confirmed CC has flipped reasoning_effort defaults across versions (high → medium → xhigh/high). Recommended Effort section now cites this as evidence and reinforces that `/effort max` should be set explicitly every session, never assumed from the default.
  - **Extended-thinking + caching + idle sessions can drop thinking blocks** — new "Known CC Gotchas" top-level section documents the failure mode (cached prompt prefix re-served after idle pruning silently drops thinking blocks downstream), with a workaround (start fresh session with `claude --continue` if quality degrades mid-session) and a detection signal pointer to ROADMAP #220.
  - **Brevity-cap audit + regression guard** — audited every `skills/*/SKILL.md` and `hooks/*.sh` for compounding brevity constraints (`≤N words`, `be concise`, `keep brief`). Audit clean; no system-prompt brevity caps in the wizard. New `tests/test-postmortem-lessons.sh` (7 tests) includes a regression guard that fails CI if a future PR introduces one.
- "Known CC Gotchas" is now a documented section pattern; future CC failure modes get folded here with workarounds.

## [1.40.1] - 2026-04-26

### Added

- **`cleanupPeriodDays: 30` pinned in template settings** (ROADMAP #225). CC 2.1.117 expanded `cleanupPeriodDays` to also cover `~/.claude/tasks/` — the directory where the Tasks system persists in-progress TodoWrite state. With aggressive defaults (some CC versions defaulted to 7 days), SDLC checklists for paused long-running features could be silently pruned. `cli/templates/settings.json` now ships `"cleanupPeriodDays": 30` as a top-level field. `CLAUDE_CODE_SDLC_WIZARD.md` documents the gotcha + override path. New `tests/test-cleanup-period-guidance.sh` (7 tests) asserts template default + wizard rationale don't regress.

## [1.40.0] - 2026-04-25

### Added

- **CLI version detection in /update-wizard** (ROADMAP #232). New Step 1.5 detects the locally installed `agentic-sdlc-wizard` CLI version (via `npm ls -g` for global installs and `~/.npm/_npx` cache inspection for npx users), compares to the npm registry latest at `registry.npmjs.org/agentic-sdlc-wizard/latest`, and surfaces a one-shot `npx -y agentic-sdlc-wizard@latest init --force` upgrade BEFORE running drift detection or per-file updates. Closes the gap where `/update-wizard` patched in-session project files but the user's stale npx cache kept running an old CLI on `init`/`check`/`complexity` invocations. Mirrors `claude update` UX (one-shot CLI + skill sync). Honors the `check-only` flag in report-only mode (no auto-upgrade). Graceful fallback when the CLI is undetectable (custom install, offline). New `tests/test-update-skill-cli-version.sh` (8 quality tests) covers step structure, both detection paths, the registry endpoint, the upgrade command, ordering before per-file plan, `check-only` precedence, fallback wording, and the changelog entry itself.

## [1.39.1] - 2026-04-25

### Fixed

- **Step 7.7 hoist** — `/update-wizard` now runs the dead-plugin cleanup even when the wizard version on disk matches npm latest. In v1.39.0 the cleanup was gated behind Step 3's "if versions match: stop" branch, so users already on the latest wizard with a stale `~/.claude/settings.json` plugin registration could never reach Step 7.7. Symptom: `UserPromptSubmit hook error: Plugin directory does not exist: ...sdlc-wizard@sdlc-wizard-local — run /plugin to reinstall` firing on every prompt despite running `/update-wizard`. Fix updates Step 3's match-branch to invoke Step 7.7 first, then stop. New `tests/test-update-skill-step-7-7.sh` (8 quality tests) asserts the ordering and prevents regression — covers Step 3-references-Step 7.7, ordering keywords, Step 7.7 documents version-independence, allowlist intact, jq pipeline intact, timestamped backup intact.

## [1.39.0] - 2026-04-24

### Added

- **Dead plugin registration cleanup in /update-wizard** (Step 7.7). When a wizard-installed plugin marketplace in `~/.claude/settings.json` points to a directory that no longer exists (rename, disable, or removal), every Claude Code session emits `UserPromptSubmit hook error: Failed to run: Plugin directory does not exist: ...` until cleaned up. New step detects entries in `extraKnownMarketplaces` matching `sdlc-wizard*` whose `source.path` is missing, plus the corresponding `enabledPlugins["sdlc-wizard@<marketplace>"]` flag, and offers cleanup with a backup. Scope-guarded to wizard installs only — never touches third-party plugin registrations. Lives in update-skill (not setup) because dead registrations only appear after install when something disables or removes the plugin directory; update is the natural drift-detection seam.

- **Community feature-discovery scanner** — ROADMAP #207. New `tests/e2e/scan-community.sh` script extracts `/[a-z][a-z0-9-]*` slash-command mentions from transcript text (Reddit, HN, Discord, CC GitHub Discussions exports) and emits any not in the `tests/e2e/known-slash-commands.txt` allowlist. Output is JSON with `scan_date`, `input_files`, and `candidates: [{slash, count, sample}]` for triage. Maintainer pulls transcripts manually (per ROADMAP #231 Phase 3 plan: "scan-community → port to tests/e2e/scan-community.sh; maintainer runs weekly on Max"); the scanner itself is offline + deterministic. Allowlist seeded with wizard skills (`/sdlc`, `/setup`, `/update`, `/feedback`, `/code-review`, `/less-permission-prompts`, `/claude-automation-recommender`, `/schedule`, `/ultrareview`), CC native commands as of 2.1.118 (`/help`, `/clear`, `/model`, `/effort`, `/usage`, `/cost`, `/stats`, `/compact`, `/resume`, `/init`, `/mcp`, `/plugin`, `/agents`, `/hooks`, `/permissions`, `/sandbox`, `/fast`, `/exit`, `/login`, `/logout`, `/doctor`, `/install`, `/uninstall`, `/settings`), plus common URL-path false positives (`/dev`, `/usr`, `/var`, `/tmp`, `/etc`, `/bin`, `/lib`, `/opt`, `/home`, `/root`, `/proc`, `/sys`, `/run`, `/mnt`, `/media`, `/srv`). Length-≥4 filter drops `/a`, `/ab` style noise. New `tests/test-community-scanner.sh` (14 tests) covers detection, allowlist filtering (CC native + wizard skills), dedup + count, empty-input edge case, JSON shape, stdin input, multi-file aggregation, sample-context inclusion, long-line sample window, case-insensitive extraction, and dash-leading filenames. Procedure documented in `CLAUDE_CODE_SDLC_WIZARD.md` → "Community Feature-Discovery Scanner". Complements aistupidlevel.info degradation signal and CC changelog diffs — three signals together cover official + community feature surface.

## [1.38.0] - 2026-04-24

### Added

- **Prompt-hook-fires-once instrumentation** — ROADMAP #224. `hooks/sdlc-prompt-check.sh` now records one tab-separated record (`<ts>\t<pid>\tsdlc-prompt-check`) per post-dedupe invocation when the opt-in env var `SDLC_HOOK_FIRE_LOG` is set. Maintainer can count lines per user prompt to verify CC 2.1.118's double-fire fix in real sessions; >1 line per prompt indicates regression. Unwritable paths fail silently. Procedure documented in `CLAUDE_CODE_SDLC_WIZARD.md` → "Verifying Prompt-Hook-Fires-Once". 6 regression tests in `tests/test-prompt-hook-fires-once.sh` cover the instrumentation contract (counter increments, opt-in semantics, log shape, output stability, error tolerance).

- **Mixed-mode tier (Sonnet 4.6 coder + Opus 4.7 reviewer)** — ROADMAP #233. New `cli/lib/repo-complexity.js` heuristic classifies repos as `simple` or `complex` from filesystem signals (LOC, test count, hook count, workflow count, plus stakes flag for `.env` / `secrets/` / `credentials/`). Setup skill Step 9.5 expanded from binary y/N into a 3-way prompt:
  - **`[N]`** No pin (default, recommended for most repos) — preserves Claude Code auto-mode
  - **`[m]`** Mixed-mode pin `model: "sonnet[1m]"` — suggested for `simple` tier; coder runs on Sonnet, cross-model reviewer always stays at flagship (Opus 4.7 / gpt-5.5 xhigh)
  - **`[f]`** Flagship pin `model: "opus[1m]"` + `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30` — suggested for `complex` / stakes-flagged tier; current pre-#233 default
  Stakes flag (`.env` / `secrets/` / `credentials/`) forces `complex` regardless of size and detects at any depth (e.g. `config/.env`, `app/secrets/`); the coder is doing security-relevant work and the saving isn't worth the risk. Heuristic outputs are advisory — the user always picks the final tier. New `tests/test-repo-complexity.sh` (11 tests) with six fixture repos (`tests/fixtures/complexity/{simple,complex,stakes,nested-stakes,boundary-simple,boundary-complex}-repo`) covers tier classification, nested stakes detection, threshold-boundary cases (29 tests = simple, 30 = complex), JSON shape, missing-dir error path, and the `npx agentic-sdlc-wizard complexity` CLI subcommand. Cross-model review section in `skills/sdlc/SKILL.md` explicitly notes the reviewer **always** runs at flagship regardless of coder pin — weakening the review leg defeats the savings. Update skill Step 7.5 recognizes `sonnet[1m]` as a valid mixed-mode pin (no migration prompt). Wizard doc gets a new "Mixed-Mode Tier" subsection documenting the split, when to use each tier, the prove-it gate (pair-test on 3+ simple repos before recommending mixed-mode as default), and tradeoffs. **Reconciles with #198:** mixed-mode is opt-in per-project via Step 9.5; no-pin remains the default.

## [1.37.1] - 2026-04-24

### Fixed

- **Dual-channel hook 2× print** (token-bloat audit, ROADMAP item 8, PR #241). When both the project's `.claude/settings.json` AND a locally-installed wizard plugin (`~/.claude/plugins-local/` or `~/.claude/plugins/cache/`) registered the same hook, both fired per event — `SDLC BASELINE` block printed twice per `UserPromptSubmit`, ~300 tokens doubled per prompt. Fix: `dedupe_plugin_or_project()` helper in `hooks/_find-sdlc-root.sh`. Plugin invocation yields if project also registers the same hook by name (project always wins). Wired into all 5 hooks (sdlc-prompt-check, instructions-loaded-check, tdd-pretool-check, model-effort-check, precompact-seam-check). Consumer plugin-only installs still fire normally. Codex 2-round: 100/100 CERTIFIED. 9 new dedupe tests + 1 stale-fixture fix (test_instructions_hook_cwd_walkup now reads current version dynamically from package.json so it doesn't drift past the staleness-nudge threshold on each release).

## [1.37.0] - 2026-04-24

### Changed

- **`monthly-research.yml` workflow deleted** (ROADMAP #231 Phase 1, PR #235). 519 lines + 4 claude-code-action steps removed. Zero merged artifacts in 30d while burning $11-23/month in Anthropic API. Research now happens inline in a Claude Code session, not on a scheduled cron. All 17 `test_monthly_*` assertions in `tests/test-workflow-triggers.sh` stubbed with `n/a per #231 Phase 1` pattern (165/165 tests still green). Live docs (CI_CD.md, ARCHITECTURE.md, plans/AUTO_SELF_UPDATE.md) mark monthly-research REMOVED; historical audit tables intentionally preserved. Codex cross-model review: 3-round, 9/10 CERTIFIED.

- **`model-effort-check.sh` loud WARNING below xhigh** (ROADMAP #217, PR #236). Closed the coherence gap between the docs (`max` preferred, `xhigh` floor) and the hook behavior. Previously the hook treated any effort ≠ xhigh as "upgrade available" — including `max` (the preferred default), which was backwards. New behavior:
  - `effort=max` or `xhigh` → silent (at or above floor)
  - `effort=high/medium/low` or unset → LOUD WARNING block: `WARNING` marker, SDLC compliance mention, `/effort max` primary recommendation, `/effort xhigh` floor alternative, `opus[1m]` model reminder
  - Removed duplicate effort/model check from `instructions-loaded-check.sh` — single source of truth is now `model-effort-check.sh`. Regression test asserts the dupe doesn't come back.
  - 2 new TDD tests + 1 regression test. Updated `test_hooks_recommend_opus_1m_alias` for single-source-of-truth. 119/119 hook tests pass.
  - Codex cross-model review: 3-round, 10/10 CERTIFIED.

### Roadmap

- **#232 added**: `/update-wizard` should mimic `claude update` UX — detect stale npm CLI and offer to refresh before applying in-session file updates. User call-out 2026-04-24.

### Removed

- `.github/workflows/monthly-research.yml` (519 lines, 4 claude-code-action steps, 0 merged artifacts in 30d).

## [1.36.1] - 2026-04-23

### Changed

- **Repo renamed `agentic-ai-sdlc-wizard` → `claude-sdlc-wizard`.** Matches sibling pattern (`codex-sdlc-wizard`, future `opencode-sdlc-wizard`). GitHub auto-redirects old URLs for git + web. **npm package name unchanged** (`agentic-sdlc-wizard`) — brand-neutral, safer re: Anthropic trademark guidelines, and avoids disruptive npm rename.
- **Slug migration across docs/tests/configs.** All repo-internal references to the old slug updated: `README.md`, `CLAUDE_CODE_SDLC_WIZARD.md`, `CONTRIBUTING.md`, `ROADMAP.md`, `package.json` `repository.url`, raw GitHub URL fetches in `tests/test-self-update.sh`, CI workflow references. GitHub handles the redirect transparently but keeping internal references in sync prevents future drift.
- **`npm pkg fix` applied to `package.json`.** Normalizes `bin` path (drops leading `./`), `repository.url` form (`git+https://...`). Resolves `npm warn` messages surfaced during v1.36.0 publish.

### Process

- Codex cross-model review on the slug-migration + `npm pkg fix` PR.
- Release workflow `workflow_dispatch` fallback added in v1.36.0 via PR #221 proved its worth on v1.36.0 publish (tag-push trigger didn't fire; manual dispatch unblocked). Kept as permanent safety net.

## [1.36.0] - 2026-04-23

### Added

- **Regression test: every ci.yml `steps.X.outputs.Y` reference must resolve** (#214 / ROADMAP #215). Python+PyYAML test walks ci.yml, builds per-job map of step_id → emitted outputs (handles `NAME=val` and heredoc `NAME<<EOF`), and flags any dead gate. Caught #215's original bug and guards against re-introduction.
- **Regression test: no `oven-sh/setup-bun` in workflows** (#217 / ROADMAP #210). Defensive guard against Node 20 deprecation reintroduction. Committed negative control writes a tmp fixture with the banned pattern, asserts grep catches it, tears down — proves the regex is live-fire correct.
- **ROADMAP #218** — evaluate CC 2.1.118 `type: "mcp_tool"` hook capability (Prove-It gated).
- **ROADMAP #219** — re-verify #198 model-pin guidance against CC 2.1.117 restart-persistence behavior.
- **ROADMAP #220** — token-spike anomaly detection (from Anthropic 2026-04-23 post-mortem).
- **ROADMAP #221** — fold post-mortem lessons into wizard docs (explicit effort / extended-thinking+caching+idle gotcha / verbosity-cap audit).
- **ROADMAP #222** — prompt-compounding audit harness (A/B each of ~40 prompt-injection sites).
- **ROADMAP #223** — adopt GPT-5.5 in review-tier guidance after calibration (standard $5/$30 is Codex-usable ceiling; Pro $30/$180 is ChatGPT-only, reserve for release-blocker one-offs).

### Fixed

- **Tier 2 persist-scores dead gate** (#214 / ROADMAP #215). The Tier 2 "Persist scores to PR branch" step was gated on `steps.check-baseline.outputs.should_simulate`, but the Tier 2 `check-baseline` only emits `has_baseline`. The step had been silently dead, so `score-history.jsonl` never got appended from Tier 2 runs. One-word fix (`should_simulate` → `has_baseline`) plus the new cross-job output-parser regression test.
- **`score-history.jsonl` `max_score` correctness** (#216 / ROADMAP #211). Both Tier 1 and Tier 2 hardcoded `--argjson max_score 10`, causing UI scenarios (which score out of 11 via design_system bonus) to record `11/10` — nonsensical and breaking downstream analytics. Both sites now read `MAX_SCORE` from the eval result file; shell `case` statement guards non-numeric inputs; regression test grep-asserts no hardcoded literal remains.
- **CC 2.1.118 `/cost` → `/usage` doc rename** (#209). Claude Code 2.1.118 consolidated `/cost` and `/stats` into `/usage` with aliases preserved. Wizard docs and test-self-update now use `/usage` as canonical (alias note inline).

### Docs

- Roadmap entries for all additions above (#218-223), plus minor wording correction to #221(c) post-Codex review (attributes 3% drop to broader length-limit prompt change, not a single sentence).

### Process

- Codex cross-model review run on every PR in the v1.36.0 batch (3 code PRs: 10/10 + 10/10 + 8/10; 4 doc/roadmap PRs: 10/10 + 10/10 + 7/10→fixed + 9/10). Shepherd-loop discipline re-enforced after a process miss mid-cycle — logged as feedback memory `feedback_shepherd_loop_per_pr.md`.

## [1.35.0] - 2026-04-19

### Added

- **PreCompact seam gate** (#205 / ROADMAP #208). New `hooks/precompact-seam-check.sh` blocks manual `/compact` when `.reviews/handoff.json` status is `PENDING_REVIEW`/`PENDING_RECHECK` or a git rebase/merge/cherry-pick is in flight. Matcher is `manual` — auto-compact is deliberately NOT gated (blocking it could push past 100% context). Requires Claude Code v2.1.105+. 10 quality tests.
- **Self-healing PreCompact** (#206 / ROADMAP #209). Hook now treats a stale `PENDING_*` handoff as implicit `CERTIFIED` when optional `pr_number` field is present and `gh pr view <N>` reports `MERGED`. Fixes the "forgot to flip status to CERTIFIED after merge" consumer bug. Graceful fallback: if `pr_number` absent, `gh` missing, offline, or any error → existing block behavior. 4 new quality tests with mocked `gh` binary.
- **Dynamic effort auto-bump hook** (#202 / ROADMAP #195). `sdlc-prompt-check.sh` scans `UserPromptSubmit` payload for LOW-confidence / FAILED-repeatedly / CONFUSED phrases and logs a timestamped signal. At ≥2 recent signals in a 30-min window, emits a loud `!! EFFORT BUMP REQUIRED !!` block with the exact `/effort xhigh` command. 8 quality tests.
- **Loud staleness nudge** (#201 / ROADMAP #196). `instructions-loaded-check.sh` now caches npm-latest for 24h and prints a loud multi-line warning when the installed wizard is ≥3 minor versions behind. 1–2 minor keeps the existing mild one-liner.
- **Session-start CC auto-update nudge** (#192 / ROADMAP #85). Instructions-loaded hook queries for open auto-update PRs and nudges the user to review before compacting.
- **Hook token-cost caps** (#203). 4 new size-cap tests across every hook. Negative control injects echo bloat to prove the caps trip.
- **Permissions allowlist** (#204). Top read-only tools pre-approved in `.claude/settings.json` to cut permission prompts during automation.
- **Codex-audit-on-CI-logs shepherd step** (docs). SDLC skill now requires running `codex exec xhigh` against both Tier 1 and Tier 2 CI logs separately — catches silent failures, degraded metrics, and warnings-promoted-to-errors that the green checkmark hides. Dogfooded on PR #206: caught 4 P1s in pre-existing CI infra (tracked as ROADMAP #210, #211, #215 + regression of #93).

### Fixed

- **CI persist-to-PR-branch race** (#196 / ROADMAP #193). Tier 2 no longer aborts the whole run on a single low-score trial; records the trial instead.
- **Setup wizard `allowedTools` → `permissions.allow`** (#200 / ROADMAP #197). CC v2.1 renamed the field; setup template updated.
- **Setup wizard `opus[1m]` opt-in** (#199 / ROADMAP #198). Default no longer force-pins; respects explicit user choice.
- **SessionStart hook model-field absence** (#180 / commit 3b23860). Model isn't exposed in SessionStart payload; hook now detects effort-only.

### Docs

- Memory lessons promoted (#194): tier2 exit-code pattern + pipeline liveness.
- Community paths (#191 / ROADMAP #98): issue + PR templates + Discussions enabled.
- ROADMAP backlog filed this cycle: #210 (Node 24 false-green), #211 (Tier 1 "11/10" score), #212 (local-Max E2E), #213 (ship degradation env vars by default — blocked on #214), #214 (adaptive-thinking A/B Prove-It), #215 (Tier 2 persist dead code), #216 (repo rename).

## [1.34.0] - 2026-04-17

### Added
- Memory Audit Protocol for promoting private-memory lessons to shared docs (#189)
  - New `/sdlc` subsection under "After Session (Capture Learnings)" defines a three-bucket classifier (`promote` / `keep` / `manual-review`) with a rule-based privacy denylist (`type: user`/`reference` → keep, `project`/`feedback` → manual-review)
  - YAML frontmatter parser in `tests/test-memory-audit-protocol.sh` normalizes inline comments, quoted values, and whitespace so variants like `type: "user" # external` still route to keep
  - `SDLC.md` now has a `## Lessons Learned` section seeded with 7 verified technical gotchas (GH CLI stdout, `workflows` YAML scope, GITHUB_TOKEN workflow triggers, GHA `${{ }}` backtick substitution, macOS bash 3.x, stderr/stdout separation for JSON parsing, `continue-on-error` + `||` masking); each entry cites its originating PR or incident date and was re-verified with a runnable repro before promotion
  - 10-fixture corpus at `tests/fixtures/memory-audit-corpus/` (6 promote / 2 keep / 2 manual-review) with `test_expected` frontmatter seeds the future LLM-gated quality runner
  - 12-test protocol suite covers structure, rule-based denylist, YAML-variant hardening, corpus consistency (promote fixtures route to manual-review under rule-based), and corpus shape
  - Codex xhigh 3-round code review: 4/10 → 8/10 → 10/10 CERTIFIED. Caught two false lessons in private memory (`${3:-{}}` brace-default claim and `--argjson result` jq-conflict claim) that were retracted with dated strikethroughs — the protocol's first real use prevented its own false claims from shipping
  - CLI distributes skill updates + new SDLC.md section; CI wire-up in `.github/workflows/ci.yml` (validate job)
- API feature detection shepherd for Claude API release notes (#100, PRs #184, #186, #187)
  - LLM-free weekly detector at `.github/workflows/weekly-api-update.yml` polls `platform.claude.com/docs/en/release-notes/api.md`
  - `scripts/parse-api-changelog.py` parses ATX date headers with ordinal-date normalizer and bullet-summary capture (non-date sub-headers like `#### SDKs` no longer terminate bullet extraction); 200-char truncation with ellipsis; tab scrub
  - `scripts/persist-api-state.sh` writes last-seen date with branch-protection-safe non-blocking push; opens/updates a single `api-review-needed` tracking issue with enriched bullet summaries (not just dates)
  - `instructions-loaded-check.sh` nudges at session start when open issues exist; gated on local workflow presence so consumer forks see only their own detector's issues
  - 33 tests including 8 fixture-based parser tests (bullet capture, subheader boundary, tab scrub, truncation, ordinal dates) and 2 integration tests
  - Codex xhigh 5 rounds across 2 PRs: 9/10 CERTIFIED. Found-in-prod P0 hotfix in #187 — `gh api` writes JSON error bodies to stdout (not stderr), so the label-create `already_exists` check was broken after the first successful dispatch; pattern now captures both streams

### Fixed
- `gh api` error handling in `weekly-api-update.yml` now captures stdout+stderr together for `already_exists` detection on label creation (#187). Added as portable lesson in `SDLC.md` Lessons Learned

### Docs
- `/less-permission-prompts` Claude Code native skill surfaced in wizard and setup documentation (#183)
- README community section restyled with visual Discord badge for Automation Station

## [1.33.0] - 2026-04-17

### Added
- `opus[1m]` as the SDLC wizard default model (#182)
  - CLI template ships `"model": "opus[1m]"` + `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30` (tuned for 1M — compacts at ~300K)
  - `cli/init.js` `mergeSettings` merges top-level `model` on fresh installs and when absent; respects user's explicit choice; `--force` overwrites
  - Wizard doc "1M vs 200K Context Window" section flipped to recommend `opus[1m]` as default; pricing framed as "verify current rates at docs.anthropic.com" (no stale tier-specific claims)
  - `/sdlc` skill: new "Recommended Model" section between auto-approval and Confidence Check
  - `/setup` skill Step 9.5: 1M default, 200K fallback (inverted from before)
  - SDLC.md baseline bumped to v2.1.111+ (Opus 4.7 minimum)
  - Session-start hooks now recommend `opus[1m]` alias (matches the `/model` command users run)
  - 9 new tests (5 CLI model merge, 4 doc consistency); 6 existing autocompact tests updated to expect `30`, fixtures bumped to `50` in tests 37/38 to preserve the no-overwrite proof
  - Codex xhigh 2-round review: 9/10 CERTIFIED
- Dual-channel install drift guardrails (#181)
  - `cli/init.js` detects plugin install paths (`~/.claude/plugins-local/sdlc-wizard-wrap/`, `~/.claude/plugins/cache/sdlc-wizard-local/`) and blocks init with a typed `err.pluginPaths` error; `--force` bypasses
  - `instructions-loaded-check.sh` non-blocking nudge when both CLI skills and Claude plugin are present in the same project
  - HOME isolation in test files (`mktemp -d` + `trap` cleanup) prevents dev-machine HOME from leaking into assertions
  - `path.isAbsolute(home)` guard in `detectPluginInstall` — empty/relative HOME no longer causes false-positive block
  - `run_init_split` test helper captures stdout/stderr separately with explicit exit code
  - 9 new CLI tests, 5 new hook tests; Codex xhigh 4-round review: 9/10 CERTIFIED
- Model/effort upgrade detection at session start (#179, #180)
  - SessionStart hook nudges when configured `effortLevel` is below `xhigh` (wording superseded by #217 on 2026-04-24: `max` preferred, `xhigh` floor)
  - Reads `.claude/settings.local.json` → `.claude/settings.json` → `$HOME/.claude/settings.json` precedence
  - Non-blocking (`exit 0`); asks Claude to compare recommended model against its own system prompt
  - `claude-opus-4-6` defaults bumped to `claude-opus-4-7` in `pr-review.yml`, `evaluate.sh`, `sdp-score.sh`, `pairwise-compare.sh`
  - Hook added to `SDLC.md` hooks table + CLI distributes `model-effort-check.sh`

### Fixed
- `cli/bin/sdlc-wizard.js` double-print: plugin-detect errors now suppress the outer `"Error:"` prefix since detection streams its own colored guidance block (#181)

## [1.32.0] - 2026-04-16

### Added
- Opus 4.7 support in benchmark workflow (#178)
  - `claude-opus-4-7` added to model choices, `effort` input (high/xhigh/max)
  - `--effort` passed via `claude_args`, effort recorded in artifacts + summaries
  - Hard-fail when xhigh used with non-4.7 models (inputs resolved before shell)
  - Artifact names include effort level to prevent collision
  - Default: opus-4-7 + xhigh (matches CC's new default)
  - 3 new tests (39 total model-comparison tests)
- `xhigh` effort level documented in wizard (#178)
  - New effort table: high → xhigh → max (xhigh was called "recommended for coding" here; superseded by #217 on 2026-04-24: `max` is preferred, `xhigh` is the floor)
  - Opus 4.7 changes: stricter effort adherence, budget_tokens deprecated, 64k+ max_tokens guidance
- Benchmark ceiling effect audit documented in wizard
  - Cross-model audit (Codex GPT-5.4, xhigh) rated benchmark 2/10 NOT CERTIFIED
  - 4 P0 findings: fake trials, answer key leaked, no independent verification, binary rubric
  - 3 concrete fixes documented (remove coaching, add correctness scoring, real trials)
  - External benchmark comparison (SWE-Bench, Aider methodology)
- Automation Station community Discord link in README

### Fixed
- Orphaned `skills/gdlc/` causing test-doc-consistency failures (deleted)

## [1.31.0] - 2026-04-14

### Added
- Ephemeral marketplace path detection in CLI `check` command (#174)
  - Scans `~/.claude/settings.json` `extraKnownMarketplaces` for directory sources on ephemeral paths (`/tmp/`, `/private/tmp/`, `/var/folders/`)
  - `EPHEMERAL` status (path exists but in ephemeral root) warns but doesn't fail check
  - `DANGLING` status (path doesn't exist) errors with non-zero exit code
  - Suggests moving to `~/.claude/plugins-local/<name>` for stable installs
  - JSON output (`--json`) includes new `marketplace` field
  - 10 new tests (51 total CLI tests)

### Fixed
- Hook false-positive "SETUP NOT COMPLETE" in non-SDLC directories (#173, PR #175)
  - Three-way detection: both files (normal), one file (warn partial setup), neither (silent exit)
  - Added `find_partial_sdlc_root` helper for partial-setup detection
  - 2 new hook tests (60 total hook tests)

## [1.30.0] - 2026-04-12

### Added
- CC degradation detection (#96, PR #166)
  - Score persistence: CI now git-commits `score-history.jsonl` to PR branch after E2E runs, feeding CUSUM drift detection with real data
  - Fork guard (`head.repo.full_name == github.repository`) prevents silent push failures on fork PRs
  - Injection-safe: `head.ref` passed via `env:` block, not inline `${{ }}`
  - Wizard effort section hardened: explains adaptive thinking root cause (Boris Cherny GH #42796), scopes "medium default" to Pro/Max plans, cites code.claude.com docs
  - `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` documented as opt-in hardening (not default)
  - Anti-laziness CLAUDE.md guidance section targeting specific mechanisms (adaptive thinking, effort levels, thinking budget)
  - 14 behavioral tests (`test-degradation-detection.sh`)
- Model A/B comparison workflow (#94, PRs #164, #165)
  - `workflow_dispatch` benchmark: Opus vs Sonnet on E2E scenarios with 95% CI
  - Matrix strategy over scenarios, parameterized model/trials/max_turns
  - Wizard installation verification before simulation (P0 fix)
  - jq-based artifact construction (safe against empty outputs)
  - 37 quality tests (`test-model-comparison.sh`)
- Firmware-embedded E2E fixture (#78, PR #163)
  - Python SD card overlay manager, 3 device configs (Raspberry Pi, STM32, ESP32)
  - SIL + config validation tests within fixture
  - Domain-adaptive testing proof: firmware indicators, Python overlay, multi-device differentiation
  - 12 quality tests (`test-firmware-fixture.sh`)

### Fixed
- P0 shell injection in model comparison workflow: `${{ inputs.model }}` directly in `run:` blocks. Fixed by passing all inputs through `env:` block (caught by Codex review)

## [1.29.0] - 2026-04-07

### Added
- Node 24 compliance across all GitHub Actions workflows (#93, PR #160)
  - 5 action version bumps: checkout@v5, setup-node@v5, upload-artifact@v6, create-pull-request@v8, sticky-pull-request-comment@v3
  - 2 third-party actions replaced with `gh` CLI: `int128/hide-comment-action` → GraphQL `minimizeComment`, `softprops/action-gh-release` → `gh release create`
  - 4 node-version bumps from 20 to 22
  - 13 new compliance regression tests (`test-node24-compliance.sh`)
  - Expression injection P0 in release.yml caught by CI reviewer and fixed
- Autocompact env var in settings.json (#88, PR #161)
  - CLI now ships `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` in `settings.json` `env` field (200K default)
  - Smart merge preserves existing user env vars on upgrade; `--force` resets to defaults
  - Handles malformed env values (arrays, strings) gracefully with type validation
  - Setup wizard Step 9.5 references settings.json instead of shell profiles; 1M users guided to 30%
  - 9 new tests (41 total CLI tests)
- Effectiveness scoreboard (#80, PR #162)
  - `.metrics/catches.jsonl`: 52 historical bug catches extracted from repo history
  - `catch-analytics.sh`: DDE (Defect Detection Effectiveness) per layer, escape rates, severity breakdown
  - Results: cross-model-review (48%) and self-review (46%) nearly tied; self-review missed 28 bugs caught downstream; all 3 P0s caught by cross-model or CI review
  - 14 new quality tests (`test-effectiveness-scoreboard.sh`)
  - Log automation deferred until analytics proven useful (prove-it gate)

### Fixed
- Expression injection in `release.yml`: `${{ github.ref_name }}` directly in `run:` shell command allowed tag-based code injection. Fixed by passing through `TAG_NAME` env var (P0, caught by CI reviewer)
- `$TOTAL_` variable name collision in `catch-analytics.sh`: bash parsed as undefined variable `TOTAL_` instead of `$TOTAL` + underscore. Fixed with `${TOTAL}_` brace syntax (P0, caught by CI reviewer)

## [1.28.0] - 2026-04-06

### Added
- Autocompact benchmarking methodology — first rigorous framework for testing `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` thresholds (#92, PR #158)
  - `AUTOCOMPACT_BENCHMARK.md`: experimental design, canary fact mechanism, cost estimation, limitations
  - `tests/benchmarks/run-benchmark.sh`: parameterized harness with `--dry-run`, threshold validation, multi-turn session via `--resume`
  - `tests/benchmarks/analyze-results.sh`: statistical comparison tables using `stats.sh`
  - 3 task files (short/medium/long) with canary fact injection for context preservation measurement
  - `canary-facts.json`: 5 domain-independent facts for binary recall scoring with negation detection
  - `.github/workflows/benchmark-autocompact.yml`: `workflow_dispatch` with matrix strategy across thresholds
  - 26 quality tests proving methodology rigor, harness behavior, and research standards

### Changed
- README bio: reflects full-stack founding engineer background (not just SDET/QA)
- Wizard doc autocompact section references benchmarking methodology
- Workflow count updated (5→6) across README and CI

## [1.27.0] - 2026-04-05

### Added
- Domain-adaptive testing diamond — setup wizard auto-detects project domain (firmware/data-science/CLI/web) and generates domain-specific TESTING.md with appropriate testing layers (#79, PR #157)
  - Firmware/Embedded: HIL/SIL/Config Validation/Unit (no browser, no DB)
  - Data Science: Model Evaluation/Pipeline Integration/Data Validation/Unit
  - CLI Tool: CLI Integration/Behavior/Unit (no browser)
  - Web/API: unchanged default (E2E/Integration/Unit)
- Domain detection patterns in wizard doc scan tree and setup skill Step 1/2/6
- 3 new test fixtures: firmware-embedded, data-science, cli-tool (partially satisfies #78)
- 25 domain detection quality tests

### Fixed
- Setup skill cross-references: Step 4/5 now correctly reference wizard doc Steps 8/9 (caught by CI PR review)

## [1.26.0] - 2026-04-05

### Added
- Codex SDLC Adapter plan — certified (9/10) through 5-round cross-model review. `BaseInfinity/codex-sdlc-wizard` repo created with plan + README. Upstream sync architecture designed (weekly GH Action monitors sdlc-wizard releases). Hooks: PreToolUse `^Bash$` for git commit/push blocking (HARD — stronger than CC), AGENTS.md for TDD guidance (SOFT), UserPromptSubmit for SDLC baseline. ~70% CC parity (#91)
- Research: claw-code, OmO, OmX pattern analysis — 16 candidate patterns identified from 3 open-source AI agent projects (claw-code 168K stars, OmO 48K, OmX 16K). Key findings: GreenContract graduated test levels, $ralph bounded persistence loop, planning gate enforcement, planner/executor separation. All candidates require Prove It Gate before adoption. Codex certified 8/10 round 3 (#58)
- Automated CC Feature Discovery verified working — weekly-update.yml already implements this via analyze-release.md (#85)

### Changed
- Roadmap: #79 (Domain-Adaptive Testing) and #92 (Autocompact Benchmarking) queued for next release
- Research doc: `RESEARCH_58_CLAW_OMO_OMX.md` added as reference (candidates list, not commitments)
- Codex adapter plan: `CODEX_ADAPTER_PLAN.md` added with full specs (hooks, scripts, tests, install flow)

## [1.25.0] - 2026-04-04

### Added
- Claude Code plugin format — single source of truth: `skills/` and `hooks/` at repo root serve plugin + CLI. `.claude-plugin/plugin.json` manifest, `hooks/hooks.json` with `${CLAUDE_PLUGIN_ROOT}`, `.claude-plugin/marketplace.json` for self-hosted marketplace. Absorbs #66 + #87 (#89)
- 6 distribution channels — npm, plugin, curl install script, Homebrew tap, gh CLI extension, GitHub Releases (#90)
- `install.sh` curl-pipeable installer — download guard, strict mode, Node.js >= 18 check, `--global` flag, terminal-aware colors. 20 tests (structural + integration)
- `.github/workflows/release.yml` — tag-push automation with npm publish --provenance (SLSA), GitHub Release via softprops/action-gh-release@v2. 14 tests
- External repos: `BaseInfinity/homebrew-sdlc-wizard` (Homebrew tap), `BaseInfinity/gh-sdlc-wizard` (gh CLI extension)
- 25 plugin format tests, 34 distribution tests (20 install + 14 release workflow)

### Fixed
- CI shepherd: enforce reading CI logs on pass AND fail (not just failures). Pre-release CI audit across merged PRs added to release planning gate

### Changed
- CLI `init.js` reads skills/hooks from repo root (single source, no duplication)
- Dogfood `.claude/` uses symlinks to root skills/hooks
- README: added curl, Homebrew, gh extension, GitHub install methods
- CI_CD.md: added release.yml documentation + NPM_TOKEN secret

## [1.24.0] - 2026-04-04

### Added
- Hook `if` conditionals — CC v2.1.85+ `if` field on PreToolUse hook. TDD check only spawns for source files (repo: `.github/workflows/*`, template: `src/**`). Documented in wizard CC features section with matcher-vs-if comparison table (#68)
- Autocompact tuning guidance — `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` and `CLAUDE_CODE_AUTO_COMPACT_WINDOW` env vars with community-recommended thresholds (75% for 200K, 30% for 1M). 1M vs 200K context window comparison table. Setup wizard Step 9.5 for context window configuration (#88)
- 6 hook tests for `if` field (52 total hook tests)
- 5 autocompact/context tests (70 total self-update tests)

### Fixed
- E2E tdd_red detection — three bugs since inception: test-only scenarios scored 0 (missing elif branch), golden outputs were .txt not JSON, golden-scores.json encoded the bug it was meant to catch. Codex cross-model review caught regex false-positive + missing JSON pairing (#86)
- 29 deterministic + 9 regression tests for tdd_red fix

## [1.23.0] - 2026-04-01

### Added
- Update notification hook — `instructions-loaded-check.sh` checks npm for newer wizard version each session. Non-blocking, graceful on network failure. One-liner: "SDLC Wizard update available: X → Y (run /update-wizard)" (#64)
- Cross-model review standardization — mission-first handoff (mission/success/failure fields), preflight self-review doc, verification checklist, adversarial framing, domain template guidance, convergence reduced to 2-3 rounds. Audited 4 repos + 14 external repos + 7 papers (#72, #56)
- Release Planning Gate — section in SDLC skill. Before implementing release items: list all, plan each at 95% confidence, identify blocks, present plans as batch. Prove It Gate strengthened with absorption check (#73)
- 6 quality tests for update notification (fake npm in PATH, version comparison, failure modes)
- 12 quality tests for cross-model review, context position, release planning
- Testing Diamond boundary table — explicit E2E (UI/browser ~5%) vs Integration (API/no UI ~90%) vs Unit (pure logic ~5%) in SKILL.md and wizard doc (#65)
- Skill frontmatter docs — expanded to full table covering `paths:`, `context: fork`, `effort:`, `disable-model-invocation:`, `argument-hint:` (#69)
- `--bare` mode documentation in SKILL.md — complete wizard bypass warning for scripted headless calls (#70)
- 6 quality tests for #65/#69/#70
- "NEVER AUTO-MERGE" enforcement gate in CI Shepherd section — same weight as "ALL TESTS MUST PASS." Full shepherd sequence documented as mandatory (post-mortem from PR #145 incident)
- Post-Mortem pattern — when process fails, feed it back: Incident → Root Cause → New Rule → Test → Ship. "Every mistake becomes a rule"
- 4 quality tests for enforcement gate + post-mortem

### Fixed
- Dead-code pipe in `test_prove_it_absorption()` — `grep -qi | grep -qi` was a no-op (P1 from PR #145 CI review)

### Changed
- Moved "ALL TESTS MUST PASS" from 61% depth to 11% depth in SDLC skill (Lost in the Middle fix) (#57)
- Prove It Gate now requires absorption check — "can this be a section in an existing skill?" — before proposing new skills/components
- Wizard "E2E vs Manual Testing" section replaced with "E2E vs Integration — The Critical Boundary" (#65)
- Wizard "Skill Effort Frontmatter" section expanded to "Skill Frontmatter Fields" with full field reference (#69)

## [1.22.0] - 2026-04-01

### Added
- Plan Auto-Approval Gate — skip plan approval when confidence >= 95% AND task is single-file/trivial. Still announces approach, just doesn't wait. "When in doubt, wait for approval" (#53)
- Debugging Workflow section — systematic Reproduce → Isolate → Root Cause → Fix → Regression Test methodology. `git bisect` for regressions, environment-specific debugging guidance (#55)
- `/feedback` skill — privacy-first community contribution loop. Bug reports, feature requests, pattern sharing, SDLC improvements. Never scans without explicit consent. Creates GH issues on wizard repo (#37)
- BRANDING.md detection in setup wizard — scans for brand/, logos/, style-guide.md, brand-voice.md. Conditional generation only when branding assets found (#44)
- N-Reviewer CI Pipeline guidance — address each reviewer independently, resolve conflicts, max 3 iterations per reviewer (#32)
- Custom Subagents documentation — `.claude/agents/` pattern for sdlc-reviewer, ci-debug, test-writer agents. Skills vs agents comparison (#45)
- CLI distributes `/feedback` skill (9 template files, was 8)
- Improved CLI install restart messaging — `--continue` promoted as primary option for preserving conversation history
- 20 new tests across all 6 roadmap items

### Changed
- SDLC skill: added Auto-Approval, Debugging Workflow, Multiple Reviewers, Custom Subagents sections
- Setup skill: added branding asset detection (Step 1) and BRANDING.md generation (Step 8.5)
- Wizard doc: added Plan Auto-Approval, Debugging Workflow, N-Reviewer Pipeline, Custom Subagents, BRANDING.md template

## [1.21.0] - 2026-03-31

### Added
- Confidence-driven setup wizard — kills the fixed 18 questions. Scans repo, builds confidence per data point, only asks what it can't infer. Dynamic question count (0-2 for well-configured projects, 10+ for bare repos). 95% aggregate confidence threshold (#52)
- CI Shepherd opt-in question in setup wizard (#48 partial)
- Cross-model release review recommendation — releases/publishes as explicit trigger, Release Review Checklist with v1.20.0 evidence (#49)
- Prove It Gate enforcement in SDLC skill — prevents unvalidated additions with quality test requirements (#50)
- 6 confidence-driven setup tests, 10 prove-it-gate tests, 6 release review tests

### Removed
- ci-analyzer skill — violated Prove It philosophy (existence-only tests, no quality validation, overlap with `/claude-automation-recommender`) (#50)
- ci-self-heal.yml deprecated — local shepherd is the primary CI fix mechanism

### Changed
- Wizard doc: Q-numbered questions → data point descriptions with detection hints
- Setup skill: 12 steps (was 11) with new "Build Confidence Map" step
- CLI distributes 8 template files (was 9, removed ci-analyzer)

## [1.20.0] - 2026-03-31

### Added
- CC version-pinned update gate — E2E tests run actual new CC version, not bundled binary (#46)
- Tier 1 E2E flakiness fix — regression threshold 1.5→3.0, absorbs ±2-3 point LLM variance (#47)
- Flaky test prevention guidance with external reference in wizard, SKILL.md
- 2 release consistency tests (package.json ↔ CHANGELOG ↔ SDLC.md version parity)

## [1.19.0] - 2026-03-31

### Added
- CI Local Shepherd Model — two-tier CI fix model (shepherd primary, bot fallback), SHA-based suppression (#36)
- Gap Analysis vs `/claude-automation-recommender` — complementary tools positioning (#35)
- `/clear` vs `/compact` context management guidance (#38)
- Token efficiency auditing — `/cost`, `--max-budget-usd`, OpenTelemetry (#42)
- Blank repo support — verified clean install, 10 new E2E tests (#31)
- Feature documentation enforcement — ADR guidance, `claude-md-improver`, doc sync in SDLC (#43)
- Setup skill description trimmed to 199 chars (v2.1.86 caps at 250)

## [1.18.0] - 2026-03-30

### Added
- `/update-wizard` skill — guided update with changelog diff, per-file comparison, selective adoption
- `step-update-wizard` in wizard step registry
- CLI distributes `skills/update/SKILL.md` (now 8 managed files)
- `/update-wizard` reference in wizard "How to Update" section

## [1.17.0] - 2026-03-30

### Fixed
- Setup skill now force-reads entire wizard doc before proceeding (was just "Reference")
- README no longer tells users to manually invoke setup — hooks auto-invoke
- 3 new tests for setup auto-invoke behavior

### Changed
- Testing consolidation: `/testing` skill merged into `/sdlc` (#28)

## [1.16.0] - 2026-03-29

### Added
- Cross-model review dialogue protocol — structured FIXED/DISPUTED/ACCEPTED negotiation loop (#40)
- P0/P1/P2 severity rubric in PR review prompt (#34)
- Effort level recommendations in wizard
- 5 enforcement gap fixes in TodoWrite checklist (#39)

## [1.15.0] - 2026-03-25

### Added
- aistupidlevel.info as Source 3 in external benchmark cascade (DailyBench -> LiveBench -> aistupidlevel -> baseline)
- Competitive watchlist in `analyze-community.md` — weekly scan now checks 5 named repos for new releases/patterns
- `COMPETITIVE_AUDIT.md` — honest ecosystem comparison, unique strengths, tracked gaps, contribution ideas
- README "How This Compares" section with honest positioning table
- Token usage tracking gap documented (blocked until `claude-code-action` exposes usage data)
- 3 new tests in `test-external-benchmark.sh` for aistupidlevel integration
- 2 new tests in `test-prove-it.sh` for competitive watchlist and README positioning

### Changed
- Roadmap reordered: competitive audit (#10) marked DONE

## [1.14.0] - 2026-03-24

### Fixed
- CI re-trigger bug: `workflow_dispatch` caused `e2e-quick-check` to skip, blocking auto-merge (PR #75). Jobs now accept dispatch events with simulation steps gated behind PR-only checks
- SDLC.md version stuck at 1.9.0 (should be 1.14.0)
- CONTRIBUTING.md missing 11 test scripts, outdated scoring criteria, wrong repo URL in discussions link

### Added
- 3 tests in `test-workflow-triggers.sh`: verify required CI jobs accept `workflow_dispatch`
- 4 integration tests in `test-prove-it.sh`: prove `compare_ci` detects REGRESSION/STABLE/IMPROVED with synthetic scores
- 3 E2E tests in `test-self-update.sh`: verify live CHANGELOG and wizard URLs return valid content
- `should_simulate` gate in CI: dispatch runs produce green checks without burning API credits
- Documented `workflow_dispatch` behavior in `ci-self-heal.yml`

### Changed
- Roadmap reordered: competitive audit (#10) before distribution (#30)
- CONTRIBUTING.md scoring criteria updated to v3 multi-call judge + v3.1 pairwise tiebreaker
- CONTRIBUTING.md test list updated to all 21 CI validate scripts

## [1.13.0] - 2026-03-23

### Changed
- Rewrote "Staying Updated" section with explicit fetch URLs, CHANGELOG-first update flow, and 4-phase process
- Claude now shows users what changed (via CHANGELOG) before offering to apply updates
- Fixed "CHANGELOG is for Humans, Not Claude" — Claude reads CHANGELOG first to drive the update flow

### Added
- Optional "Wizard Update Notification" GitHub Action template — weekly check, creates issue when newer version exists ($0 cost, no API key)
- `step-update-notify` in wizard step registry (optional step for CI notification)
- 12 new tests in `tests/test-self-update.sh` (URL correctness, YAML validation, workflow template, step registry)

## [1.12.0] - 2026-03-23

### Fixed
- Apply step in `weekly-update.yml` and `monthly-research.yml` never propagated changes to test fixture (baseline == candidate, verdict always STABLE, comparison useless)
- Stale output file between baseline and candidate simulations in both auto-update workflows (same bug as ci.yml, fixed in #24)
- `sdp-score.sh` default model `claude-sonnet-4` corrected to `claude-opus-4-6` (matches evaluate.sh)
- README "All 6 workflows" corrected to "All 5 workflows" (stale since v1.9.0 consolidation)

### Added
- 6 new audit tests: apply step propagation (2), stale output cleanup (2), SDP model consistency (1), README accuracy (1)
- Native CC feature overlap analysis: all 5 custom features audited — KEEP CUSTOM (no overlap with CC v2.1.81)

### Audited (no changes needed)
- All 5 custom features (hooks + skills): value is in content (SDLC philosophy, TDD enforcement), not framework
- Noted for future: `continue-on-error` patterns, `/tmp` hardcodes, permission scoping

## [1.11.0] - 2026-03-23

### Fixed
- Stale output file between baseline and candidate simulations in Tier 2 (candidate eval could read baseline data on silent failure)
- Comment "3x evaluations" corrected to "5x evaluations" in ci.yml Tier 2 header
- `run-tier2-evaluation.sh` silent `score=0` fallback replaced with proper error handling (stderr separation, exit on failure)

### Added
- 13 test scripts wired into CI validate job (228 additional tests now run on every PR)
- Tests for Tier 2 comment accuracy and stale output cleanup
- Tests for `run-tier2-evaluation.sh` error handling (no stderr suppression, no silent fallback)

### Removed
- Legacy duplicate `tests/test-self-heal-simulation.sh` (690 lines, subset of e2e version)

## [1.10.0] - 2026-03-22

### Added
- "Prove It's Better" CI automation — when weekly-update detects a CC release that overlaps a custom wizard feature, CI auto-runs a side-by-side Tier 2 comparison and recommends KEEP CUSTOM / SWITCH TO NATIVE / TIE
- `tests/e2e/lib/prove-it.sh` — path validation allowlist + fixture stripping library
- `prove-it-test` job in `weekly-update.yml` — only runs when overlap detected ($0 extra on typical weeks)
- Custom feature inventory table in `analyze-release.md` — tells Claude what to check for overlap
- `has_overlap` / `overlap_paths` outputs wired from `check-updates` job
- 13 new tests in `tests/test-prove-it.sh` (allowlist validation, fixture stripping, settings.json updates, overlap signal parsing, workflow integration)
- Test fixture `tests/fixtures/releases/v99.0.0-overlap.json`

## [1.9.1] - 2026-03-22

### Verified
- `all-findings` self-heal (#27): PR #70 confirmed `workflow_run` triggers on review suggestions, `AUTOFIX_LEVEL=all-findings` passes filtering, Claude invoked in `review-findings` mode

### Added
- Real CI review format parsing test (h4 headers, `_None._` italic, line references)
- Roadmap ordering in AUTO_SELF_UPDATE.md

## [1.9.0] - 2026-03-21

### Changed
- Consolidated `daily-update.yml` + `weekly-community.yml` into single `weekly-update.yml`
  - 4 jobs: check-updates, version-test, scan-community, community-e2e-test
  - Single Monday 9 AM UTC schedule (was two separate cron entries)
  - Reduces workflow count from 6 to 5, auto-update workflows from 3 to 2
  - Cost: ~$2.50/week combined (unchanged)
- Updated all docs and 25+ tests to reference `weekly-update.yml`

### Added
- 5 new workflow consolidation tests: 4-job structure, dependency chains, permissions, single cron

## [1.8.1] - 2026-03-21

### Fixed
- `tdd_red` deterministic checker: now parses JSON execution output via jq (was always scoring 0/2 due to regex mismatch with claude-code-action JSON format)
- Score history push: checkout actual PR branch before push (was silently failing from detached HEAD)
- `instructions-loaded-check.sh`: explicit `exit 0` for defensive safety

### Changed
- Phase 5: Re-enabled all auto-update workflow schedules
  - `weekly-update.yml` (formerly `daily-update.yml` + `weekly-community.yml`): Mondays 9 AM UTC
  - `monthly-research.yml`: re-enabled (1st of month 11 AM UTC)
- Golden scores: `high-compliance.tdd_red` updated to 0 (text golden files lack JSON tool_use blocks; tdd_red correctness verified via dedicated JSON unit tests)

### Added
- 7 new tests: JSON-based tdd_red checks (5), empty/nonexistent file edge cases (2)
- 3 new workflow trigger tests: weekly schedule validation, all-schedules-active, score-history-checkout

## [1.8.0] - 2026-03-20

### Added
- Version catch-up: consolidated update from Claude Code v2.1.15 to v2.1.81 (66 minor versions)
- `InstructionsLoaded` hook (`instructions-loaded-check.sh`) — validates SDLC.md and TESTING.md exist at session start (v2.1.69+)
- `effort: high` frontmatter on `/sdlc` and `/testing` skills (v2.1.80+)
- "Prove It's Better" core philosophy — use native features unless custom is proven better via E2E comparison
- Vision statement in README — "Mold an ever-evolving SDLC... replace with native... one day delete this repo"
- Documentation section in README linking ARCHITECTURE.md, CI_CD.md, SDLC.md, TESTING.md, CHANGELOG.md, CONTRIBUTING.md
- Documented new built-in commands in wizard: `/memory`, `/simplify`, `/batch`, `/loop`, `/effort`
- Documented security hardening fixes (v2.1.49, v2.1.72, v2.1.74, v2.1.77, v2.1.78)
- Documented `${CLAUDE_SKILL_DIR}` variable, `agent_id`/`agent_type` hook metadata
- Documented `CLAUDE_CODE_SIMPLE` bypass risk, HTML comment behavior, 128k output tokens, `--bare` flag
- 7 new hook tests (18 total) for InstructionsLoaded hook
- `plans/CATCHUP.md` — documents the version catch-up process for future reference

### Changed
- Claude Code baseline bumped from v2.1.15+ to v2.1.81+
- Wizard version bumped from 1.7.0 to 1.8.0
- Prerequisites updated: minimum v2.1.69+ (was v2.1.16+)
- `.github/last-checked-version.txt` updated to v2.1.81
- Scheduled workflow triggers disabled (PR #66) to save API tokens — re-enable in Phase 5

### Audited (Category C: no swap needed)
- No custom `/claude-api` skill exists — nothing to swap with native built-in

## [1.7.0] - 2026-02-15

### Added
- CI Auto-Fix Loop (`ci-self-heal.yml`) — automated fix cycle for CI failures and PR review findings
- Multi-call LLM judge (v3) — per-criterion API calls with dedicated calibration examples
- Golden output regression — 3 saved outputs with verified expected score ranges catch prompt drift
- Per-criterion CUSUM — tracks individual criterion drift, not just total score
- Pairwise tiebreaker (v3.1) — holistic comparison with full swap when scores within 1.0
- Deterministic pre-checks — grep-based scoring for task_tracking, confidence, tdd_red (free, fast)
- 3 real-world scenarios: multi-file-api-endpoint, production-bug-investigation, technical-debt-cleanup
- Score analytics (`score-analytics.sh`) — history parsing, trends, per-criterion averages, reports
- Score history persistence — results committed back to repo after each E2E evaluation
- Historical context in PR comments — scenario average and weakest criterion
- Color-coded PR comments — emoji indicators for PASS/WARN/FAIL per criterion
- Binary sub-criteria scoring with workflow input validation (PR #32)
- Evaluate bug regression tests (`test-evaluate-bugs.sh`)
- Score analytics tests (`test-score-analytics.sh`)
- Self-heal simulation tests (25 tests) — retry counting, AUTOFIX_LEVEL filtering, findings parsing, branch safety
- Self-heal live fire test procedure — validated full workflow_run → Claude fix → commit cycle (PR #52)

### Fixed
- `workflow_run` trigger dead for ci-autofix — invalid `workflows: write` permission scope caused GitHub parser to silently fail; removed it + renamed to `ci-self-heal.yml`
- Tier 1 E2E flakiness — regression threshold widened from -0.5 to -1.5 (absorbs ±1 LLM noise)
- Silent zero scores from `2>&1` mixing stderr into stdout (PR #33)
- Token/cost metrics always N/A — removed dead extraction code (action doesn't expose usage data)
- Score history never persisting (ephemeral runner) — added git commit step
- `show_full_output` invalid action input — deleted
- `configureGitAuth` crash — added `git init` before simulation
- `error_max_turns` on hard scenarios — bumped from 45 to 55
- Autofix can't push workflow files — requires PAT with `workflow` scope or GitHub App (not YAML permissions)
- `git push` silent error swallowing in `weekly-community.yml` — removed `|| echo` fallback
- Missing `pull-requests: write` permission in `monthly-research.yml` — e2e-test job creates PRs but permission wasn't declared
- Workflow input validation audit — removed `prompt_file`, `direct_prompt`, `model` invalid inputs across all 3 auto-update workflows
- `outputs.response` doesn't exist — read from execution output file instead
- CI re-trigger 403 in self-heal loop — missing `actions: write` permission for `gh workflow run` dispatch

### Changed
- `monthly-research.yml` schedule enabled (1st of month, 11 AM UTC) — Item 23 Phase 3
- `weekly-community.yml` schedule enabled (Mondays 10 AM UTC) — Item 23 Phase 2
- `daily-update.yml` schedule re-enabled (9 AM UTC) — Item 23 Phase 1
- All auto-update workflows create PRs (removed "LOW → direct commit" path)
- Evaluation uses `claude-opus-4-6` model (was hardcoded to `claude-sonnet-4`)
- E2E scenarios expanded from 10 to 13

## [1.6.0] - 2026-02-06

### Added
- Full test coverage for stats library, hooks, and compliance checker (34 new tests)
- Extended SDP calculation and external benchmark tests (9 new tests)
- Future roadmap items 14-19 in AUTO_SELF_UPDATE.md

### Fixed
- Version format validation before npm install (security: prevents injection)
- Hardcoded `/home/runner/work/_temp/` paths replaced with `${RUNNER_TEMP:-/tmp}`
- Silent fallback to v0.0.0 on API failure (now fails loudly)
- Duplicate prompt sources in daily-update workflow (prompt_file + inline prompt)
- Hardcoded output path in pr-review workflow
- Weekly community workflow hardcoded output path

### Changed
- Documentation overhaul: TESTING.md, CI_CD.md, CONTRIBUTING.md, README.md updated
- SDLC.md version tracking updated from 1.0.0 to 1.6.0

### Files Added
- `tests/test-stats.sh` - Statistical functions tests (14 tests)
- `tests/test-hooks.sh` - Hook script tests (11 tests)
- `tests/test-compliance.sh` - Compliance checker tests (9 tests)

### Files Modified
- `.github/workflows/daily-update.yml` - Security + correctness fixes
- `.github/workflows/pr-review.yml` - Hardcoded path fix
- `.github/workflows/weekly-community.yml` - Hardcoded path fix
- `tests/test-sdp-calculation.sh` - Extended (5 new tests)
- `tests/test-external-benchmark.sh` - Extended (4 new tests)

## [1.5.0] - 2026-02-03

### Added
- SDP (SDLC Degradation-adjusted Performance) scoring to distinguish "model issues" from "wizard issues"
- External benchmark tracking (DailyBench, LiveBench) with 24-hour caching
- Robustness metric showing how well SDLC holds up vs model changes
- Two-layer scoring: L1 (Model Quality) + L2 (SDLC Compliance)

### How It Works
PR comments now show three metrics:
- **Raw Score**: Actual E2E measurement
- **SDP Score**: Adjusted for external model conditions
- **Robustness**: < 1.0 = resilient, > 1.0 = sensitive

When model benchmarks drop but your SDLC score holds steady, that's a sign your wizard setup is robust.

### Files Added
- `tests/e2e/lib/external-benchmark.sh` - Multi-source benchmark fetcher
- `tests/e2e/lib/sdp-score.sh` - SDP calculation logic
- `tests/e2e/external-baseline.json` - Baseline external benchmarks
- `tests/test-external-benchmark.sh` - Benchmark fetcher tests
- `tests/test-sdp-calculation.sh` - SDP calculation tests

### Files Modified
- `tests/e2e/evaluate.sh` - Outputs SDP alongside raw scores
- `.github/workflows/ci.yml` - PR comments include SDP metrics
- Documentation updated (README, CONTRIBUTING, CI_CD, AUTO_SELF_UPDATE)

## [1.4.0] - 2026-01-26

### Added
- Auto-update system for staying current with Claude Code releases
- Daily workflow: monitors official releases, creates PRs for relevant updates
- Weekly workflow: scans community discussions, creates digest issues
- Analysis prompts with wizard philosophy baked in
- Version tracking files for state management

### How It Works
GitHub Actions check for Claude Code updates daily (official releases) and weekly (community discussions). Claude analyzes relevance to the wizard, and HIGH/MEDIUM confidence updates create PRs for human review. Most community content is filtered as noise - that's expected.

### Files Added
- `.github/workflows/daily-update.yml`
- `.github/workflows/weekly-community.yml`
- `.github/prompts/analyze-release.md`
- `.github/prompts/analyze-community.md`
- `.github/last-checked-version.txt`
- `.github/last-community-scan.txt`

### Required Setup
Add `ANTHROPIC_API_KEY` to repository secrets for workflows to function.

## [1.3.0] - 2026-01-24

### Added
- Idempotent wizard - safe to run on any existing setup
- Setup tracking comments in SDLC.md (version, completed steps, preferences)
- Wizard step registry for tracking what's been done
- Backwards compatibility for old wizard users

### Changed
- "Staying Updated" section rewritten for idempotent approach
- Update flow now checks plugins and questions, not just files
- One unified flow for setup AND updates (no separate paths)

### How It Works
The wizard now tracks completed steps in SDLC.md metadata comments. Old users running "check for updates" will be walked through only the new steps they haven't done yet.

## [1.2.0] - 2026-01-24

### Added
- Official plugin integration (claude-md-management, code-review, claude-code-setup)
- Step 0.1-0.4: Plugin setup before auto-scan
- "Leverage Official Tools" principle in Philosophy section
- Post-mortem learnings table (what goes where)
- Testing skill "After Session" section for capturing learnings
- Clear update workflow in "Staying Updated" section

### Changed
- Step 0 restructured: plugins first, then SDLC setup, then auto-scan
- Stay Lightweight section now includes official plugin table
- Clarified plugin scope: claude-md-management = CLAUDE.md only

### Files Affected
- `.claude/skills/testing/SKILL.md` - Add "After Session" section
- `SDLC.md` - Consider adding version comment

## [1.1.0] - 2026-01-23

### Added
- Tasks system documentation (v2.1.16+)
- $ARGUMENTS skill parameter support (v2.1.19+)
- Ike the cat easter egg (8 pounds, Fancy Feast enthusiast)
- Iron Man analogy for human+AI partnership

### Changed
- Test review preference: user chooses oversight level
- Shared environment awareness (not everyone runs isolated)

## [1.0.0] - 2026-01-20

### Added
- Initial SDLC Wizard release
- TDD enforcement hooks
- SDLC and Testing skills
- Confidence levels (HIGH/MEDIUM/LOW)
- Planning mode integration
- Self-review workflow
- Testing Diamond philosophy
- Mini-retro after tasks

