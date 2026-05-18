---
name: sdlc
description: Full SDLC workflow for implementing features, fixing bugs, refactoring code, testing, releasing, publishing, and deploying. Use this skill when implementing, fixing, refactoring, testing, adding features, building new code, or releasing/publishing/deploying.
argument-hint: [task description]
effort: high
---
# SDLC Skill - Full Development Workflow

## Skill source & precedence

This skill is loaded from **`.claude/skills/sdlc/SKILL.md` in the active repo**. Claude Code prefers repo-local skills over global (`~/.claude/skills/sdlc/SKILL.md`) when both exist with the same name — the repo-local copy is the project's authoritative workflow contract. Use global skills only for cross-repo personal tooling (e.g. `feedback`, `revise-claude-md`); use repo-local for implementation, tests, release, and verification in this repo.

If unsure which copy is active, compare `head -5 .claude/skills/sdlc/SKILL.md` against `head -5 ~/.claude/skills/sdlc/SKILL.md`. The repo-local copy wins. Don't mix guidance from both — pick the source for this repo and stay there.

## Task
$ARGUMENTS

## Full SDLC Checklist

Your FIRST action must be TodoWrite with these steps:

```
TodoWrite([
  // PLANNING PHASE (Plan Mode for non-trivial tasks)
  { content: "Find and read relevant documentation", status: "in_progress", activeForm: "Reading docs" },
  { content: "Assess doc health - flag issues (ask before cleaning)", status: "pending", activeForm: "Checking doc health" },
  { content: "DRY scan: What patterns exist to reuse? New pattern = get approval", status: "pending", activeForm: "Scanning for reusable patterns" },
  { content: "Prove It Gate: adding new component? Research alternatives, prove quality with tests", status: "pending", activeForm: "Checking prove-it gate" },
  { content: "Blast radius: What depends on code I'm changing?", status: "pending", activeForm: "Checking dependencies" },
  { content: "Design system check (if UI change)", status: "pending", activeForm: "Checking design system" },
  { content: "Restate task in own words - verify understanding", status: "pending", activeForm: "Verifying understanding" },
  { content: "Scrutinize test design - right things tested? Follow TESTING.md?", status: "pending", activeForm: "Reviewing test approach" },
  { content: "Present approach + STATE CONFIDENCE LEVEL", status: "pending", activeForm: "Presenting approach" },
  { content: "Signal ready - user exits plan mode", status: "pending", activeForm: "Awaiting plan approval" },
  // TRANSITION PHASE (After plan mode)
  { content: "Doc sync: update or create feature docs — MUST be current before commit", status: "pending", activeForm: "Syncing feature docs" },
  // IMPLEMENTATION PHASE
  { content: "TDD RED: Write failing test FIRST", status: "pending", activeForm: "Writing failing test" },
  { content: "TDD GREEN: Implement, verify test passes", status: "pending", activeForm: "Implementing feature" },
  { content: "Run lint/typecheck", status: "pending", activeForm: "Running lint and typecheck" },
  { content: "Run ALL tests", status: "pending", activeForm: "Running all tests" },
  { content: "Production build check", status: "pending", activeForm: "Verifying production build" },
  // REVIEW PHASE
  { content: "DRY check: Is logic duplicated elsewhere?", status: "pending", activeForm: "Checking for duplication" },
  { content: "Visual consistency check (if UI change)", status: "pending", activeForm: "Checking visual consistency" },
  { content: "Self-review: run /code-review", status: "pending", activeForm: "Running code review" },
  { content: "Security review (if warranted)", status: "pending", activeForm: "Checking security implications" },
  { content: "Cross-model review (if configured — see below)", status: "pending", activeForm: "Running cross-model review" },
  { content: "Scope guard: only changes related to task? No legacy/fallback code left?", status: "pending", activeForm: "Checking scope and legacy code" },
  // CI FEEDBACK LOOP (if CI monitoring enabled in setup - skip if no CI)
  // NOTE (meta-repo only, ROADMAP #212 Option 1, 2026-04-24): this repo no
  // longer runs e2e simulation in CI. Only `validate` blocks merge. For E2E
  // signal on a PR, checkout the PR locally and run:
  //   bash tests/e2e/local-shepherd.sh <PR>
  // which scores on Max subscription and posts an advisory check-run.
  // Consumer repos still use their own CI as configured.
  { content: "Commit and push to remote", status: "pending", activeForm: "Pushing to remote" },
  { content: "Watch CI - fix failures, iterate until green (max 2x)", status: "pending", activeForm: "Watching CI" },
  { content: "Read CI review - implement valid suggestions, iterate until clean", status: "pending", activeForm: "Addressing CI review feedback" },
  { content: "Meta-repo only: run local shepherd if PR needs E2E score (optional)", status: "pending", activeForm: "Running local shepherd" },
  { content: "Post-deploy verification (if deploy task — see Deployment Tasks)", status: "pending", activeForm: "Verifying deployment" },
  // FINAL
  { content: "Present summary: changes, tests, CI status", status: "pending", activeForm: "Presenting final summary" },
  { content: "Capture learnings (if any — update TESTING.md, CLAUDE.md, or feature docs)", status: "pending", activeForm: "Capturing session learnings" },
  { content: "Close out plan files: if task came from a plan, mark complete or delete", status: "pending", activeForm: "Closing plan artifacts" }
])
```

## SDLC Quality Checklist (Scoring Rubric)

Your work is scored on these criteria. **Critical** criteria are must-pass.

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

**Total: 10 points** (11 for UI tasks, +1 for design_system check)

