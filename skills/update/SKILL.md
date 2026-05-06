---
name: update-wizard
description: Smart update for SDLC wizard — shows changelog, compares files, lets you selectively adopt changes while preserving customizations.
argument-hint: [optional: check-only | force-all]
effort: high
---
# Update Wizard - Smart SDLC Update

## Task
$ARGUMENTS

## Purpose

Guided update assistant. Check what version the user has, show what changed, walk them through selectively adopting updates while preserving their customizations. **DO NOT blindly overwrite files.** Show diffs and let the user decide.

## MANDATORY FIRST ACTION: Read the Wizard Doc

**Before doing ANYTHING else**, use Read on `CLAUDE_CODE_SDLC_WIZARD.md` — specifically the "Staying Updated (Idempotent Wizard)" section near the end. This contains update URLs, version tracking format, and step registry. Do NOT proceed without reading it first.

## Execution Checklist

Follow steps IN ORDER. Do not skip or combine.

### Step 1: Read Installed Version

Read `SDLC.md` and extract from the metadata comment:
```
<!-- SDLC Wizard Version: X.X.X -->
<!-- Completed Steps: ... -->
```
No version comment → treat as `0.0.0` (suggest `/setup-wizard` instead).

### Step 1.5: Check CLI Version (ROADMAP #232)

The wizard files in the user's project are one half of the install. The other half is the **npm CLI** (`agentic-sdlc-wizard`) — the binary powering `npx agentic-sdlc-wizard init`/`check`/`complexity`. If the user ran `init` months ago, their npx cache (or global install) can be stuck on an old version even after `/update-wizard` patches the project files in-session. This step closes that gap.

**Detection — try both paths:**

1. **Global install** (rare): `npm ls -g agentic-sdlc-wizard --json --depth=0 2>/dev/null | jq -r '.dependencies["agentic-sdlc-wizard"].version // empty'`

2. **npx cache** (common): find every `package.json` under `~/.npm/_npx` matching `*agentic-sdlc-wizard*`, extract `.version`, pick the largest **by semver** (do NOT use `sort -u | tail -1` — lexicographic treats `1.9.0 > 1.10.0`). Use a Node `cmp()` helper: split on `-` for prerelease tag, compare numeric `major.minor.patch`, then prerelease ordering (`1.40.0-beta.1 < 1.40.0`). Read each version on its own line via stdin, track max, print at close. Empty input → empty output.

If both paths return empty, the user may be running from a custom install or never used `npx`. Treat as **undetectable** — note in the report but do not block. Skip the CLI bump prompt; continue to Step 2.

**Registry comparison:**
```bash
curl -fsS "https://registry.npmjs.org/agentic-sdlc-wizard/latest" | jq -r '.version'
```
Cache the result (also used in Step 3).

**Compare with semver-aware logic** — `sort -V` does NOT correctly order prereleases. Reuse the Node `cmp()` helper to produce exit `0` (installed < latest), `1` (installed > latest), `2` (equal).

**Surface the result:**
- `installed == latest` → silent, continue.
- `installed < latest` → show the gap with the upgrade options below.
- `installed > latest` (rare — pre-release/local dev) → silent, continue.

**Upgrade options when behind:**

> Your `agentic-sdlc-wizard` CLI is at **{installed}**, npm has **{latest}**. The in-session `/update-wizard` will refresh project files via Step 6, but your `npx` cache will keep the old CLI on disk for `npx agentic-sdlc-wizard check`/`init`/`complexity`.
>
> **A. Refresh just the CLI cache (recommended).** No project changes; Step 6 handles the rest with diffs:
> ```bash
> npx -y agentic-sdlc-wizard@latest --version
> ```
>
> **B. One-shot CLI + project re-init.** Refreshes CLI AND overwrites *non-settings* managed files (skills, hooks, templates) with latest. `settings.json` is smart-merged (custom hooks + permissions preserved); other managed files are NOT smart-merged — local edits are lost unless committed. Use only if no local skill/hook customizations:
> ```bash
> npx -y agentic-sdlc-wizard@latest init --force
> ```
>
> **C. Skip the CLI bump.** Keep stale CLI; this session's file updates apply but `npx ... check` keeps using old drift logic.
>
> Pick A, B, or C: `[A/B/C]` (default A)

