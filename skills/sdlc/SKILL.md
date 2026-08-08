---
name: sdlc
description: Full SDLC workflow for implementing features, fixing bugs, refactoring code, testing, releasing, publishing, and deploying. Use this skill when implementing, fixing, refactoring, testing, adding features, building new code, or releasing/publishing/deploying.
argument-hint: "[task description]"
---
# SDLC Skill - Full Development Workflow

## Skill source & precedence

Loaded from repo-local **`.claude/skills/sdlc/SKILL.md`**, which wins over global `~/.claude/skills/` — the project's authoritative contract. Global is for cross-repo tooling only. Unsure which is active? `head -5` both.

## Task
$ARGUMENTS

Operational checklist — **complete on its own**. Full protocol (optional depth, Claude Code installs only): `CLAUDE_CODE_SDLC_WIZARD.md`; if absent, do not hunt for it.

**If the user requests /sdlc, ALWAYS run the full workflow — even for mechanical tasks.** Never silently skip; if overkill, say so and ask.

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
  { content: "TDD RED: failing test FIRST — watch EACH assertion fail, not the suite", status: "pending" },
  { content: "TDD GREEN: Implement, verify test passes", status: "pending" },
  { content: "Run lint/typecheck", status: "pending" },
  { content: "Run ALL tests", status: "pending" },
  { content: "Production build check", status: "pending" },
  // REVIEW
  { content: "DRY check: Is logic duplicated elsewhere?", status: "pending" },
  { content: "Visual consistency check (if UI change)", status: "pending" },
  { content: "Security review (if warranted)", status: "pending" },
  { content: "Cross-model review (high-stakes)", status: "pending" },
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
| self_review | 1 | | Read back files/diffs you modified |
| clean_code | 1 | | One coherent approach, no dead code |

**Total: 10 points** (11 for UI tasks, +1 for design_system check). Critical miss on `tdd_red` = process failure regardless of total score.

## Test Failure Recovery

**ALL TESTS MUST PASS. NO EXCEPTIONS.** Test code is app code. Failures are bugs — investigate them like a 15-year SDET, not by brushing aside.