Critical miss on `tdd_red` or `self_review` = process failure regardless of total score.

## Test Failure Recovery (SDET Philosophy)

```
┌─────────────────────────────────────────────────────────────────────┐
│  ALL TESTS MUST PASS. NO EXCEPTIONS.                                │
│                                                                     │
│  This is not negotiable. This is not flexible. This is absolute.   │
└─────────────────────────────────────────────────────────────────────┘
```

**Not acceptable:**
- "Those were already failing" → Fix them first
- "Not related to my changes" → Doesn't matter, fix it
- "It's flaky" → Flaky = bug, investigate

**Treat test code like app code.** Test failures are bugs. Investigate them the way a 15-year SDET would - with thought and care, not by brushing them aside.

If tests fail:
1. Identify which test(s) failed
2. Diagnose WHY - this is the important part:
   - Your code broke it? Fix your code (regression)
   - Test is for deleted code? Delete the test
   - Test has wrong assertions? Fix the test
   - Test is "flaky"? Investigate - flakiness is just another word for bug
3. Fix appropriately (fix code, fix test, or delete dead test)
4. Run specific test individually first
5. Then run ALL tests
6. Still failing? ASK USER - don't spin your wheels

**Flaky tests are bugs, not mysteries:**
- Sometimes the bug is in app code (race condition, timing issue)
- Sometimes the bug is in test code (shared state, not parallel-safe)
- Sometimes the bug is in test environment (cleanup not proper)

Debug it. Find root cause. Fix it properly. Tests ARE code.

## New Pattern & Test Design Scrutiny (PLANNING)

**New design patterns require human approval:**
1. Search first - do similar patterns exist in codebase?
2. If YES and they're good - use as building block
3. If YES but they're bad - propose improvement, get approval
4. If NO (new pattern) - explain why needed, get explicit approval

**Test design scrutiny during planning:**
- Are we testing the right things?
- Does test approach follow TESTING.md philosophies?
- If introducing new test patterns, same scrutiny as code patterns

## Prove It Gate (REQUIRED for New Additions)

**Adding a new skill, hook, workflow, or component? PROVE IT FIRST:**

1. **Absorption check:** Can this be added as a section in an existing skill instead of a new component? Default is YES — new skills/hooks need strong justification. Releasing is SDLC, not a separate skill. Debugging is SDLC, not a separate skill. Keep it lean
2. **Research:** Does something equivalent already exist (native CC, third-party plugin, existing skill)?
3. **If YES:** Why is yours better? Show evidence (A/B test, quality comparison, gap analysis)
4. **If NO:** What gap does this fill? Is the gap real or theoretical?
5. **Quality tests:** New additions MUST have tests that prove OUTPUT QUALITY, not just existence
6. **Less is more:** Every addition is maintenance burden. Default answer is NO unless proven YES

**Existence tests are NOT quality tests:**
- BAD: "ci-analyzer skill file exists" — proves nothing about quality
- GOOD: "ci-analyzer recommends lint-first when test-before-lint detected" — proves behavior

**If you can't write a quality test for it, you can't prove it works, so don't add it.**

## Plan Mode Integration

**Use plan mode for:** Multi-file changes, new features, LOW confidence, bugs needing investigation.

**Workflow:**
1. **Plan Mode** (editing blocked): Research -> Write plan file -> Present approach + confidence
2. **Transition** (after approval): Update feature docs
3. **Implementation**: TDD RED -> GREEN -> PASS

### Auto-Approval: Skip Plan Approval Step

If ALL of these are true, skip plan approval and go straight to TDD:
- Confidence is **HIGH (95%+)** — you know exactly what to do
- Task is **single-file or trivial** (config tweak, small bug fix, string change)
- No new patterns introduced
- No architectural decisions

When auto-approving, still announce your approach — just don't wait for approval:
> "Confidence HIGH (95%). Single-file change. Proceeding directly to TDD."

**When in doubt, wait for approval.** Auto-approval is for clear-cut cases only.

## Recommended Model

**Default: `opus[1m]` (Opus 4.7 with 1M context window).** Run `/model opus[1m]` at the start of any non-trivial SDLC session.

**Why:**
- SDLC sessions (plan → TDD → review → CI shepherd) accumulate context fast — plans, test output, diffs, review artifacts. 200K fills up before you're done.
- Forced auto-compact mid-task loses your working state. Extra headroom is cheaper than re-reading files.
- At time of writing, Anthropic lists 1M context at standard pricing for supported Opus/Sonnet models — verify current rates for your plan before relying on this.

**Requires Claude Code v2.1.111+** for Opus 4.7.