If A: prompt the user to run the one-liner, then re-invoke `/update-wizard`. If B: same with the warning. If C: log the choice and continue.

**`check-only` precedence:** if the user passed `check-only`, Step 1.5 runs in report-only mode — print the gap if found, but do NOT prompt and do NOT run `init --force`. The check-only contract is "tell me what's drifted, don't change anything," and that supersedes the CLI bump path. **Graceful fallback** when CLI undetectable: skip the bump prompt, surface the unknown-state in the report, continue to Step 2.

**Why Step 1.5, not later:** subsequent steps shell out to `npx agentic-sdlc-wizard check` (Step 4). If the CLI is stale, Step 4 reports based on the OLD definition of managed files and may miss new templates entirely.

### Step 2: Fetch Latest CHANGELOG

WebFetch:
```
https://raw.githubusercontent.com/BaseInfinity/claude-sdlc-wizard/main/CHANGELOG.md
```
Extract latest version from the first `## [X.X.X]` line.

### Step 3: Compare Versions and Show What Changed

Parse CHANGELOG entries between the user's installed version and latest. Present a clear summary:

```
Installed: 1.42.0
Latest:    1.72.0

What changed:
- [1.72.0] #323 closed — customization-aware `check` recommendation + new `--preserve-customized` flag. `init --force --preserve-customized` skips CUSTOMIZED files (action `PRESERVE`), still OVERWRITEs MATCH and CREATEs MISSING. Default `init --force` unchanged. 10 tests.
- [1.71.0] token-bloat phase 3 — `skills/sdlc/SKILL.md` Cross-Model Review trimmed (~70 → ~20 lines, -427 tokens). Full protocol + examples moved to canonical `CLAUDE_CODE_SDLC_WIZARD.md` "Cross-Model Review Loop" section.
- [1.70.0] token-bloat fix phase 2 — `hooks/tdd-pretool-check.sh` TDD CHECK JSON nudge fires once per CC `session_id` instead of every src/ edit. Saves ~0.5-1.5K tokens/session.
- [1.69.0] token-bloat fix phase 1 — `hooks/sdlc-prompt-check.sh` BASELINE block fires once per CC `session_id`. Saves ~12K tokens/session.
- [1.68.0–1.65.0] roadmap hygiene — five paperwork closes: #97 Anthropic Policy NO-GO + AAR-paper validating parallel; #99 AutoGPT NO-GO; #95 Nous NO-GO; #243 token-history liveness verified; #210 Node-24 false-green; #235 Thoughtworks AI Evals NO-GO. **6/6 external-product audits NO-GO** (continues #76, #77). Research write-ups in `.reviews/research-*.md`.
- [1.64.0] XDLC ecosystem cross-references — README, wizard doc, and ROADMAP now cross-reference all three sibling packages (`agentic-sdlc-wizard`, `codex-sdlc-wizard`, `claude-gdlc-wizard`). New "Ecosystem (Sibling Projects)" section in README. 3 new doc-consistency tests prevent drift.
- [1.63.0] cache-cost observability closeout (#204 absorbed by #220) — `tests/test-token-spike.sh` gains explicit cache-miss regression test + negative-control test. SDLC skill + wizard doc gain "Cache-Cost Surprises" sections covering 10-20× silent cost blowups (mid-session CLAUDE.md edits, idle pruning, upstream cache bugs) and detection via `hooks/token-spike-check.sh`'s `costly_tokens` metric.
- [1.62.0] roadmap hygiene + #211 backfill — closes paperwork-stale rows (#207, #211 historical, #215, #217, #78, #79, #80, #219). Backfilled 5 corrupted `score-history.jsonl` rows from `max_score:10` → `max_score:11` (UI scenarios with design_system criterion). Codex strategic review confirmed scope.
- [1.61.0] calibration scenarios for #96 Phase 3 PR 2 — `tests/e2e/scenarios/calibration-careful-read.md` (parsePrice with 5 edge-case formats) tests whether self-review catches missed requirements. Score delta between SDLC and naive agents on this scenario is a calibration signal for `lift-proof.sh`
- [1.60.0] wizard-installation lift-proof harness (#96 Phase 3 PR 1) — `tests/e2e/lift-proof.sh` runs same scenario on bare vs wizard-installed fixture, emits score delta. Closes the "does the wizard work?" question. Honestly zero-API (sim + eval on Max)
- [1.59.0] evaluator on Max via `claude --print` (#228) — `EVAL_USE_CLI=1` swaps `evaluate.sh`'s per-criterion judge transport from `curl` → API to `claude --print --output-format json`. local-shepherd.sh sets it by default, so the local path is honestly zero-API
- [1.58.0] ground-truth gate for E2E benchmark (#96 Phase 2) — `tests/e2e/ground-truth.sh` runs `npm test` post-sim; final score capped at 5 if tests fail. Catches "agent followed protocol but produced broken code"
- [1.57.0] de-coach E2E benchmark prompt (#96 Phase 1) — remove answer-key leakage that saturated benchmark scores at 10/10; new neutral task framing measures organic SDLC behavior
- [1.56.0] community feature-discovery fetcher (#207) — `tests/e2e/fetch-community.sh` pulls Reddit + HN; pipe to `scan-community.sh` to surface candidate /slash-commands
- [1.55.0–1.51.0] ROADMAP #231 weekly-update.yml dismantle (Phase 2 → Phase 4): five releases, each deleting a cron-API job in favor of manual local-Max replacements. End state: weekly-update.yml shrunk from ~1670 → 161 lines (-90%), zero API spend, only `check-updates` release detection survives.
... (older entries omitted — read the full CHANGELOG.md for anything pre-1.51.0)
```