Not acceptable: "those were already failing", "not related to my changes", "it's flaky" (flaky = bug we haven't found yet).

When tests fail:
1. Identify which test(s) failed
2. Diagnose WHY: your code broke it (regression — fix code), test is for deleted code (delete test), test has wrong assertions (fix test), "flaky" (investigate — race, shared state, env)
3. Fix appropriately, run specific test individually first, then run ALL tests
4. Still failing after 2 attempts? Escalate (see Confidence Check) — not straight to the user

## Confidence Check (REQUIRED)

State your confidence before presenting an approach:

| Level | Meaning | Action | Effort |
|-------|---------|--------|--------|
| HIGH (90%+) | Know exactly what to do | Present, proceed after approval | Model default |
| MEDIUM (60-89%) | Solid approach, some uncertainty | Present, highlight uncertainties | Model default |
| LOW (<60%) | Not sure | Escalate, don't ask ↓ | **escalate now** (per model, see above) |
| FAILED 2x | Something's wrong | Escalate, don't ask ↓ | **escalate now** |
| CONFUSED | Can't diagnose | Escalate, don't ask ↓ | **escalate now** |

**Effort bumping is NOT optional** — bump BEFORE the next attempt.

**Confidence ramp:** Opus research → Fable batch review → 95% list → /goal TDD → Codex.

**Uncertainty ≠ a human question.** Use the model/tool evidence available before interrupting a human — escalate to Fable (`advisor()`; if down, a Fable subagent at `high`), then Codex `high`; reserve the user for priority/risk/scope/spend or irreversible calls. **Confidence is not authorization**: a high score never overrides approval, external-effect, production, release/merge, or policy gates, and merge protections are non-overridable. **Standing instructions stay in force** (wizard doc).

## Plan Mode

Use plan mode for: multi-file changes, new features, LOW confidence, bug investigation. **Skip plan approval step** (auto-approval) when confidence HIGH (95%+) AND single-file/trivial AND no new patterns AND no architectural decisions — still announce approach, don't wait. When in doubt, wait.

## Long-Running Goals (`/goal`)

Native `/goal <condition>` (**v2.1.143+**). Haiku evaluator re-checks transcript per turn. **NEVER invoke below HIGH 95%** — below that it rubber-stamps flailing as progress. **Condition MUST name the DLC** (`/sdlc`, `/gdlc`, etc.) so the evaluator anchors on "doing it right." **Pre-flight:** trusted workspace; `disableAllHooks`/`allowManagedHooksOnly` off. **Condition = contract:** end state + check + constraints + hard turn/time bound; e.g. `/goal "tests pass + clean tree following /sdlc, stop after 20 turns"`. Evaluator can't call tools. `--resume` resets counters.

## Recommended Model

**Recommended: Opus 5 `high`** for complex projects, `medium` for routine web/CRUD. Escalate `xhigh` only for genuinely hard/long runs — not the default. Pin Opus 4.8 for a same-family escape. **Sonnet 5 `medium`** for simple work.

**Effort is model-aware, not blanket `max`** — `max` overthinks on Sonnet 5/Opus 4.8. Set via `/effort` per session, not a shell-rc env var (overrides post-switch — see SDLC.md). `/model` persists; picker `s` does not.

**Pinning `claude-opus-4-6`:** pair with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30` (1M) — do not set this for `opusplan` (200K, too aggressive). **Advisor (v2.1.170+):** `advisorModel: "fable"` works with all drivers above; set in `/claude-setup-wizard` Step 9.5.

## Cross-Model Review (REQUIRED for High-Stakes)

**When to run:** high-stakes changes (auth, payments, data), releases/publishes, complex refactors. **When to skip (log justification):** trivial, hotfixes, risk < review cost. **Prerequisites:** Codex CLI + OpenAI API key. **Reviewer:** `gpt-5.6-sol` `high` — adversarial diversity. **Cadence:** Fable during design, Codex once before commit — don't stack both per task unless the decision itself needs two independent reviewers.

PROTOCOL is universal across domains; only `review_instructions` and `verification_checklist` change.

**Handoff/preflight file mechanics live in the wizard doc.** These two steps stay here because improvising them has cost this repo real time: the codex flags below prevent a stdin hang and a 70-minute foreground kill (#364), and the `commit_sha` rule is what the merge gate checks for staleness (#437).

1. **Run reviewer:** `codex exec -c 'model_reasoning_effort="high"' -s danger-full-access -o .reviews/latest-review.md "<prompt>" < /dev/null`. Always `high`. Bash tool requires `run_in_background: true` + `dangerouslyDisableSandbox: true`; always append `< /dev/null`. **Why:** `< /dev/null` prevents codex stdin-hang at S/0% CPU; background avoids the Bash 10-min `timeout` cap that force-kills foreground codex (bundles take 5–30 min; no wrapper timeout). Foreground burned 70 min on a 7-min review (#364).
2. **Dialogue loop:** per-finding response (`{"finding":"1","action":"FIXED|DISPUTED|ACCEPTED","summary":"..."}` in `.reviews/response.json`). Bump round, set `PENDING_RECHECK`, add `fixes_applied` (numbered, file:line). Recheck prompt: "TARGETED RECHECK. FIXED → verify certify condition. DISPUTED → ACCEPT if sound, REJECT with reasoning. ACCEPTED → verify applied. Don't hunt new surfaces, but report every defect; any new P0/P1/P2 BLOCKS." **NEVER unilaterally dismiss** — always run the recheck; the reviewer may accept your dispute or counter with evidence you missed. **On CERTIFIED write `"commit_sha": "<git rev-parse HEAD>"` into `handoff.json`** — the gate hook (#437) treats a missing/mismatched SHA as stale, not just the status string.

**Convergence:** judge by max severity per round. Escalate, never ship.

**Multi-reviewer:** respond to each independently. **Non-code domains:** add `"audience"`/`"stakes"` keys.

**Full protocol** (rationale, full JSON example, anti-patterns like "find at least N", convergence diagrams): `CLAUDE_CODE_SDLC_WIZARD.md` → "Cross-Model Review Loop".

## Documentation Sync (REQUIRED — During Planning)

**Docs MUST be current before commit.** Stale docs = wrong implementations = wasted sessions.

Standard pattern: `*_DOCS.md` — living documents that grow with the feature (`AUTH_DOCS.md`, `PAYMENTS_DOCS.md`).

1. Read feature docs for the area being changed during planning
2. Code change contradicts or extends what the doc describes → MUST update the feature doc
3. No `*_DOCS.md` exists and feature touches 3+ files → create one
4. Project has `ROADMAP.md` → mark items done, add new items (ROADMAP feeds CHANGELOG)
5. **Change alters behaviour README describes → update README.** It ships and is the most-read doc; a deleted behaviour still advertised there is a lie to every consumer

`/claude-md-improver` audits CLAUDE.md structure periodically. Does NOT cover feature docs.

## CI Feedback Loop — Local Shepherd

**NEVER AUTO-MERGE. Do NOT run `gh pr merge --auto`.** Auto-merge fires before review feedback can be read. The shepherd loop IS the process.

Mandatory steps:
1. Push to remote
2. `gh pr checks --watch`
3. **Read CI logs even on pass** (`gh run view <RUN_ID> --log`) — green can hide warnings
4. **Cross-model audit the CI logs** — release/workflow/control-plane PRs only: silent failures, skipped tests, degraded metrics
5. CI fails → fix, push (max 2 attempts)
6. CI passes → `gh api .../pulls/PR/comments` for review feedback
7. Implement valid suggestions (bugs, perf, dedup). Skip opinions. Max 3 iterations
8. **Clearance, once CI green.** Ask reviewers *"safe to merge?"* — NOT "can you break this" (unsatisfiable; #478). Each posts `**CROSS-MODEL-CLEARANCE**` + one fenced json `{"reviewer","verdict":"YES","confidence","sha"}`. **`verdict` decides; confidence only qualifies it.** YES <95 names a residual → one focused round, never a human ask; re-asking unchanged is shopping.
9. Explicit `gh pr merge --squash` (repo wrapper if any) — never auto-merge. Needs 2 YES ≥95 on head SHA AND: CI `validate` green; Codex `high` CERTIFIED via full dialogue; **fresh Fable subagent** (diff only) with **zero unresolved findings** after **≥1 dialogue round**. Merge-evidence paths (workflows, `hooks/`, `.claude/`, merge script) + `package.json` version bumps need a human. Tell the user after — never silent.

**Evidence:** PR #145 auto-merged, shipped a P1 bug. v1.92.0: two YES (97/93) dead-ended (#478).

## Scope, DRY, Patterns, Legacy

- **Scope guard** — only task-related changes. Notice something else → NOTE in summary, don't fix unless asked. AI drift into "helpful" changes breaks unrelated things.
- **DRY** — before coding: "what patterns exist to reuse?" After: "did I duplicate anything?"
- **New patterns** require human approval: search first, propose if no equivalent, get explicit approval.
- **DELETE legacy code** — backwards-compat shims, "just in case" fallbacks → gone. If it breaks, fix properly.

## Debugging Workflow (Systematic)

Reproduce → Isolate → Root Cause → Fix → Regression Test. Do not skip steps. `git bisect` for regressions. 2 failed attempts → escalate (see Confidence Check), not straight to the user.

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

New skill/hook/workflow/PRACTICE? Default answer is NO. Prove it: (1) **Absorption check** — can this be a section in an existing skill? (2) Research existing equivalents (native CC, third-party, existing skill). (3) If yes — why is yours better with evidence. (4) If no — real gap or theoretical? (5) **Quality tests** must prove OUTPUT QUALITY (existence tests prove nothing). (6) Less is more — every addition is burden.

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

End of release: audit `~/.claude/projects/<proj>/memory/` and promote portable lessons into shared docs. **A process rule saved only to memory is a /sdlc gap** — memory changes one agent, docs change everyone. Type-based denylist, destinations and the MANDATORY human gate: `CLAUDE_CODE_SDLC_WIZARD.md`.

## Post-Mortem: Process Failures Become Rules

```
Incident → Root Cause → New Rule → Test That Proves the Rule → Ship
```

Don't fix only the symptom. Add a gate so it can't happen again. Example: PR #145 auto-merged before CI review → "NEVER AUTO-MERGE" block + `test_never_auto_merge_gate`.

## Context Management & Subagents

- `/compact` between planning and implementation (plan preserved in summary)
- `/clear` between unrelated tasks, after a PR, or after 2+ failed corrections
- **Work under ~350K tokens** (~35% of a 1M window). Compact well before autocompact (~95%). `/usage` = spend.
- **Run the test — a completion claim is not a test result.** Applies at any context size, not past a threshold
- `--bare` (v2.1.81+) skips ALL hooks/skills/LSP/plugins. Headless scripts only.
- Custom subagents (`.claude/agents/`) run autonomously. Skills guide; agents do. Use for parallel work or fresh context.

## Design System Check (UI Changes Only)

Read `DESIGN_SYSTEM.md` if exists. Verify colors/fonts/spacing match tokens; flag new patterns not in design system. Skip on backend/config/non-visual code.

---
**Full reference:** `CLAUDE_CODE_SDLC_WIZARD.md` (cross-model review, deployment, debugging, post-mortem, memory audit, design system). `TESTING.md` (testing diamond + mocking). `ARCHITECTURE.md` (environments + post-deploy).