**Pair with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30`.** Without it, CC's default auto-compact on 1M fires at ~76K and defeats the purpose. The wizard's `cli/templates/settings.json` sets both defaults on install.

**Fall back to `opus` (200K) only when:** your plan charges a premium for long-context prompts, the task is genuinely short (<30K), or team cost controls flag >200K prompts. See the "1M vs 200K Context Window" section in `CLAUDE_CODE_SDLC_WIZARD.md` for details.

## Confidence Check (REQUIRED)

Before presenting approach, STATE your confidence:

| Level | Meaning | Action | Effort |
|-------|---------|--------|--------|
| HIGH (90%+) | Know exactly what to do | Present approach, proceed after approval | `high` (default) |
| MEDIUM (60-89%) | Solid approach, some uncertainty | Present approach, highlight uncertainties | `high` (default) |
| LOW (<60%) | Not sure | Do more research or try cross-model research (Codex) to get to 95%. If still LOW after research, ASK USER | **Run `/effort xhigh` now** — don't wait |
| FAILED 2x | Something's wrong | Try cross-model research (Codex) for a fresh perspective. If still stuck, STOP and ASK USER | **Run `/effort max` now** — you're already burning cycles at lower effort |
| CONFUSED | Can't diagnose why something is failing | Try cross-model research (Codex). If still confused, STOP. Describe what you tried, ask for help | **Run `/effort max` now** — stop spinning |

**Dynamic bumping is NOT optional.** "Consider max effort" is the same as "ignore this" in practice. If your confidence drops or tests fail twice, bump effort BEFORE the next attempt — not after a third failure. Spinning at low effort is an SDLC failure mode, not a style choice.

## Self-Review Loop (CRITICAL)

```
PLANNING -> DOCS -> TDD RED -> TDD GREEN -> Tests Pass -> Self-Review
    ^                                                      |
    |                                                      v
    |                                            Issues found?
    |                                            |-- NO -> Present to user
    |                                            +-- YES v
    +------------------------------------------- Ask user: fix in new plan?