Read the actual entries from the fetched CHANGELOG; don't paraphrase. The user wants to see exactly what shipped.

**If versions match:** Step 7.7 (global plugin-registration cleanup) is independent of wizard file versions — it must run even when the user is up-to-date. The `check-only` flag still gates whether cleanup is *applied*:

- **Without `check-only`**: Run Step 7.7 in normal mode (detect, prompt, apply) before stopping. Then say "You're up to date! (version X.X.X)" and stop. Do not run Steps 4–10; only Step 7.7 fires on match.
- **With `check-only`**: Run Step 7.7 in detection-only mode — report any dead plugin registrations, but do NOT prompt and do NOT mutate `~/.claude/settings.json`. Then say "You're up to date! (version X.X.X)" and stop.

**If user passed `check-only` and versions don't match:** Stop after showing what changed. Do not apply anything.

### Step 4: Run Drift Detection

```bash
npx agentic-sdlc-wizard check
```
Reports each managed file as MATCH, CUSTOMIZED, MISSING, or DRIFT.

### Step 5: Fetch Latest Wizard Doc

WebFetch:
```
https://raw.githubusercontent.com/BaseInfinity/claude-sdlc-wizard/main/CLAUDE_CODE_SDLC_WIZARD.md
```
Source of truth for all templates, hooks, skills, step registry.

### Step 6: Per-File Update Plan

| Status | Action |
|--------|--------|
| MATCH | Skip — already current |
| MISSING | Recommend install — explain what the file does |
| CUSTOMIZED | Show what changed in latest vs user's version. Ask: adopt, skip, or merge? |
| DRIFT | Flag the issue (e.g., missing executable permission). Offer to fix |

Read both the installed file and the latest template. Present a human-readable summary of differences — what was added/changed/removed and why, NOT a raw diff.

**If user passed `force-all`:** skip per-file approval, apply all updates.

### Step 7: settings.json (Smart Merge Only)

NEVER overwrite. Read user's current settings.json, compare to latest template's hook definitions, describe what changed (added/updated/removed), offer to merge: update wizard hooks while preserving all custom hooks, permissions, and other settings.

CLI's `init --force` already has smart-merge logic. If manual merge gets complicated, suggest: `npx agentic-sdlc-wizard init --force` (preserves custom hooks).

### Step 7.5: Model Pin Migration (Issue #198)

