---
name: sdlc
description: Full SDLC workflow for implementing features, fixing bugs, refactoring code, testing, releasing, publishing, and deploying. Use this skill when implementing, fixing, refactoring, testing, adding features, building new code, or releasing/publishing/deploying.
argument-hint: [task description]
effort: high
---
# SDLC Skill - Full Development Workflow

## Skill source & precedence

This skill is loaded from **`.claude/skills/sdlc/SKILL.md`** in the active repo (symlinked to `skills/sdlc/SKILL.md` in the wizard's source tree). Claude Code prefers repo-local skills over global (`~/.claude/skills/sdlc/SKILL.md`) when both exist with the same name — the repo-local copy is the project's authoritative workflow contract. Use global skills only for cross-repo personal tooling (e.g. `feedback`, `revise-claude-md`); use repo-local for implementation, tests, release, and verification in this repo.

If unsure which copy is active, compare `head -5 .claude/skills/sdlc/SKILL.md` against `head -5 ~/.claude/skills/sdlc/SKILL.md`. The repo-local copy wins. Don't mix guidance from both — pick the source for this repo and stay there.

## Task
$ARGUMENTS

Operational checklist. Full protocol lives in `CLAUDE_CODE_SDLC_WIZARD.md` — read it for depth.

## Full SDLC Checklist

Your FIRST action must be a TodoWrite covering every phase below. Compact form (omit `activeForm` to use the subject as the spinner label):

```
TodoWrite([
  // PLANNING
  { content: "Find and read relevant documentation", status: "in_progress" },
  { content: "Assess doc health - flag issues (ask before cleaning)", status: "pending" },
  { content: "DRY scan: What patterns exist to reuse? New pattern = get approval", status: "pending" },
  { content: "Prove It Gate: adding new component? Research alternatives, prove quality with tests", status: "pending" },
  { content: "Blast radius: What depends on code I'm changing?", status: "pending" },
  { content: "Design system check (if UI change)", status: "pending" },
  { content: "Restate task in own words - verify understanding", status: "pending" },
  { content: "Scrutinize test design - right things tested? Follow TESTING.md?", status: "pending" },
  { content: "Present approach + STATE CONFIDENCE LEVEL", status: "pending" },
  { content: "Signal ready - user exits plan mode", status: "pending" },
  // TRANSITION
  { content: "Doc sync: update or create feature doc — MUST be current before commit", status: "pending" },
  // IMPLEMENTATION
  { content: "TDD RED: Write failing test FIRST", status: "pending" },
  { content: "TDD GREEN: Implement, verify test passes", status: "pending" },
  { content: "Run lint/typecheck", status: "pending" },
  { content: "Run ALL tests", status: "pending" },
  { content: "Production build check", status: "pending" },
  // REVIEW
  { content: "DRY check: Is logic duplicated elsewhere?", status: "pending" },
  { content: "Visual consistency check (if UI change)", status: "pending" },
  { content: "Self-review: run /code-review", status: "pending" },
  { content: "Security review (if warranted)", status: "pending" },
  { content: "Cross-model review (if configured)", status: "pending" },
  { content: "Scope guard: only changes related to task? No legacy/fallback code left?", status: "pending" },
  // CI SHEPHERD
  { content: "Commit and push to remote", status: "pending" },
  { content: "Watch CI - fix failures, iterate until green (max 2x)", status: "pending" },
  { content: "Read CI review - implement valid suggestions, iterate until clean", status: "pending" },
  { content: "Meta-repo only: run local shepherd if PR needs E2E score (optional)", status: "pending" },
  { content: "Post-deploy verification (if deploy task)", status: "pending" },
  // FINAL
  { content: "Present summary: changes, tests, CI status", status: "pending" },
  { content: "Capture learnings (after session — TESTING.md, CLAUDE.md, or feature docs)", status: "pending" },
  { content: "Close out plan files: if task came from a plan, mark complete or delete", status: "pending" }
])
```

## SDLC Quality Checklist (Scoring Rubric)

| Criterion | Points | Critical? | What Counts |
|-----------|--------|-----------|-------------|
| task_tracking | 1 | | Use TodoWrite or TaskCreate |
| confidence | 1 | | State HIGH/MEDIUM/LOW |
| tdd_red | 2 | **YES** | Write/edit test files BEFORE implementation files |
| plan_mode_outline | 1 | | Outline steps before coding |
| plan_mode_tool | 1 | | Use TodoWrite/TaskCreate/EnterPlanMode |
| tdd_green_ran | 1 | | Run tests, show runner output |
| tdd_green_pass | 1 | | All tests pass in final run |
| self_review | 1 | **YES** | Read back files/diffs you modified |
| clean_code | 1 | | One coherent approach, no dead code |

**Total: 10 points** (11 for UI tasks, +1 for design_system check). Critical miss on `tdd_red` or `self_review` = process failure regardless of total score.

## Test Failure Recovery

**ALL TESTS MUST PASS. NO EXCEPTIONS.** Test code is app code. Failures are bugs — investigate them like a 15-year SDET, not by brushing aside.

Not acceptable: "those were already failing", "not related to my changes", "it's flaky" (flaky = bug we haven't found yet).

When tests fail:
1. Identify which test(s) failed
2. Diagnose WHY: your code broke it (regression — fix code), test is for deleted code (delete test), test has wrong assertions (fix test), "flaky" (investigate — race, shared state, env)
3. Fix appropriately, run specific test individually first, then run ALL tests
4. Still failing after 2 attempts? STOP and ASK USER

## Confidence Check (REQUIRED)

State your confidence before presenting an approach:

| Level | Meaning | Action | Effort |
|-------|---------|--------|--------|
| HIGH (90%+) | Know exactly what to do | Present, proceed after approval | `high` (default) |
| MEDIUM (60-89%) | Solid approach, some uncertainty | Present, highlight uncertainties | `high` |
| LOW (<60%) | Not sure | Research or try Codex; if still LOW, ASK USER | **`/effort xhigh` now** |
| FAILED 2x | Something's wrong | Codex for fresh perspective; if still stuck, STOP | **`/effort max` now** |
| CONFUSED | Can't diagnose | Codex; if still confused, STOP and describe | **`/effort max` now** |

**Dynamic effort bumping is NOT optional.** "Consider max effort" is the same as "ignore this." Bump BEFORE the next attempt, not after a third failure.

## Plan Mode

Use plan mode for: multi-file changes, new features, LOW confidence, bugs needing investigation. **Skip plan approval step** (auto-approval) when confidence HIGH (95%+) AND single-file/trivial AND no new patterns AND no architectural decisions — still announce approach, don't wait. When in doubt, wait.

## Long-Running Goals (`/goal`)

Native `/goal <condition>` (**v2.1.143+**). Haiku evaluator re-checks transcript per turn. **Confidence gate — NEVER invoke below HIGH 95%**; below that the evaluator rubber-stamps flailing as progress. **DLC binding — condition MUST name the DLC** (`/sdlc`, `/gdlc`, `/ldlc`, etc.) so the evaluator anchors on "doing it right." **Pre-flight:** trusted workspace; `disableAllHooks`/`allowManagedHooksOnly` both off. **Condition = contract:** end state + check + constraints + hard turn/time bound (no native cap); e.g. `/goal "tests pass + clean tree following /sdlc, stop after 20 turns"`. **Anti-pattern:** evaluator can't call tools — transcript-only. `--resume` resets counters.

## Recommended Model

**Opt-in: `opus[1m]` (Opus 4.8 with 1M context).** `/model opus[1m]` at the start of non-trivial sessions — understand the tradeoff (issue #198). A top-level `model` pin in `.claude/settings.json` disables CC's per-turn auto-selection; pin only when you need 1M headroom. Requires CC v2.1.154+.

**Pair with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30` when you opt in.** Without it, the default fires at ~76K on 1M. **Pick ONE — do NOT set both `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30` AND `CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000`** — they compound to 30% × 400K = 120K trigger ≈ 12% of 1M, fires almost immediately (#207). See wizard "Autocompact Tuning" for details.

## Self-Review Loop

```
PLANNING → DOCS → TDD RED → GREEN → Tests Pass → Self-Review
    ^                                                  |
    +--- Ask user: fix in new plan? ←- Issues found? YES (NO → Present)
```

The loop goes back to PLANNING, not TDD RED. Run `/code-review`; issues at confidence ≥ 80 are real, < 80 are likely false positives. Found issues → ask "Want a plan to fix?" → new plan → docs → TDD → review.

## Cross-Model Review (If Configured)

**When to run:** high-stakes changes (auth, payments, data), releases/publishes, complex refactors. **When to skip:** trivial changes, time-sensitive hotfixes, risk < review cost. **Prerequisites:** Codex CLI (`npm i -g @openai/codex`) + OpenAI API key. **Reviewer at flagship tier (#233):** even when project pins `sonnet[1m]`, reviewer runs `gpt-5.5` / Opus 4.8 max — adversarial diversity is the point.

PROTOCOL is universal across domains; only `review_instructions` and `verification_checklist` change.

1. **Preflight** (`.reviews/preflight-{review_id}.md`) — what you already checked: `/code-review` passed, tests passing, manual verifications, known limits. Reduces reviewer findings to 0-1/round.
2. **Mission-first handoff** (`.reviews/handoff.json`) — required keys: `"review_id"`, `"status": "PENDING_REVIEW"`, `"round": 1`, `"mission"`/`"success"`/`"failure"` (without them you get "looks good"), `"files_changed"`, `"verification_checklist"` (verification checklist with file:line refs — NOT generic), `"review_instructions"`, `"preflight_path"`. Optional `"pr_number":` opts into PreCompact self-heal (#209: PR MERGED → implicit CERTIFIED).
3. **Run reviewer:** `codex exec -c 'model_reasoning_effort="xhigh"' -s danger-full-access -o .reviews/latest-review.md "<prompt>" < /dev/null`. Always `xhigh`. Bash tool requires `run_in_background: true` + `dangerouslyDisableSandbox: true`; append `< /dev/null` always. **Why:** `< /dev/null` prevents codex stdin-hang at S/0% CPU; `run_in_background: true` avoids the Bash 10-min (`600000` ms) `timeout` cap that force-kills foreground codex (multi-artifact bundles take 5–30 min). xhigh 1–30 min; wrapper's `STALL_SECONDS=1800` is the real control. Heartbeat: `scripts/codex-review-with-progress.sh`. Foreground burned 70 min on a 7-min review (#364).
4. **Dialogue loop:** per-finding response (`{"finding": "1", "action": "FIXED|DISPUTED|ACCEPTED", "summary": "..."}` in `.reviews/response.json`). Bump round, set status `PENDING_RECHECK`, add `fixes_applied` (numbered, file:line). Recheck prompt: "TARGETED RECHECK. FIXED → verify certify condition. DISPUTED → ACCEPT if sound, REJECT with reasoning. ACCEPTED → verify applied. No new findings unless P0."

**Convergence:** 2 rounds sweet spot, 3 max. After 3 NOT CERTIFIED → escalate.

**Enforcement:** `hooks/goal-confidence-check.sh` warns when `/goal` skips the 95%-confidence or DLC-binding gates (#360).

**Multi-reviewer:** respond to each reviewer independently (no shared anchoring). **Non-code domains:** add `"audience"`/`"stakes"` keys to handoff.

### Release Review Focus

Before any release/publish, add to `verification_checklist`: **CHANGELOG consistency** (sections present, no lost entries), **Version parity** (package.json + SDLC.md + CHANGELOG + wizard metadata), **Stale examples** (hardcoded version strings), **Docs accuracy** (README + ARCHITECTURE reflect current features), **CLI-distributed file parity** (live skills/hooks match CLI templates).

**Full protocol** (rationale, full JSON example, anti-patterns like "find at least N", convergence diagrams): `CLAUDE_CODE_SDLC_WIZARD.md` → "Cross-Model Review Loop".

## Documentation Sync (REQUIRED — During Planning)

**Docs MUST be current before commit.** Stale docs = wrong implementations = wasted sessions.

Standard pattern: `*_DOCS.md` — living documents that grow with the feature (`AUTH_DOCS.md`, `PAYMENTS_DOCS.md`).

1. Read feature docs for the area being changed during planning
2. When a code change contradicts what the doc says → MUST update the feature doc
3. When a code change extends behavior the doc describes → MUST update the feature doc (add new behavior)
4. No `*_DOCS.md` exists and feature touches 3+ files → create one
5. Project has `ROADMAP.md` → mark items done, add new items (ROADMAP feeds CHANGELOG)

`/claude-md-improver` audits CLAUDE.md structure. Run it periodically. It does NOT cover feature docs — the SDLC workflow handles those.

## CI Feedback Loop — Local Shepherd

**NEVER AUTO-MERGE. Do NOT run `gh pr merge --auto`.** Auto-merge fires before review feedback can be read. The shepherd loop IS the process.

Mandatory steps:
1. Push to remote
2. `gh pr checks --watch`
3. **Read CI logs whether pass or fail** (`gh run view <RUN_ID> --log`, not just `--log-failed`). Passing CI hides warnings, skipped steps, degraded scores
4. **Cross-model audit the CI logs** — pipe to a tmp file, run `codex exec -c 'model_reasoning_effort="xhigh"' -s danger-full-access "<audit prompt>" < /dev/null` (always append `< /dev/null` — stdin-hang fix) with *"Audit for silent failures, skipped tests, degraded metrics, warnings-that-should-be-errors."* Tier 1 + Tier 2 separately
5. CI fails → diagnose, fix, push (max 2 attempts)
6. CI passes → `gh api repos/OWNER/REPO/pulls/PR/comments` for review feedback
7. Implement valid suggestions (bugs, perf, missing error handling, dedup, coverage). Skip opinions/style. Max 3 iterations
8. Explicit `gh pr merge --squash`

**Evidence:** PR #145 auto-merged before review was read; reviewer found a P1 dead-code bug that shipped. v1.24.0 only checked the green checkmark on round 2; passing CI hides degraded E2E scores and silent test exclusions. Use idle CI time (3-5 min) for `/compact` if context is long.

## Scope, DRY, Patterns, Legacy

- **Scope guard** — only task-related changes. Notice something else → NOTE in summary, don't fix unless asked. AI drift into "helpful" changes breaks unrelated things.
- **DRY** — before coding: "what patterns exist to reuse?" After: "did I duplicate anything?"
- **New patterns** require human approval: search first, propose if no equivalent, get explicit approval.
- **DELETE legacy code** — backwards-compat shims, "just in case" fallbacks → gone. If it breaks, fix properly.

## Debugging Workflow (Systematic)

Reproduce → Isolate → Root Cause → Fix → Regression Test. This is the systematic debugging methodology — do not skip steps. Regressions: `git bisect`. Env-specific: check env vars/OS/deps/permissions, reproduce locally, log at the failure point. 2 failed attempts → STOP and ASK USER.

## Release Planning (Task Ships a Release)

List all items from ROADMAP, plan each at 95% confidence, identify dependencies, present all plans together (catches conflicts/scope creep), pre-release CI audit across merged PRs (warnings, degraded scores, skipped suites — green checkmark insufficient), user approves, then implement in priority order.

## Deployment Tasks

Read `ARCHITECTURE.md` Environments table + Deployment Checklist. **Production requires HIGH (90%+); ANY doubt → ASK USER.** **Post-deploy verification:** health check, log scan, smoke tests, monitor 15 min (prod only). Issues → rollback first, then new SDLC loop.

## Test Review (Harder Than Implementation)

Critique tests harder than app code: testing the right things? Tests prove correctness or just verify current behavior? Follow TESTING.md (Testing Diamond, minimal mocking, real-captured fixtures).

**Testing Diamond:** E2E ~5% (slow, proves real thing) → Integration ~90% (best bang for buck — real DB/cache/services via API, no UI) → Unit ~5% (pure logic only). If no UI/browser, it's integration, not E2E.

**Mocking:**

| What | Mock? | Why |
|------|-------|-----|
| Database | NEVER | Test DB or in-memory |
| Cache | NEVER | Isolated test instance |
| External APIs | YES | Real calls = flaky + expensive |
| Time/Date | YES | Determinism |

Mocks MUST come from real captured data — never guess shapes. Unit tests qualify ONLY for pure I→O (no DB, API, FS, cache).

**TDD proves:** RED (fails — bug or missing feature), GREEN (passes — fix works), Forever (regression protection).

## Prove It Gate (New Additions Only)

Adding a new skill/hook/workflow? Default answer is NO. Prove it: (1) **Absorption check** — can this be a section in an existing skill? (2) Research existing equivalents (native CC, third-party, existing skill). (3) If yes — why is yours better with evidence. (4) If no — real gap or theoretical? (5) **Quality tests** must prove OUTPUT QUALITY (existence tests prove nothing). (6) Less is more — every addition is maintenance burden.

If you can't write a quality test for it, you can't prove it works.

## After Session (Capture Learnings)

| Insight | Destination |
|---------|-------------|
| Testing patterns/gotchas | `TESTING.md` |
| Feature-specific quirks | `*_DOCS.md` (e.g., `AUTH_DOCS.md`) |
| Architecture decisions | `docs/decisions/` (ADR) or `ARCHITECTURE.md` |
| General project context | `CLAUDE.md` (or `/revise-claude-md`) |
| Plan files (work done) | Delete or mark complete (stale plans mislead) |

### Memory Audit Protocol

Per-user memory at `~/.claude/projects/<proj>/memory/` accumulates private learnings. Some are portable lessons (tool quirks, platform gotchas) worth promoting to wizard docs.

**When to run:** end-of-release, after debugging-heavy sessions, or on explicit "audit my memory" request.

**Rule-based denylist** (deterministic, no LLM):
- `type: user` → keep (user identity, preferences — never promote)
- `type: reference` → keep (external pointers, private by default)
- `type: project` → manual review (mixed state + portable lesson)
- `type: feedback` → manual review (mixed personal preference + portable rule)

**Destinations for promote entries** (no new files): tool/platform gotchas → `SDLC.md` `## Lessons Learned`. Testing → `TESTING.md`. Tool quirks tied to a skill → that `SKILL.md`. Process rules → `CLAUDE.md`.

**Tracking:** `promoted_to: <path>` in the memory file's YAML frontmatter; later audits skip already-promoted entries.

**Human gate is MANDATORY.** Protocol produces diffs; user approves chunk-by-chunk. Never auto-apply. Prove-It: build a `/memory-audit` slash command only after running 4+ times manually. (Full protocol: wizard doc.)

## Post-Mortem: Process Failures Become Rules

```
Incident → Root Cause → New Rule → Test That Proves the Rule → Ship
```

Don't fix only the symptom. Add a gate so it can't happen again. Example: PR #145 auto-merged before CI review → "NEVER AUTO-MERGE" block + `test_never_auto_merge_gate`.

## Context Management & Subagents

- `/compact` between planning and implementation (plan preserved in summary)
- `/clear` between unrelated tasks; after 2+ failed corrections (context polluted)
- Auto-compact fires at ~95% capacity
- After committing a PR, `/clear` before next feature
- `--bare` mode (v2.1.81+) skips ALL hooks/skills/LSP/plugins. Scripted headless only — never normal development.
- Custom subagents (`.claude/agents/`) run autonomously and return results. Skills guide behavior; agents do work. Use for parallel tasks or fresh context. Examples: `sdlc-reviewer`, `ci-debug`, `test-writer`.

## Design System Check (UI Changes Only)

Read `DESIGN_SYSTEM.md` if exists. Verify colors/fonts/spacing match tokens; flag new patterns not in design system. Skip on backend/config/non-visual code.

---
**Full reference:** `CLAUDE_CODE_SDLC_WIZARD.md` (cross-model review, deployment, debugging, post-mortem, memory audit, design system). `TESTING.md` (testing diamond + mocking). `ARCHITECTURE.md` (environments + post-deploy).
