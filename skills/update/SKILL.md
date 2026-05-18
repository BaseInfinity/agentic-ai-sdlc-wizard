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

You are a guided update assistant. Your job is to check what version the user has, show what changed, and walk them through selectively adopting updates while preserving their customizations. DO NOT blindly overwrite files. Show diffs and let the user decide.

## MANDATORY FIRST ACTION: Read the Wizard Doc

**Before doing ANYTHING else**, use the Read tool to read the `CLAUDE_CODE_SDLC_WIZARD.md` file — specifically the "Staying Updated (Idempotent Wizard)" section near the end. This contains the update URLs, version tracking format, and step registry you need. Do NOT proceed without reading it first.

## Execution Checklist

Follow these steps IN ORDER. Do not skip or combine steps.

### Step 1: Read Installed Version

Read `SDLC.md` and extract the version from the metadata comment:
```
<!-- SDLC Wizard Version: X.X.X -->
```
If no version comment exists, treat as `0.0.0` (first-time setup — suggest running `/setup-wizard` instead).

Also note the completed steps from `<!-- Completed Steps: ... -->`.

### Step 1.5: Check CLI Version (ROADMAP #232)

The wizard files in the user's project (skills, hooks, settings.json) are one half of the install. The other half is the **npm CLI** (`agentic-sdlc-wizard`) — the binary that powers `npx agentic-sdlc-wizard init`, `check`, and `complexity`. If the user ran `npx agentic-sdlc-wizard init` months ago, their npx cache (or global install) can be stuck on an old version even after `/update-wizard` patches the project files in-session. This step closes that gap: detect the locally installed CLI version, compare to the npm registry latest, and surface a one-shot upgrade BEFORE running drift detection or per-file updates.

**Detection — try both paths, in order:**

1. **Global install** (rare but possible): `npm ls -g agentic-sdlc-wizard --json --depth=0 2>/dev/null | jq -r '.dependencies["agentic-sdlc-wizard"].version // empty'` — emits the version if globally installed, empty otherwise.

2. **npx cache** (the common case): find every `package.json` in npx's cache layout, extract `.version`, then pick the largest by semver. Do NOT use `sort -u | tail -1` — that's lexicographic and treats `1.9.0 > 1.10.0`. Use Node's built-in semver-aware compare:

   ```bash
   find ~/.npm/_npx -maxdepth 4 -name 'package.json' -path '*agentic-sdlc-wizard*' 2>/dev/null \
     | xargs -I{} jq -r '.version' {} 2>/dev/null \
     | node -e "
       let max = '';
       require('readline').createInterface({input: process.stdin}).on('line', v => {
         if (!v) return;
         if (!max || cmp(v, max) > 0) max = v;
       }).on('close', () => process.stdout.write(max));
       function cmp(a, b) {
         const [ab, ap] = a.split('-'), [bb, bp] = b.split('-');
         const an = ab.split('.').map(Number), bn = bb.split('.').map(Number);
         for (let i = 0; i < 3; i++) if (an[i] !== bn[i]) return an[i] - bn[i];
         if (ap && !bp) return -1; if (!ap && bp) return 1;
         if (ap && bp) return ap < bp ? -1 : ap > bp ? 1 : 0;
         return 0;
       }
     "
   ```

   This reads each found version on its own line, compares pairwise with semver semantics (numeric major.minor.patch, plus prerelease tags ordered as `1.40.0-beta.1 < 1.40.0`), and prints the maximum. Empty input prints empty.

If both paths return empty, the user may be running from a custom install or has never used `npx`. Treat as **undetectable** — note it in your update report but do not block the rest of the flow. Skip the CLI bump prompt, continue to Step 2.

**Registry comparison:**

```bash
curl -fsS "https://registry.npmjs.org/agentic-sdlc-wizard/latest" | jq -r '.version'
```