Wizard 1.31.0–1.33.x unconditionally wrote `"model": "opus[1m]"` and `"env": { "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "30" }` to `.claude/settings.json`. Issue #198 flipped that to opt-in because a top-level `model` disables Claude Code's auto-mode.

Check user's `.claude/settings.json`:

1. **`model: "opus[1m]"` AND `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "30"`** — likely the old wizard-installed pair, not an intentional choice. Ask:
   > Your `.claude/settings.json` pins `model: "opus[1m]"` with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30`. This pair was the wizard default in 1.31.0–1.33.x, but it disables Claude Code's auto-mode (issue #198).
   > - **Remove the pin** (recommended) — keeps auto-mode enabled
   > - **Keep the pin** — guaranteed Opus 4.7 + 1M, OK with no auto-selection
   > Remove, keep, or decide later? `[r/k/l]`

2. **Only one of the two fields matches** — treat as intentional customization. Do not prompt.
3. **`model: "sonnet[1m]"`** (mixed-mode tier, #233, v1.38.0+) — explicit user choice. Mention in summary: "Detected mixed-mode tier (Sonnet coder + flagship reviewer). Cross-model review still uses Opus / gpt-5.5."
4. **Other `model` value** (`sonnet`, `opus`) — explicit user choice. Do not touch.
5. **Neither field set** — already on new default.

When removing: drop `model` (and `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` if `env` becomes empty). Never touch other keys.

### Step 7.6: `allowedTools` → `permissions.allow` Migration (Issue #197)

Pre-#197 wizard guided users to write a top-level `allowedTools` array. Claude Code silently disables auto-mode when that key is present, even with `defaultMode: "auto"`.

If user's `.claude/settings.json` has top-level `allowedTools`, offer migrate:

1. **Only `allowedTools`** (no `permissions.allow`) — ask:
   > Your `.claude/settings.json` has top-level `allowedTools` (silently disables auto-mode, issue #197). Successor: `permissions.allow`.
   > - **Migrate** (recommended): move all entries into `permissions.allow`, remove the legacy key
   > - **Keep** — specific reason for legacy key
   > - **Later** — don't touch now
   > `[m/k/l]`

2. **Both `allowedTools` AND `permissions.allow` present** — flag: lists may have diverged. Show both arrays. On migrate, **append every entry from `allowedTools` to the end of `permissions.allow`** byte-for-byte (preserve order within each list), then drop `allowedTools`. **Do NOT dedup.** Same string in both lists stays in both — CC treats duplicates as no-op, but dedup would silently remove user data the user might have intended. If user explicitly asks to dedup, that's a separate follow-up edit.

3. **Only `permissions.allow`** — already on new shape.
4. **Neither** — no action.

Preserve every entry byte-for-byte; only the container key changes. Do not reorder, dedup, or expand wildcards. Other top-level keys never touched.

### Step 7.7: Dead Plugin Registration Cleanup (Global Settings)

Wizard installs sometimes leave dead plugin registrations in **global** `~/.claude/settings.json` after the underlying plugin directory is renamed/disabled/removed. Symptom: every CC session emits `UserPromptSubmit hook error: Failed to run: Plugin directory does not exist: <path> ... run /plugin to reinstall`. Harmless but bleeds into every prompt across every project until cleaned up.

This step is **global-settings-only** (`~/.claude/settings.json`, not project's). Update normally avoids global; this is the one exception, only when the marketplace name matches an exact wizard-owned identifier.

**Wizard-owned marketplace allowlist** (exact match — wildcards risk eating third-party `sdlc-wizard-tools` if such a thing ships):

- `sdlc-wizard-local`
- `sdlc-wizard-wrap`

If `cli/init.js` later adds wizard marketplace names, append verbatim.

**Detection:**

1. Read `~/.claude/settings.json`, parse as JSON.
2. For each `extraKnownMarketplaces[key]` where `key` is in the allowlist:
   - Verify `entry.source.source === "directory"` AND `typeof entry.source.path === "string"`. Either guard fails → skip (not the wizard's shape).
   - Resolve `source.path` (expand `~`). If the resolved path **does not exist**, mark **dead**.
3. For every dead marketplace `<name>`, look for `enabledPlugins["sdlc-wizard@<name>"]` — also flag for removal.
4. Repeat for **all** allowlist entries; collect the full set of dead pairs before prompting (multiple are common).

**Cleanup (always ask, all-or-nothing per response):**

> Your `~/.claude/settings.json` references wizard plugin marketplaces that don't exist on disk:
>
> - `extraKnownMarketplaces.sdlc-wizard-local.source.path` → `<resolved-path>` (missing)
> - `enabledPlugins["sdlc-wizard@sdlc-wizard-local"]` is `true`
> - (list all dead pairs)
>
> Causes `Plugin directory does not exist` on every prompt in every CC session.
>
> Drop these entries from `~/.claude/settings.json`? `[y/N]`

If yes:
1. **Backup with timestamp**: `cp ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%Y%m%dT%H%M%S)` (two cleanups same day don't overwrite each other).
2. **Single `jq` filter** dropping every dead marketplace + every dead `enabledPlugins` key in one pass: `jq 'del(.enabledPlugins["sdlc-wizard@sdlc-wizard-local"]) | del(.extraKnownMarketplaces["sdlc-wizard-local"]) | del(.enabledPlugins["sdlc-wizard@sdlc-wizard-wrap"]) | del(.extraKnownMarketplaces["sdlc-wizard-wrap"])'` — include only keys actually marked dead.
3. Write to a temp file, validate with `jq empty` (round-trip parse), then `mv`. Validation fails → restore from backup.
4. **Formatting note**: `jq` rewrites the whole file. Wizard does NOT preserve comments/trailing commas (CC's settings.json is strict JSON, so safe today). Tell the user.

If no: skip silently. Some users have a recovery plan (re-enable, reinstall).

**Idempotency:** rerunning Step 7.7 after a clean must be a no-op. Only marketplaces with allowlist match AND missing path qualify.

**Scope guard:** only entries whose marketplace name matches the exact allowlist. Third-party plugin registrations (`legal@knowledge-work-plugins`, etc.) and unrelated `sdlc`-prefixed marketplaces (e.g. `danielscholl/claude-sdlc`) are never the wizard's business.

**Why update, not setup:** setup runs once at install; plugin paths are valid by definition. Dead registrations only appear later, when something disables/renames/deletes the plugin directory. Update is the natural seam.

**Runs regardless of version match:** Step 7.7 is global-settings hygiene, not file-update logic. Must run even when wizard version matches latest (per Step 3 match-branch). Gating Step 7.7 on version mismatch would silently leave the error firing forever.

**`check-only` precedence:** if `check-only` is set (whether versions match or not), Step 7.7 runs in detection-only mode: report dead registrations, do NOT prompt, do NOT execute `jq`, do NOT touch `~/.claude/settings.json`. Check-only must never mutate state.

### Step 8: Apply Selected Changes

For each approved file: Edit (existing) or Write (MISSING). For settings.json, apply the merge from Step 7.

### Step 9: Bump Version Metadata

Update `SDLC.md`:
```
<!-- SDLC Wizard Version: X.X.X -->
<!-- Completed Steps: step-0.1, step-0.2, ..., step-update-wizard -->
```
Set to latest version. Update completed steps if new ones applied.

### Step 10: Verify

```bash
npx agentic-sdlc-wizard check
```
All updated files should show MATCH. User-skipped files still show CUSTOMIZED — that's fine.

## Rules

1. **NEVER modify CLAUDE.md.** Fully custom to user's project. Wizard never touches it.
2. **NEVER auto-apply without showing what will change first** (unless `force-all`).
3. **Offline fallback:** WebFetch fails → tell user "Cannot reach GitHub. Run `npx agentic-sdlc-wizard init --force` to update from your locally installed CLI."
4. **First-time users:** SDLC.md missing or no version metadata → suggest `/setup-wizard`.
5. **Respect customizations.** CUSTOMIZED files are intentional — show what's different, let them decide. Don't pressure.
6. **Reference the wizard doc** for full protocol details (step registry, URLs, version tracking) rather than hardcoding.