```

**The loop goes back to PLANNING, not TDD RED.** When self-review finds issues:
1. Ask user: "Found issues. Want to create a plan to fix?"
2. If yes -> back to PLANNING phase with new plan doc
3. Then -> docs update -> TDD -> review (proper SDLC loop)

**How to self-review:**
1. Run `/code-review` to review your changes
2. It launches parallel agents (CLAUDE.md compliance, bug detection, logic & security)
3. Issues at confidence >= 80 are real findings — go back to PLANNING to fix
4. Issues below 80 are likely false positives — skip unless obviously valid
5. Address issues by going back through the proper SDLC loop

## Cross-Model Review (If Configured)

**When to run:** High-stakes changes (auth, payments, data handling), releases/publishes (version bumps, CHANGELOG, npm publish), complex refactors, research-heavy work.
**When to skip:** Trivial changes (typo fixes, config tweaks), time-sensitive hotfixes, risk < review cost.

**Prerequisites:** Codex CLI installed (`npm i -g @openai/codex`), OpenAI API key set.

**The core insight:** The review PROTOCOL is universal across domains. Only the review INSTRUCTIONS change. Code review is the default template below. For non-code domains (research, persuasion, medical content), adapt the `review_instructions` and `verification_checklist` fields while keeping the same handoff/dialogue/convergence loop.

**Reviewer always at the flagship tier (roadmap #233):** if the project pins `model: "sonnet[1m]"` (mixed-mode) or any non-flagship coder, the cross-model reviewer **still runs at the flagship**: `codex exec -c 'model_reasoning_effort="xhigh"'` (gpt-5.5) or an Opus 4.7 max equivalent. The whole point of mixed-mode is that adversarial review catches Sonnet's blind spots — weakening the reviewer leg defeats the savings. Don't downscale the review just because the coder is downscaled.

### Step 0: Write Preflight Self-Review Doc

Before submitting to an external reviewer, document what YOU already checked. This is proven to reduce reviewer findings to 0-1 per round (evidence: anticheat repo preflight discipline).

Write `.reviews/preflight-{review_id}.md`:
```markdown
## Preflight Self-Review: {feature}
- [ ] Self-review via /code-review passed
- [ ] All tests passing
- [ ] Checked for: [specific concerns for this change]
- [ ] Verified: [what you manually confirmed]
- [ ] Known limitations: [what you couldn't verify]
```

### Step 1: Write Mission-First Handoff

After self-review and preflight pass, write `.reviews/handoff.json`:
```jsonc
{
  "review_id": "feature-xyz-001",
  "status": "PENDING_REVIEW",
  "round": 1,
  "mission": "What changed and why — 2-3 sentences of context",
  "success": "What 'correctly reviewed' looks like — the reviewer's goal",
  "failure": "What gets missed if the reviewer is superficial",
  "files_changed": ["src/auth.ts", "tests/auth.test.ts"],
  "fixes_applied": [],
  "previous_score": null,
  "verification_checklist": [
    "(a) Verify input validation at auth.ts:45 handles empty strings",
    "(b) Verify test covers the null-token edge case",
    "(c) Check no hardcoded secrets in diff"
  ],
  "review_instructions": "Focus on security and edge cases. Be strict — assume bugs may be present until proven otherwise.",
  "preflight_path": ".reviews/preflight-feature-xyz-001.md",
  "artifact_path": ".reviews/feature-xyz-001/"
}
```

**Key fields explained:**
- `mission/success/failure` — Gives the reviewer context. Without this, you get generic "looks good" feedback. With it, reviewers read raw source files and verify specific claims (proven across 4 repos)
- `verification_checklist` — Specific things to verify with file:line references. NOT "review for correctness" — that's too vague. Each item is independently verifiable
- `preflight_path` — Shows the reviewer what you already checked, so they focus on what you might have missed

### Step 2: Run the Independent Reviewer

```bash
codex exec \
  -c 'model_reasoning_effort="xhigh"' \
  -s danger-full-access \
  -o .reviews/latest-review.md \
  "You are an independent code reviewer performing a certification audit. \
   Read .reviews/handoff.json for full context — mission, success/failure \
   conditions, and verification checklist. \
   Verify each checklist item with evidence (file:line, grep results, test output). \
   Output each finding with: ID (1, 2, ...), severity (P0/P1/P2), evidence, \
   and a 'certify condition' (what specific change resolves it). \
   Re-verify any prior-round passes still hold. \
   End with: score (1-10), CERTIFIED or NOT CERTIFIED." \
  < /dev/null
```

**Always use `xhigh` reasoning effort.** Lower settings miss subtle errors (wrong-generation references, stale pricing, cross-file inconsistencies).

**Always append `< /dev/null`** when invoking `codex exec` from a hook, CI step, background process, or any non-interactive parent (including the Claude Code Bash tool). Without it, codex blocks on stdin reads even when the prompt is given as a positional argument — the process sits at S/0% CPU indefinitely with a 0-byte `-o` output file (the file is only written on completion, so a hang gives zero visibility). Validated on codex-cli 0.130.0 / macOS 14, May 15, 2026, after two ~30+ min silent hangs. For live progress visibility add `--json` and redirect stdout to a file (`> .reviews/events.jsonl`); `tail -f` then shows the event stream.

**Sandbox note:** Codex's Rust binary requires access to macOS system configuration APIs (`SCDynamicStore`) during sandbox initialization. Claude Code's sandbox blocks this access, causing `codex exec` to crash with `system-configuration panicked: Attempted to create a NULL object`. When running `codex exec` from within Claude Code, you MUST use `dangerouslyDisableSandbox: true` on the Bash tool call. This is safe — Codex has its own sandbox (`-s danger-full-access` is already specified), and the CC sandbox bypass only affects the Codex process. This is a known Codex issue ([#15640](https://github.com/openai/codex/issues/15640)).

If CERTIFIED → proceed to CI. If NOT CERTIFIED → go to dialogue loop.

### Step 3: Dialogue Loop

Respond per-finding — don't silently fix everything:

1. Write `.reviews/response.json`:
   ```jsonc
   {
     "review_id": "feature-xyz-001",
     "round": 2,
     "responding_to": ".reviews/latest-review.md",
     "responses": [
       { "finding": "1", "action": "FIXED", "summary": "Added missing validation" },
       { "finding": "2", "action": "DISPUTED", "justification": "Intentional — see CODE_REVIEW_EXCEPTIONS.md" },
       { "finding": "3", "action": "ACCEPTED", "summary": "Will add test coverage" }
     ]
   }
   ```
   - **FIXED**: "I fixed this. Here's what changed." Reviewer verifies against certify condition.
   - **DISPUTED**: "This is intentional/incorrect. Here's why." Reviewer accepts or rejects with reasoning.
   - **ACCEPTED**: "You're right. Fixing now." (Same as FIXED, batched.)

2. Update `handoff.json`: increment `round`, set `"status": "PENDING_RECHECK"`, add `fixes_applied` list with numbered items and file:line references, update `previous_score`.

3. Run targeted recheck (NOT a full re-review):
   ```bash
   codex exec \
     -c 'model_reasoning_effort="xhigh"' \
     -s danger-full-access \
     -o .reviews/latest-review.md \
     "TARGETED RECHECK — not a full re-review. Read .reviews/handoff.json \
      for previous_review path and response.json for the author's responses. \
      For each finding: FIXED → verify against original certify condition. \
      DISPUTED → evaluate justification (ACCEPT if sound, REJECT with reasoning). \
      ACCEPTED → verify it was applied. \
      Do NOT raise new findings unless P0 (critical/security). \
      New observations go in 'Notes for next review' (non-blocking). \
      Re-verify all prior passes still hold. \
      End with: score (1-10), CERTIFIED or NOT CERTIFIED." \
     < /dev/null
   ```

### Convergence

**2 rounds is the sweet spot. 3 max.** Research across 14 repos and 7 papers confirms additional rounds beyond 3 produce <5% position shift.

Max 2 recheck rounds (3 total including initial review). If still NOT CERTIFIED after round 3, escalate to the user with a summary of open findings.

```
Preflight → handoff.json (round 1) → FULL REVIEW
                                          |
                               CERTIFIED? → YES → CI
                                          |
                                          NO (scored findings)
                                          |
                               response.json (FIXED/DISPUTED/ACCEPTED)
                                          |
                               handoff.json (round 2+) → TARGETED RECHECK
                                          |
                               CERTIFIED? → YES → CI
                                          |
                                          NO → one more round, then escalate
```

**Tool-agnostic:** The value is adversarial diversity (different model, different blind spots), not the specific tool. Any competing AI reviewer works.

### Anti-Patterns to Avoid

- **"Find at least N problems"** — Incentivizes false positives. Use adversarial framing ("assume bugs may be present") instead
- **"Review this"** — Too vague, gets generic feedback. Use mission + verification checklist
- **Numeric 1-10 scales without criteria** — Unreliable. Decompose into specific checklist items
- **Letting reviewer see author's reasoning** — Causes anchoring bias. Let them form independent opinion from code

### Release Review Focus

Before any release/publish, add these to `verification_checklist`:
- **CHANGELOG consistency** — all sections present, no lost entries during consolidation
- **Version parity** — package.json, SDLC.md, CHANGELOG, wizard metadata all match
- **Stale examples** — hardcoded version strings in docs match current release
- **Docs accuracy** — README, ARCHITECTURE.md reflect current feature set
- **CLI-distributed file parity** — live skills, hooks, settings match CLI templates

### Multiple Reviewers (N-Reviewer Pipeline)

When multiple reviewers comment on a PR (Claude PR review, Codex, human reviewers), address each reviewer independently:

1. **Read all reviews** — `gh api repos/OWNER/REPO/pulls/PR/comments` to get every reviewer's feedback
2. **Respond per-reviewer** — Each reviewer has different blind spots and priorities. Address each one's findings separately
3. **Resolve conflicts** — If reviewers disagree, pick the stronger argument, note why
4. **Iterate until all approve** — Don't merge until every active reviewer is satisfied
5. **Max 3 iterations per reviewer** — If a reviewer keeps finding new things, escalate to the user

### Adapting for Non-Code Domains

The handoff format and dialogue loop work for ANY domain. Only `review_instructions` and `verification_checklist` change:

| Domain | Instructions Focus | Checklist Example |
|--------|-------------------|-------------------|
| **Code (default)** | Security, logic bugs, test coverage | "Verify input validation at file:line" |
| **Research/Docs** | Factual accuracy, source verification, overclaims | "Verify $736-$804 appears in both docs, no stale $695-$723 remains" |
| **Persuasion** | Audience psychology, tone, trust | "If you were [audience], what's the moment you'd stop reading?" |

For non-code: add `"audience"` and `"stakes"` fields to handoff.json. For code, these are implied (audience = other developers, stakes = production impact).

### Custom Subagents (`.claude/agents/`)

Claude Code supports custom subagents in `.claude/agents/`:

- **`sdlc-reviewer`** — SDLC compliance review (planning, TDD, self-review checks)
- **`ci-debug`** — CI failure diagnosis (reads logs, identifies root cause, suggests fix)
- **`test-writer`** — Quality tests following TESTING.md philosophies

**Skills** guide Claude's behavior. **Agents** run autonomously and return results. Use agents for parallel work or fresh context windows.

## Test Review (Harder Than Implementation)

During self-review, critique tests HARDER than app code:
1. **Testing the right things?** - Not just that tests pass
2. **Tests prove correctness?** - Or just verify current behavior?
3. **Follow our philosophies (TESTING.md)?**
   - Testing Diamond (integration-heavy)?
   - Minimal mocking (see table below)?
   - Real fixtures from captured data?

**Tests are the foundation.** Bad tests = false confidence = production bugs.

### Testing Diamond — Know Your Layers

| Layer | What It Tests | % of Suite | Key Trait |
|-------|--------------|------------|-----------|
| **E2E** | Full user flow through UI/browser (Playwright, Cypress) | ~5% | Slow, brittle, but proves the real thing works |
| **Integration** | Real systems via API without UI — real DB, real cache, real services | ~90% | **Best bang for buck.** Fast, stable, high confidence |
| **Unit** | Pure logic only — no DB, no API, no filesystem | ~5% | Fast but limited scope |

**The critical boundary:** E2E tests go through the user's actual UI/browser. Integration tests hit real systems via API but without UI. If your test doesn't open a browser or render a UI, it's not E2E — it's integration. This distinction matters because mislabeling integration tests as E2E leads to overinvestment in slow browser tests when fast API-level tests would suffice.

### Minimal Mocking Philosophy

| What | Mock? | Why |
|------|-------|-----|
| Database | NEVER | Use test DB or in-memory |
| Cache | NEVER | Use isolated test instance |
| External APIs | YES | Real calls = flaky + expensive |
| Time/Date | YES | Determinism |

**Mocks MUST come from REAL captured data** — capture real API responses, save to fixtures directory, import in tests. Never guess mock shapes.

### Unit Tests = Pure Logic ONLY

A function qualifies for unit testing ONLY if:
- No database calls
- No external API calls
- No file system access
- No cache calls
- Input -> Output transformation only

Everything else needs integration tests.

### TDD Tests Must PROVE

| Phase | What It Proves |
|-------|----------------|
| RED | Test FAILS -> Bug exists or feature missing |
| GREEN | Test PASSES -> Fix works or feature implemented |
| Forever | Regression protection |

## Flaky Test Recovery

**Flaky tests are bugs. Period.** See: [How do you Address and Prevent Flaky Tests?](https://softwareautomation.notion.site/How-do-you-Address-and-Prevent-Flaky-Tests-23c539e19b3c46eeb655642b95237dc0)

When a test fails intermittently:
1. **Don't dismiss it** — "flaky" means "bug we haven't found yet"
2. **Identify the layer** — test code? app code? environment?
3. **Stress-test** — run the suspect test N times to reproduce reliably
4. **Fix root cause** — don't just retry-and-pray
5. **If CI infrastructure** — make cosmetic steps non-blocking, keep quality gates strict

## Scope Guard (Stay in Your Lane)

**Only make changes directly related to the task.**

If you notice something else that should be fixed:
- NOTE it in your summary ("I noticed X could be improved")
- DON'T fix it unless asked

**Why this matters:** AI agents can drift into "helpful" changes that weren't requested. This creates unexpected diffs, breaks unrelated things, and makes code review harder.

## Debugging Workflow (Systematic Investigation)

When something breaks and the cause isn't obvious, follow this systematic debugging workflow:

```
Reproduce → Isolate → Root Cause → Fix → Regression Test
```

1. **Reproduce** — Can you make it fail consistently? If intermittent, stress-test (run N times). If you can't reproduce it, you can't fix it
2. **Isolate** — Narrow the scope. Which file? Which function? Which input? Use binary search: comment out half the code, does it still fail?
3. **Root cause** — Don't fix symptoms. Ask "why?" until you hit the actual cause. "It crashes on line 42" is a symptom. "Null pointer because the API returns undefined when rate-limited" is a root cause
4. **Fix** — Fix the root cause, not the symptom. Write the fix
5. **Regression test** — Write a test that fails without your fix and passes with it (TDD GREEN)

**For regressions** (it worked before, now it doesn't):
- Use `git bisect` to find the exact commit that broke it
- `git bisect start`, `git bisect bad` (current), `git bisect good <known-good-commit>`
- Bisect narrows to the breaking commit in O(log n) steps

**Environment-specific bugs** (works locally, fails in CI/staging/prod):
- Check environment differences: env vars, OS version, dependency versions, file permissions
- Reproduce the environment locally if possible (Docker, env vars)
- Add logging at the failure point — don't guess, observe

**When to stop and ask:**
- After 2 failed fix attempts → STOP and ASK USER
- If the bug is in code you don't understand → read first, then fix
- If reproducing requires access you don't have → ASK USER

## CI Feedback Loop — Local Shepherd (After Commit)

**This is the "local shepherd" — the CI fix mechanism.** It runs in your active session with full context.

**The SDLC doesn't end at local tests.** CI must pass too.

```
Local tests pass -> Commit -> Push -> Watch CI
                                         |
                              CI passes? -+-> YES -> Present for review
                                         |
                                         +-> NO -> Fix -> Push -> Watch CI
                                                           |
                                                   (max 2 attempts)
                                                           |
                                                   Still failing?
                                                           |
                                                   STOP and ASK USER
```

```
┌─────────────────────────────────────────────────────────────────────┐
│  NEVER AUTO-MERGE. NO EXCEPTIONS.                                   │
│                                                                     │
│  Do NOT run `gh pr merge --auto`. Ever.                            │
│  Auto-merge fires before you can read review feedback.             │
│  The shepherd loop IS the process. Skipping it = shipping bugs.    │
└─────────────────────────────────────────────────────────────────────┘
```

**The full shepherd sequence — every step is mandatory:**
1. Push changes to remote
2. Watch CI: `gh pr checks --watch`
3. Read CI logs — **pass or fail**: `gh run view <RUN_ID> --log` (not just `--log-failed`). Passing CI can still hide warnings, skipped steps, or degraded scores. Don't just check the green checkmark
4. **Cross-model review the CI logs themselves** — pipe `gh run view <RUN_ID> --log` to a tmp file and run `codex exec -c 'model_reasoning_effort="xhigh"' -s danger-full-access` with a prompt like *"Audit this CI log for silent failures, skipped tests, degraded metrics, or warnings-that-should-be-errors. Green checkmark is necessary but not sufficient."* A second model catches things the first missed (e.g., a job that passed but degraded an E2E score by 30%, or a test that was silently excluded). Cheap — one extra `codex exec` per PR. **Run separately on Tier 1 quick-check AND Tier 2 5x evaluation logs** — they exercise different code paths, so a clean Tier 1 audit doesn't imply a clean Tier 2. Evidence from PR #206: Tier 1 audit found 3 P1s (Node 24 false-green, "11/10" score leak, E2E incomplete); Tier 2 audit TBD — value is measured by running both and comparing.
5. If CI fails → diagnose from logs, fix, push again (max 2 attempts)
6. If CI passes → read ALL review comments: `gh api repos/OWNER/REPO/pulls/PR/comments`
7. Fix valid suggestions, push, iterate until clean
8. Only then: explicit merge with `gh pr merge --squash`

**Why this is non-negotiable:** PR #145 auto-merged a release before review feedback was read. CI reviewer found a P1 dead-code bug that shipped to main. The fix required a follow-up commit. Auto-merge cost more time than the shepherd loop would have taken.

**Why read passing logs:** v1.24.0 release only read logs on failure (round 1), then just checked the green checkmark on round 2. Passing CI can hide warnings, skipped steps, degraded E2E scores, or silent test exclusions. A green checkmark is necessary but not sufficient.

**Context GC (compact during idle):** While waiting for CI (typically 3-5 min), suggest `/compact` if the conversation is long. Think of it like a time-based garbage collector — idle time + high memory pressure = good time to collect. Don't suggest on short conversations.

**CI failures follow same rules as test failures:**
- Your code broke it? Fix your code
- CI config issue? Fix the config
- Flaky? Investigate - flakiness is a bug
- Stuck? ASK USER

## CI Review Feedback Loop — Local Shepherd (After CI Passes)

**CI passing isn't the end.** If CI includes a code reviewer, read and address its suggestions.

```
CI passes -> Read review suggestions
                    |
        Valid improvements? -+-> YES -> Implement -> Run tests -> Push
                             |                                      |
                             |                          Review again (iterate)
                             |
                             +-> NO (just opinions/style) -> Skip, note why
                             |
                             +-> None -> Done, present to user
```

**How to evaluate suggestions:**
1. Read all CI review comments: `gh api repos/OWNER/REPO/pulls/PR/comments`
2. For each suggestion, ask: **"Is this a real improvement or just an opinion?"**
   - **Real improvement:** Fixes a bug, improves performance, adds missing error handling, reduces duplication, improves test coverage → Implement it
   - **Opinion/style:** Different but equivalent formatting, subjective naming preference, "you could also..." without clear benefit → Skip it
3. Implement the valid ones, run tests locally, push
4. CI re-reviews — repeat until no substantive suggestions remain
5. Max 3 iterations — if reviewer keeps finding new things, ASK USER

**The goal:** User is only brought in at the very end, when both CI and reviewer are satisfied. The code should be polished before human review.

**Customizable behavior** (set during wizard setup):
- **Auto-implement** (default): Implement valid suggestions autonomously, skip opinions
- **Ask first**: Present suggestions to user, let them decide which to implement
- **Skip review feedback**: Ignore CI review suggestions, only fix CI failures

## Context Management

- `/compact` between planning and implementation (plan preserved in summary)
- `/clear` between unrelated tasks (stale context wastes tokens and misleads)
- `/clear` after 2+ failed corrections (context polluted — start fresh with better prompt)
- Auto-compact fires at ~95% capacity — no manual management needed
- After committing a PR, `/clear` before starting the next feature
- **Autocompact tuning:** Set `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` to trigger compaction earlier (75% for 200K, 30% for 1M). On 1M models, the default fires at ~76K — set 30% or `CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000` to use the full context window. See wizard doc "Autocompact Tuning" for full details

**`--bare` mode (v2.1.81+):** `claude -p "prompt" --bare` skips ALL hooks, skills, LSP, and plugins. This is a complete wizard bypass — no SDLC enforcement, no TDD checks, no planning hooks. Use only for scripted headless calls (CI pipelines, automation) where you explicitly don't want wizard enforcement. Never use `--bare` for normal development work.

## DRY Principle

**Before coding:** "What patterns exist I can reuse?"
**After coding:** "Did I accidentally duplicate anything?"

## Design System Check (If UI Change)

**When to check:** CSS/styling changes, new UI components, color/font usage.
**When to skip:** Backend-only changes, config/build changes, non-visual code.

**Planning phase - "Design system check":**
1. Read DESIGN_SYSTEM.md if it exists
2. Check if change involves colors, fonts, spacing, or components
3. Verify intended styles match design system tokens
4. Flag if introducing new patterns not in design system

**Review phase - "Visual consistency check":**
1. Are colors from the design system palette?
2. Are fonts/sizes from typography scale?
3. Are spacing values from the spacing scale?
4. Do new components follow existing patterns?

**If no DESIGN_SYSTEM.md exists:** Skip these checks (project has no documented design system).

## Release Planning (If Task Involves a Release)

**When to check:** Task mentions "release", "publish", "version bump", "npm publish", or multiple items being shipped together.
**When to skip:** Single feature implementation, bug fix, or anything that isn't a release.

Before implementing any release items:

1. **List all items** — Read ROADMAP.md (or equivalent), identify every item planned for this release
2. **Plan each at 95% confidence** — For each item: what files change, what tests prove it works, what's the blast radius. If confidence < 95% on any item, flag it
3. **Identify blocks** — Which items depend on others? What must go first?
4. **Present all plans together** — User reviews the complete batch, not one at a time. This catches conflicts, sequencing issues, and scope creep before any code is written
5. **Pre-release CI audit** — Before cutting the release, review CI runs across ALL PRs merged since last release. Look for: warnings in passing runs, degraded E2E scores, skipped test suites, silent failures masked by `continue-on-error`. Use `gh run list` + `gh run view <ID> --log` to audit. A green checkmark is necessary but not sufficient
6. **User approves, then implement** — Full SDLC per item (TDD RED → GREEN → self-review), in the prioritized order

**Why batch planning works:** Ad-hoc one-at-a-time implementation leads to unvalidated additions and scope creep. Batch planning catches problems early — if you can't plan it at 95%, you're not ready to ship it.

**Why pre-release CI audit:** v1.24.0 shipped without auditing CI logs across merged PRs #150-#152. Passing CI doesn't mean nothing fishy got through — warnings, degraded scores, and skipped steps can hide in green runs.

## Deployment Tasks (If Task Involves Deploy)

**When to check:** Task mentions "deploy", "release", "push to prod", "staging", etc.
**When to skip:** Code changes only, no deployment involved.

**Before any deployment:**
1. Read ARCHITECTURE.md → Find the Environments table and Deployment Checklist
2. Verify which environment is the target (dev/staging/prod)
3. Follow the deployment checklist in ARCHITECTURE.md

**Confidence levels for deployment:**

| Target | Required Confidence | If Lower |
|--------|---------------------|----------|
| Dev/Preview | MEDIUM or higher | Proceed with caution |
| Staging | MEDIUM or higher | Proceed, note uncertainties |
| **Production** | **HIGH only** | **ASK USER before deploying** |

**Production deployment requires:**
- All tests passing
- Production build succeeding
- Changes tested in staging/preview first
- HIGH confidence (90%+)
- If ANY doubt → ASK USER first

**If ARCHITECTURE.md has no Environments section:** Ask user "How do you deploy to [target]?" before proceeding.

**After deploying — Post-Deploy Verification:**
1. Read ARCHITECTURE.md → Find the Post-Deploy Verification table
2. Run health check for the target environment
3. Check logs for new errors
4. Run smoke tests if configured
5. Monitor error rates for 15 min (production only)
6. If issues found → rollback first, then start new SDLC loop to fix

**If ARCHITECTURE.md has no Post-Deploy section:** Ask user "How do you verify [target] is working after deploy?"

## DELETE Legacy Code

- Legacy code? DELETE IT
- Backwards compatibility? NO - DELETE IT
- "Just in case" fallbacks? DELETE IT

**THE RULE:** Delete old code first. If it breaks, fix it properly.

## Documentation Sync (REQUIRED — During Planning)

Feature docs MUST be current before commit. Docs are code — stale docs mislead future sessions, waste tokens, and cause wrong implementations.

**Standard pattern:** `*_DOCS.md` — living documents that grow with the feature (e.g., `AUTH_DOCS.md`, `PAYMENTS_DOCS.md`, `SEARCH_DOCS.md`). Same philosophy as `TESTING.md` and `ARCHITECTURE.md` — one source of truth per topic, kept current.

```
┌─────────────────────────────────────────────────────────────────────┐
│  DOCS MUST BE CURRENT BEFORE COMMIT.                                │
│                                                                     │
│  Stale docs = wrong implementations = wasted sessions.             │
│  If you changed the feature, update its doc. No exceptions.        │
└─────────────────────────────────────────────────────────────────────┘
```

1. **During planning**, read feature docs for the area being changed (`*_DOCS.md`, `docs/features/`, `docs/decisions/`)
2. If your code change contradicts what the doc says → MUST update the doc
3. If your code change extends behavior the doc describes → MUST add to the doc
4. If no `*_DOCS.md` exists and the feature touches 3+ files → create one. Keep it simple: what the feature does, key decisions, gotchas. Same structure as TESTING.md (topic-focused, not exhaustive)
5. If the project has a `ROADMAP.md` → update it (mark items done, add new items). ROADMAP feeds CHANGELOG — keeping it current means releases write themselves

**Doc staleness signals:** Low confidence in an area often means the docs are stale, missing, or misleading. If you struggle during planning, check whether the docs match the actual code.

**CLAUDE.md health:** `/claude-md-improver` audits CLAUDE.md structure and completeness. Run it periodically. It does NOT cover feature docs — the SDLC workflow handles those.

## After Session (Capture Learnings)

If this session revealed insights, update the right place:
- **Testing patterns, gotchas** → `TESTING.md`
- **Feature-specific quirks** → Feature docs (`*_DOCS.md`, e.g., `AUTH_DOCS.md`)
- **Architecture decisions** → `docs/decisions/` (ADR format) or `ARCHITECTURE.md`
- **General project context** → `CLAUDE.md` (or `/revise-claude-md`)
- **Plan files** → If this session's work came from a plan file, delete it or mark it complete. Stale plans mislead future sessions into thinking work is still pending

### Memory Audit Protocol

Per-user memory at `~/.claude/projects/<proj>/memory/` accumulates private learnings. Some belong there (user preferences, external references). Others are portable technical lessons (tool quirks, platform gotchas, bash/GHA/macOS footguns) that would save the next contributor hours. Run this audit to promote the portable ones.

**When to run:**
- End-of-release (before cutting a tag)
- After a debugging-heavy session with multiple memory additions
- On explicit "audit my memory" request

**Classify each memory file in `~/.claude/projects/<proj>/memory/`:**

1. **Rule-based denylist (deterministic, no LLM):**
   - `type: user` → `keep` (user identity, preferences — never promote)
   - `type: reference` → `keep` (external pointers to Discord/URL/etc — private by default)
   - `type: project` → `manual-review` (often mixed state + portable lesson — human decides)
   - `type: feedback` → `manual-review` (often mixed personal preference + portable rule — human decides)
   - Parser must normalize YAML variants (`type: "user"`, `type: user # comment`, surrounding whitespace) — see `tests/test-memory-audit-protocol.sh::apply_denylist_rule` for the reference implementation
2. **Remaining entries** (no type, or type outside the 4 above) fall through to human-gated review. An LLM-assisted classification runner is Prove-It-Gated: build it only after running this protocol 4+ times with manual classification. Until then, human review at promotion time IS the quality gate

**Destinations for `promote` entries (no new files — use existing wizard destinations):**

| Content | Target |
|---------|--------|
| Language/tool/platform gotchas (bash, gh CLI, GHA, macOS) | `SDLC.md` → `## Lessons Learned` section |
| Testing gotchas (flaky patterns, mock-vs-integration lessons) | `TESTING.md` |
| Tool-specific quirks tied to a skill | That skill's `SKILL.md` |
| Process rules that should govern the project | `CLAUDE.md` |

**Tracking:** When you promote an entry, add `promoted_to: <path>` to that memory file's YAML frontmatter. Subsequent audits skip already-promoted entries.

**Human gate is MANDATORY.** Protocol produces diffs; user approves chunk-by-chunk before apply. Never auto-apply — private memory touching public docs needs human judgement.

**Prove It Gate:** If you find yourself running this protocol 4+ times and manually doing the same classification work, that's evidence to build a `/memory-audit` slash command AND wire the LLM-gated quality tests (8/10 classification, 6/6 destination). Until then, protocol + human review is enough — and no stub tests that skip (they mislead reviewers into thinking a gate exists when it doesn't).

## Post-Mortem: When Process Fails, Feed It Back

**Every process failure becomes an enforcement rule.** When you skip a step and it causes a problem, don't just fix the symptom — add a gate so it can't happen again.

```
Incident → Root Cause → New Rule → Test That Proves the Rule → Ship
```

**How to post-mortem a process failure:**
1. **What happened?** — Describe the incident (what went wrong, what was the impact)
2. **Root cause** — Not "I forgot" — what structurally allowed the skip? Was it guidance (easy to ignore) instead of a gate (impossible to skip)?
3. **New rule** — Turn the failure into an enforcement rule in the SDLC skill
4. **Test** — Write a test that proves the rule exists (TDD — the rule is code too)
5. **Evidence** — Reference the incident so future readers understand WHY the rule exists

**Example (real incident):** PR #145 auto-merged before CI review was read. Root cause: auto-merge was enabled by default, no enforcement gate existed. New rule: "NEVER AUTO-MERGE" block added to CI Shepherd section with the same weight as "ALL TESTS MUST PASS." Test: `test_never_auto_merge_gate` verifies the block exists.

**Industry pattern:** "Every mistake becomes a rule" — the best SDLC systems are built from accumulated incident learnings, not theoretical best practices.

---

**Full reference:** SDLC.md