This is the same endpoint the registry serves; the response is a single JSON object with `version` set to the published latest tag. Cache the result (it's also used in Step 3 for the wizard version comparison).

**Compare with semver-aware logic** — `sort -V` does NOT correctly order prereleases (it places `1.40.0-beta.1` *after* `1.40.0`, but semver requires the opposite). Use the same Node `cmp()` helper from the npx-cache step:

```bash
node -e "
  const a = process.argv[1], b = process.argv[2];
  function cmp(a, b) { /* same body as above */ }
  process.exit(cmp(a, b) < 0 ? 0 : cmp(a, b) > 0 ? 1 : 2);
" "$INSTALLED" "$LATEST"
# Exit 0 = installed < latest (behind); 1 = installed > latest; 2 = equal
```

**Surface based on the result:**

- `installed == latest` → silent, continue to Step 2.
- `installed < latest` → surface the gap with the upgrade options below.
- `installed > latest` (rare — pre-release or local dev install) → silent, continue.

**Upgrade options when behind:** be honest about what each does. Recommend the safer path by default.

  > Your locally installed `agentic-sdlc-wizard` CLI is at **{installed}**, but npm has **{latest}**. The in-session `/update-wizard` will refresh this project's files via Step 6's per-file plan, but your `npx` cache will keep the old CLI on disk for `npx agentic-sdlc-wizard check`/`init`/`complexity` calls.
  >
  > Pick one:
  >
  > **A. Refresh just the CLI cache (recommended).** Doesn't touch your project files. Then `/update-wizard`'s per-file plan handles the rest with diffs:
  > ```bash
  > npx -y agentic-sdlc-wizard@latest --version
  > ```
  >
  > **B. One-shot CLI + project re-init.** Refreshes the CLI AND overwrites *non-settings* managed files (skills, hooks, templates) with the latest versions. `settings.json` is smart-merged (custom hooks + permissions preserved); other managed files are NOT smart-merged — local edits to them are lost unless committed to git or backed up. Use this if you don't have local skill/hook customizations:
  > ```bash
  > npx -y agentic-sdlc-wizard@latest init --force
  > ```
  >
  > **C. Skip the CLI bump entirely.** Keep the stale CLI; this session's file updates apply but `npx agentic-sdlc-wizard check` will keep using the old drift logic.
  >
  > Pick A, B, or C: `[A/B/C]`

  If A: prompt the user to run the one-liner in their shell, then re-invoke `/update-wizard`. If B: same, with the warning about non-settings overwrite. If C: log the choice and continue with in-session file updates only. Default (no response) → A.

**`check-only` precedence:** if the user passed `check-only`, Step 1.5 runs in report-only mode — print the gap if found, but do NOT prompt and do NOT run `init --force`. The check-only contract is "tell me what's drifted, don't change anything," and that supersedes the CLI bump path.

**Why this lives at Step 1.5, not later:** subsequent steps shell out to `npx agentic-sdlc-wizard check` (Step 4) and rely on the CLI's drift heuristics. If the CLI is stale, Step 4 reports based on the OLD definition of "managed files" and may miss new templates entirely. Detecting + surfacing CLI staleness up front lets the user choose whether to refresh first.

### Step 2: Fetch Latest CHANGELOG

Use WebFetch to fetch the CHANGELOG:
```
https://raw.githubusercontent.com/BaseInfinity/claude-sdlc-wizard/main/CHANGELOG.md
```

Extract the latest version from the first `## [X.X.X]` line.

### Step 3: Compare Versions and Show What Changed

Parse all CHANGELOG entries between the user's installed version and the latest. Present a clear summary:

```
Installed: 1.24.0
Latest:    1.43.0

What changed:
- [1.43.0] Quick-wins bundle. (a) #226 weekly-update.yml wording cleanup — Tier 2 step renamed from "Full Statistical (5 trials)" to "Judge-Consistency Band (5× judge re-score)"; matches the existing methodology caveat at line 701. No statistical-language drift left in the workflow itself. (b) #227 score-history.txt churn — community-pattern PRs no longer ship empty `.txt`-only diffs. `weekly-update.yml` Update-CUSUM steps now write to `score-history.jsonl` (canonical) via `--add-json`, not `score-history.txt` (legacy). Regression test added to `tests/test-workflow-triggers.sh`. (c) #338 skill-precedence preamble — `skills/sdlc/SKILL.md` now opens with a "Skill source & precedence" block clarifying that repo-local `.claude/skills/` wins over global `~/.claude/skills/`. (d) #219 model-pin re-verification — CC 2.1.117 startup-header + restart-persistence behavior confirmed orthogonal to our no-pin-default recommendation. Setup skill Step 9.5 now documents the interaction. (e) #337 `--yolo` audit — verified zero `--full-auto` references repo-wide; no audit-worthy hits. (f) #339 — triaged 5 Anthropic API changelog entries (Multiagent sessions, Sonnet 4.5/4 1M retired, Rate Limits API, Managed Agents memory, Haiku 3 retired); all out-of-scope or N/A for SDLC wizard. (g) #235(a)+(b) `/insights` complementary-tool guidance — surfaced unshipped #206 research action. Setup skill Step 12 + wizard doc "Complementary Tools" section now both cite `/insights` (native CC v2.1.101+) with explicit qualitative-only caveat (does NOT replace #220 token-spike detection). `/insights` added to `tests/e2e/known-slash-commands.txt` so community scanner #207 stops flagging it. Codex CERTIFIED 8/10. #235(c) re-research checkpoint deferred to v1.44.
- [1.42.1] CI hygiene fix — skip Claude PR review on wizard self-PRs. 7 self-PRs (v1.39.0–v1.42.0) had shipped with red `review` job (API canary firing on dead credit balance). Treated as "expected" but red normalizes red. Workflow `if:` now skips review on `BaseInfinity/claude-sdlc-wizard` repo only; consumer projects unaffected. 7 quality tests, mutation-verified (== inversion fails).
- [1.42.0] AGENTS.md interop detection — ROADMAP #205 phase (a). Setup wizard auto-scan now lists AGENTS.md (cross-tool agent-instructions standard, CC issue #6235); new Step 4.5 surfaces a 3-way decision (dual-maintain / merge / skip) when AGENTS.md is detected. Phase (b) write-fresh and phase (d) drift-test deferred. 7 quality tests.
- [1.41.1] MCP-tool hooks audit — ROADMAP #218. Audited all 5 wizard hooks against CC 2.1.118's `type: "mcp_tool"` migration option; conclusion: all stay bash (portability to Codex/OpenCode siblings + exit-code gating semantics rule out MCP). Per-hook rationale documented under "Known CC Gotchas → MCP-tool hooks audit". 7 quality tests.
- [1.41.0] Post-mortem 2026-04-23 lessons folded into wizard — ROADMAP #221. New "Known CC Gotchas" section documents extended-thinking + caching + idle-session failure mode. Recommended Effort section cites the post-mortem as third-party evidence ("don't rely on CC default — set effort yourself"). Brevity-cap audit clean, regression guard added. 7 quality tests.
- [1.40.1] cleanupPeriodDays: 30 pinned in template — ROADMAP #225. CC 2.1.117 expanded `cleanupPeriodDays` to also cover `~/.claude/tasks/`. Aggressive defaults could prune in-progress TodoWrite checklists for paused long-running features. Wizard now ships a 30-day floor + documented gotcha. 7 quality tests.
- [1.40.0] CLI version detection in /update-wizard — ROADMAP #232. New Step 1.5 detects locally installed `agentic-sdlc-wizard` CLI version (npm ls + npx cache inspection, both with semver-aware ordering), compares to `registry.npmjs.org/agentic-sdlc-wizard/latest`, and surfaces a 3-way upgrade choice BEFORE drift detection: A) refresh CLI cache only (default, safest), B) `init --force` re-init with explicit non-settings overwrite warning, C) skip. Closes the gap where in-session file updates landed but the user's stale npx cache kept running an old CLI. Mirrors `claude update` UX. 8 quality tests, mutation-verified.
- [1.39.1] Step 7.7 hoist — dead-plugin cleanup now runs even when wizard versions match. Previously `/update-wizard` exited at "you're up to date" before reaching Step 7.7, so users on the latest wizard with a stale `~/.claude/settings.json` plugin registration were never offered cleanup. New `tests/test-update-skill-step-7-7.sh` (8 quality tests) guards the ordering.
- [1.39.0] Community feature-discovery scanner — ROADMAP #207. `tests/e2e/scan-community.sh` extracts unknown `/slash-command` mentions from transcript text (Reddit / HN / Discord exports), dedupes against `tests/e2e/known-slash-commands.txt` allowlist, emits JSON digest of candidates with count + sample. Replaces the deleted CI scan-community job (per #231 Phase 3) with a maintainer-runnable offline scan. 14 quality tests.
- [1.38.0] Mixed-mode tier (Sonnet 4.6 coder + Opus 4.7 reviewer) for simple repos — ROADMAP #233. New `cli/lib/repo-complexity.js` heuristic + `npx agentic-sdlc-wizard complexity .` CLI command. Setup Step 9.5 expanded from binary y/N to 3-way (no-pin / mixed / flagship). Cross-model review always stays at flagship regardless of coder pin. Reconciles with #198: mixed-mode is opt-in per-project; no-pin remains the default. Plus ROADMAP #224 prompt-hook-fires-once instrumentation (opt-in `SDLC_HOOK_FIRE_LOG`).
- [1.37.1] Token-bloat fix: dedupe 2× SDLC BASELINE print when both project + plugin register the same hook (~300 tokens doubled per prompt). 5 hooks gain `dedupe_plugin_or_project()` helper. Codex 2-round 100/100.
- [1.37.0] `monthly-research.yml` workflow deleted (ROADMAP #231 Phase 1) — 0 merged artifacts in 30d while burning $11-23/month; research happens inline now. `model-effort-check.sh` loud WARNING below xhigh (#217) — max preferred, xhigh floor; duplicate effort nudge in `instructions-loaded-check.sh` removed; single source of truth. Both changes Codex-certified.
- [1.36.1] Repo renamed `agentic-ai-sdlc-wizard` → `claude-sdlc-wizard` (matches sibling pattern; npm package unchanged); `npm pkg fix` metadata cleanup; slug migration across docs/tests/configs
- [1.36.0] CC 2.1.118 `/usage` canonical + aliases, Tier 2 dead-gate fix (#215), score-history max_score correctness (#211), setup-bun regression guard (#210), post-mortem learnings (#220-222), GPT-5.5 adoption plan (#223), MCP-tool hooks + #198 re-verify in backlog (#218/#219)
- [1.35.0] PreCompact seam gate + self-heal (#208/#209), effort auto-bump on LOW/FAILED/CONFUSED (#195), wizard staleness nudge (#196), Codex CI-log audit pattern, ...
- [1.34.0] API feature detection shepherd for Claude releases, Memory Audit Protocol with 7 verified lessons (+2 caught-and-retracted), /less-permission-prompts surfaced, ...
- [1.33.0] opus[1m] as SDLC default, dual-channel install drift guardrails, model/effort session-start nudge, ...
- [1.32.0] Opus 4.7 + xhigh support, model/effort upgrade detection, benchmark ceiling audit, ...
- [1.31.0] Hook false-positive fix for non-SDLC dirs, ephemeral marketplace path warning, ...
- [1.30.0] Firmware fixture, model A/B comparison workflow, CC degradation detection, ...
- [1.29.0] Node 24 compliance, autocompact in settings.json, effectiveness scoreboard, ...
- [1.28.0] Autocompact benchmarking methodology, canary fact mechanism, benchmark harness, ...
- [1.27.0] Domain-adaptive testing diamond, 3 domain fixtures, 25 quality tests, ...
- [1.26.0] Codex SDLC Adapter plan, claw-code/OmO/OmX research, CC feature discovery verified, ...
- [1.25.0] Plugin format, 6 distribution channels (curl, Homebrew, gh, GitHub Releases), ...
- [1.24.0] Hook if conditionals, autocompact tuning + 1M/200K guidance, tdd_red fix, ...
```

**If versions match:** Step 7.7 (global plugin-registration cleanup) is independent of wizard file versions — it must run even when the user is already up-to-date. The `check-only` flag still gates whether cleanup is *applied*:

- **Without `check-only`**: Run Step 7.7 in normal mode (detect, prompt, apply) before stopping. Then say "You're up to date! (version X.X.X)" and stop. Do not run Steps 4–10; only Step 7.7 fires on match.
- **With `check-only`**: Run Step 7.7 in detection-only mode — report any dead plugin registrations found, but do NOT prompt the user and do NOT mutate `~/.claude/settings.json`. Then say "You're up to date! (version X.X.X)" and stop.

**If user passed `check-only` and versions don't match:** Stop after showing what changed. Do not apply anything (file updates, settings cleanup, version bumps).

### Step 4: Run Drift Detection

Run the CLI drift checker to see per-file status:
```bash
npx agentic-sdlc-wizard check
```

This reports each managed file as MATCH, CUSTOMIZED, MISSING, or DRIFT. Present the results.

### Step 5: Fetch Latest Wizard Doc

Use WebFetch to fetch the latest wizard:
```
https://raw.githubusercontent.com/BaseInfinity/claude-sdlc-wizard/main/CLAUDE_CODE_SDLC_WIZARD.md
```

This is the source of truth for all templates, hooks, skills, and step registry.

### Step 6: Present Per-File Update Plan

For each managed file from the `sdlc-wizard check` output:

| Status | Action |
|--------|--------|
| MATCH | Skip — already current |
| MISSING | Recommend install — show what the file does |
| CUSTOMIZED | Show what changed in latest vs user's version. Ask: adopt, skip, or merge? |
| DRIFT | Flag the issue (e.g., missing executable permission). Offer to fix |

Read both the installed file and the latest template content. Present a human-readable summary of differences — not a raw diff, but "what was added/changed/removed and why."

**If user passed `force-all`:** Skip per-file approval and apply all updates.

### Step 7: Handle settings.json Specially

NEVER overwrite settings.json. Instead:

1. Read the user's current settings.json
2. Compare against the latest template's hook definitions
3. Describe what hooks changed (added, updated, removed)
4. Offer to merge: update wizard hooks while preserving all custom hooks, permissions, and other settings

The CLI's `init --force` already has smart merge logic for settings.json. If the manual merge gets complicated, suggest: `npx agentic-sdlc-wizard init --force` (it preserves custom hooks).

### Step 7.5: Model Pin Migration (Issue #198)

Wizard versions 1.31.0–1.33.x unconditionally wrote `"model": "opus[1m]"` and `"env": { "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "30" }` to `.claude/settings.json`. Issue #198 flipped that to opt-in because a top-level `model` disables Claude Code's auto-mode for the session.

If the user is upgrading from a pre-#198 version, check their `.claude/settings.json`:

1. **If `model` is `"opus[1m]"` and `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` is `"30"`** — this is likely the old wizard-installed pair, not an intentional user choice. Ask:

   > Your `.claude/settings.json` pins `model: "opus[1m]"` with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30`.
   > This pair was the SDLC wizard default in 1.31.0–1.33.x, but it disables Claude Code's auto-mode (see issue #198).
   >
   > - **Remove the pin** (recommended for most users) — keeps auto-mode enabled, lets Claude Code pick the model per turn.
   > - **Keep the pin** — you want guaranteed Opus 4.7 + 1M context, and you're OK giving up model auto-selection.
   >
   > Remove, keep, or decide later? `[r/k/l]`

2. **If only one of the two fields matches** (e.g. `model: "opus[1m]"` but custom autocompact, or vice versa) — treat as intentional customization. Do not prompt.

3. **If `model` is `"sonnet[1m]"` (mixed-mode tier, roadmap #233, v1.38.0+)** — treat as user's explicit mixed-mode choice. Do not prompt; this is the supported mixed-mode pin. Mention in the upgrade summary: "Detected mixed-mode tier (Sonnet coder + flagship reviewer). Cross-model review still uses Opus / gpt-5.5 — see CLAUDE_CODE_SDLC_WIZARD.md → 'Mixed-Mode Tier'."

4. **If `model` is some other value** (e.g. `"sonnet"`, `"opus"`) — treat as user's explicit choice. Do not touch.

5. **If neither field is set** — user is already on the new default. No action.

When removing: edit the file in place, drop the `model` key (and the `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` key if nothing else is in `env`, otherwise leave `env` alone). Never touch other keys the user added.

### Step 7.6: `allowedTools` → `permissions.allow` Migration (Issue #197)

Wizard versions before #197 guided users to write a top-level `allowedTools` array in `.claude/settings.json`. Claude Code silently disables its auto-mode classifier when that key is present, even with `defaultMode: "auto"` set globally.

If the user's `.claude/settings.json` has a top-level `allowedTools` array, offer to migrate:

1. **If only `allowedTools` is present** (no `permissions.allow`) — ask:

   > Your `.claude/settings.json` has a top-level `allowedTools` array. This silently disables Claude Code auto-mode (see issue #197). The supported successor is `permissions.allow`, which accepts the same patterns but doesn't trip the auto-mode gate.
   >
   > - **Migrate** (recommended): move all entries into `permissions.allow`, remove the old `allowedTools`.
   > - **Keep** — you have a specific reason to use the legacy key.
   > - **Later** — don't touch it now.
   >
   > `[m/k/l]`

2. **If both `allowedTools` and `permissions.allow` are present** — flag it: the two lists may have diverged. Show both arrays to the user. On migrate, append every entry from `allowedTools` to the end of `permissions.allow` (preserving order within each list), then drop the legacy `allowedTools` key. **Do NOT dedup.** If the same string appears in both lists, it stays in both positions — Claude Code treats duplicate entries as a no-op, but dedup would silently remove user data that the user might have intended. If the user explicitly asks to dedup, do that as a separate follow-up edit.

3. **If only `permissions.allow` is present** — user is already on the new shape. No action.

4. **If neither is present** — no action.

When migrating: preserve every entry byte-for-byte; only the container key changes. Do not reorder, dedup, or expand wildcards. Other top-level keys (hooks, env, model, custom user fields) are never touched.

### Step 7.7: Dead Plugin Registration Cleanup (Global Settings)

Wizard installs sometimes leave dead plugin registrations in the user's **global** `~/.claude/settings.json` after the underlying plugin directory is renamed, disabled, or removed. Symptom: every Claude Code session emits `UserPromptSubmit hook error: Failed to run: Plugin directory does not exist: <path> ... run /plugin to reinstall`. The error is harmless but bleeds into every prompt across every project until cleaned up.

This step is **global-settings-only** (`~/.claude/settings.json`, not the project's `.claude/settings.json`). The update skill normally avoids global settings; this is the one exception, and only when the plugin marketplace name matches an exact wizard-owned identifier.

**Wizard-owned marketplace allowlist** (exact match, no wildcard — wildcards risk eating third-party plugins like `sdlc-wizard-tools` if such a thing ever ships):

- `sdlc-wizard-local`
- `sdlc-wizard-wrap`

If `cli/init.js` later registers additional wizard marketplace names, append them to this list verbatim.

**Detection:**

1. Read `~/.claude/settings.json` and parse as JSON.
2. For each `extraKnownMarketplaces[key]` where `key` is in the allowlist above:
   - Verify `entry.source.source === "directory"` AND `typeof entry.source.path === "string"`. If either guard fails, skip — not the shape the wizard installs (matches the type-check at `cli/init.js`).
   - Resolve the `source.path` (expand `~` if literal). If the resolved path **does not exist** on disk, mark the marketplace **dead**.
3. For every dead marketplace `<name>`, look for `enabledPlugins["sdlc-wizard@<name>"]` — also flag for removal.
4. Repeat for **all** allowlist entries; collect the full set of dead `(marketplace, enabledPlugins)` pairs before prompting. Multiple dead registrations are common (e.g. both `sdlc-wizard-local` and `sdlc-wizard-wrap` if the user reinstalled twice).

**Cleanup (always ask first, all-or-nothing per user response):**

> Your `~/.claude/settings.json` references wizard plugin marketplaces that don't exist on disk:
>
> - `extraKnownMarketplaces.sdlc-wizard-local.source.path` → `<resolved-path>` (missing)
> - `enabledPlugins["sdlc-wizard@sdlc-wizard-local"]` is `true`
> - (list all dead pairs from detection)
>
> This causes `Plugin directory does not exist` errors on every prompt in every Claude Code session until cleaned up.
>
> Drop the listed entries from `~/.claude/settings.json`? `[y/N]`

If the user says yes:
1. **Back up with timestamp**: `cp ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%Y%m%dT%H%M%S)` so two cleanups on the same day don't overwrite each other's backups.
2. **Build a single `jq` filter** that drops every dead marketplace and every dead `enabledPlugins` key in one pass: `jq 'del(.enabledPlugins["sdlc-wizard@sdlc-wizard-local"]) | del(.extraKnownMarketplaces["sdlc-wizard-local"]) | del(.enabledPlugins["sdlc-wizard@sdlc-wizard-wrap"]) | del(.extraKnownMarketplaces["sdlc-wizard-wrap"])'` (include only the keys actually marked dead in detection).
3. Write to a temp file, validate with `jq empty` (round-trip parse), only then replace `~/.claude/settings.json` with `mv`. If validation fails, restore from the backup.
4. **Formatting note**: `jq` rewrites the whole file and normalizes formatting. The wizard does NOT preserve comments, trailing commas, or other JSONC features — Claude Code's `settings.json` is strict JSON, so this is safe today, but say so to the user. If they care about preserving the exact diff, give them the manual `del()` filter and let them decide whether to apply it.

If the user says no: skip silently. Some users have a recovery plan (re-enable the renamed dir, reinstall, etc.).

**Idempotency:** Re-running Step 7.7 after a successful cleanup must be a no-op. Detection only flags marketplaces whose `source.path` is missing AND whose name is in the allowlist; both must be true, so a clean settings.json reports zero dead pairs.

**Scope guard:** only touch entries whose marketplace name matches the exact allowlist. Third-party plugin registrations (`legal@knowledge-work-plugins`, `claude-md-management@claude-plugins-official`, etc.) and unrelated `sdlc`-prefixed marketplaces (e.g. `danielscholl/claude-sdlc`) are never the wizard's business. Path-existence alone never qualifies a marketplace for cleanup — only allowlist + missing-path together do.

**Why this lives in the update skill, not setup:** setup runs once at install time, when the plugin paths are valid by definition. Dead registrations only appear later, when something disables/renames/deletes the plugin directory. Update is the natural seam to detect drift and offer cleanup.

**Runs regardless of version match:** Step 7.7 is global-settings hygiene, not file-update logic. It must run even when the wizard version on disk matches npm latest (per Step 3's match-branch instruction). A user can be on the latest wizard and still have a stale plugin registration from a previous install; gating Step 7.7 on version mismatch would silently leave that error firing on every prompt forever. If a future edit to Step 3 changes the match-branch flow, it must continue to invoke Step 7.7 before stopping.

**`check-only` precedence:** If the user passed `check-only` (whether versions match or not), Step 7.7 runs in detection-only mode: report dead plugin registrations if found, do NOT prompt the user, do NOT execute the jq cleanup, do NOT touch `~/.claude/settings.json`. The check-only contract takes precedence over the cleanup contract — a `check-only` invocation must never mutate state.

### Step 8: Apply Selected Changes

For each file the user approved:
- Use the Edit tool to update the file content
- For complete replacements (MISSING files), use Write
- For settings.json, apply the merge from Step 7

### Step 9: Bump Version Metadata

Update the version in `SDLC.md`:
```
<!-- SDLC Wizard Version: X.X.X -->
```
Set it to the latest version.

Also update the completed steps if new steps were applied:
```
<!-- Completed Steps: step-0.1, step-0.2, ..., step-update-wizard -->
```

### Step 10: Verify

Run drift detection again:
```bash
npx agentic-sdlc-wizard check
```

Report final status. All updated files should show MATCH. Files the user chose to skip will still show CUSTOMIZED — that's fine, it's their choice.

## Rules

1. **NEVER modify CLAUDE.md.** It is fully custom to the user's project. The wizard never touches it.
2. **NEVER auto-apply without showing what will change first** (unless `force-all` was passed).
3. **Offline fallback:** If WebFetch fails (network unavailable), tell the user: "Cannot reach GitHub. Run `npx agentic-sdlc-wizard init --force` to update from your locally installed CLI version instead."
4. **First-time users:** If SDLC.md doesn't exist or has no version metadata, suggest `/setup-wizard` instead of `/update-wizard`.
5. **Respect customizations.** When a file is CUSTOMIZED, the user made intentional changes. Show what's different and let them decide — don't pressure them to adopt the latest.
6. **Reference the wizard doc** for full protocol details (step registry, URLs, version tracking) rather than hardcoding values in this skill.
