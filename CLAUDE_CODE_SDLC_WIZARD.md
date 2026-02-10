# Claude Code SDLC Setup Wizard

> **Contribute**: This wizard is community-driven. PRs welcome at [github.com/BaseInfinity/sdlc-wizard](https://github.com/BaseInfinity/sdlc-wizard) - your discoveries help everyone.

> **For Humans**: This wizard helps you implement a battle-tested SDLC enforcement system for Claude Code. It will scan your project, ask questions, and walk you through setup step-by-step. Works for solo developers, teams, and organizations alike.

> **Important**: This wizard is a **setup guide**, not a file you keep in your repo. Run it once to generate your SDLC files (hooks, skills, docs), then check for updates periodically with "Check if the SDLC wizard has updates".

## What This Is: SDLC for AI Agents

**This SDLC is designed for Claude (the AI) to follow, not humans.**

You set it up, Claude follows it. The magic is that structured human engineering practices (planning, TDD, confidence levels) happen to be exactly what AI agents need to stay on track.

| Human SDLC | Why It Works for AI |
|------------|---------------------|
| Plan before coding | AI must understand before acting, or it guesses wrong |
| TDD Red-Green-Pass | AI needs concrete pass/fail feedback to verify its work |
| Confidence levels | AI needs to know when to ask vs when to proceed |
| Self-review | AI catches its own mistakes before showing you |
| TodoWrite visibility | You see what AI is doing (no black box) |

**The result:** Claude follows a disciplined engineering process automatically. You just review and approve.

---

## KISS: Keep It Simple, Stupid

**A core principle of this SDLC - not just for coding, but for the entire development process.**

When implementing features, fixing bugs, or designing systems:
- **If something feels complex** - simplify another layer
- **If you're confused** - is this the right approach? Is there a better way?
- **If it's hard** - question WHY it's hard. Maybe it's hard for the wrong reasons.

**Don't power through complexity.** Step back and simplify. The simplest solution that works is usually the best one.

This applies to:
- Code you write
- Architecture decisions
- Test strategies
- The SDLC process itself

**When in doubt, simplify.**

---

## Testing AI Tool Updates

When your AI tools update, how do you know if the update is safe?

**The Problem:**
- AI behavior is stochastic - same prompt, different outputs
- Single test runs can mislead (variance looks like regression)
- "It feels slower" isn't data

**The Solution: Statistical A/B Testing**

| Phase | What You Test | Question |
|-------|---------------|----------|
| **Regression** | Old version vs new version | Did the update break anything? |
| **Improvement** | New version vs new version + changes | Do suggested changes help? |

**Statistical Rigor:**
- Run multiple trials (5+) to account for variance
- Use 95% confidence intervals
- Only claim regression/improvement when CIs don't overlap
- Overlapping CIs = no significant difference = safe

This prevents both false positives (crying wolf) and false negatives (missing real regressions).

**How We Apply This:**
- Daily workflow tests new Claude Code versions before recommending upgrade
- Phase A: Does new CC version break SDLC enforcement?
- Phase B: Do changelog-suggested improvements actually help?
- Results shown in PR with statistical confidence

---

## Philosophy: Sensible Defaults, Smart Customization

This wizard provides **opinionated defaults** optimized for AI agent workflows. You can customize, but understand what's load-bearing.

### CORE NON-NEGOTIABLES (Don't Change These)

These aren't preferences - they're **how AI agents stay on track**:

| Core Principle | Why It's Critical for AI |
|----------------|--------------------------|
| **TDD Red-Green-Pass** | AI agents need concrete pass/fail feedback. Without failing tests first, Claude can't verify its work. This is the feedback loop that keeps implementation correct. |
| **Testing Diamond** | Integration tests catch real bugs. Unit tests with mocks can "pass" while production fails. AI agents need tests that actually validate behavior. |
| **Confidence Levels** | Prevents Claude from guessing when uncertain. LOW confidence = ASK USER. This stops runaway bad implementations. |
| **TodoWrite Visibility** | You need to see what Claude is doing. Without visibility, Claude can go off-track without you knowing. |
| **Planning Before Coding** | Claude must understand before implementing. Skipping planning = wasted effort and wrong approaches. |

**WARNING:** Deviating from these fundamentals will break the system. The SDLC works because these pieces work together. Remove one and the whole system degrades.

---

### SAFELY CUSTOMIZABLE (Change Freely)

These adapt to your stack without affecting core behavior:

| Customization | Examples |
|---------------|----------|
| **Test framework** | Jest, Vitest, pytest, Go testing, etc. |
| **Commands** | Your specific lint, build, test commands |
| **Code style** | Tabs/spaces, quotes, semicolons |
| **Pre-commit checks** | Which checks to run (lint, typecheck, build) |
| **Documentation structure** | Your doc naming and organization |
| **Feature doc suffix** | Claude scans for existing patterns, suggests based on what you have, or lets you define custom |
| **Source directory patterns** | `/src/`, `/app/`, `/lib/`, etc. |
| **Test directory patterns** | `/tests/`, `/__tests__/`, `/spec/` |
| **Mocking rules** | What to mock in YOUR stack (external APIs, etc.) |
| **Code review agent** | Enable/disable self-review subagent |
| **Security review triggers** | What's security-sensitive in your domain |

---

### RISKY CUSTOMIZATIONS (Strong Warnings)

You CAN change these, but understand the trade-offs:

| Customization | Default | Risk if Changed |
|---------------|---------|-----------------|
| **Testing shape** | Diamond (integration-heavy) | Pyramid (unit-heavy) = mocks can hide real bugs, AI gets false confidence |
| **TDD strictness** | Strict (test first always) | Flexible = AI may skip tests, no verification of correctness |
| **Planning mode** | Required for implementation | Skipping = Claude codes without understanding, wasted effort |
| **Confidence thresholds** | LOW < 60% = must ask | Higher threshold = Claude proceeds when unsure, mistakes |

**If you change these:** The wizard will warn you. You can override, but you're accepting the risk.

---

### Smart Recommendations (Not Just Detection)

During setup, Claude will:

1. **Scan your project** - Find package managers (package.json, Cargo.toml, go.mod, pyproject.toml, etc.), test files, CI configs
2. **Recommend best practices** - Based on YOUR stack and what Claude discovers, not assumptions
3. **Explain the recommendation** - Why this approach works best with AI agents
4. **Let you decide** - Accept defaults or customize with full understanding
5. **Ask if unsure** - Claude will ask rather than guess about your stack

**Example:**
```
Scan result: Found Jest, mostly unit tests, heavy mocking
Recommendation: Testing Diamond with integration tests
Why: Your current unit tests with mocks may pass while production fails.
     Integration tests give Claude reliable feedback.
Action: [Accept Recommendation] or [Keep Current Approach (with warnings)]
```

---

### The Goal

**The True Goal:** Not just keeping AI Agents following SDLC, but creating a **self-improving partnership** where:
- Humans always feel **in control**
- Both sides **learn and get better** over time
- The process **organically evolves** through collaboration
- **Human + AI collaboration** working together - everyone wins

This frames the wizard as a partnership, not a constraint.

**What this means in practice:**
1. Have a process that Claude follows consistently
2. Make the process visible (TodoWrite, confidence levels)
3. Enforce quality gates (tests pass, review before commit)
4. Let Claude ask when uncertain
5. **Customize what makes sense, keep what keeps AI on track**

### Leverage Official Tools (Don't Reinvent)

When Anthropic provides official plugins or tools that handle something:
- **Use theirs, delete ours** - Official tools are maintained, tested, and updated automatically
- This wizard focuses on what official tools DON'T do (TDD enforcement, confidence levels, planning integration)

**Check periodically:** `/plugin > Discover` - new plugins may replace parts of our workflow.

---

## Prerequisites

| Requirement | Why |
|-------------|-----|
| **Claude Code v2.1.16+** | Required for Tasks system (persistent TodoWrite with dependency tracking) |
| **Git repository** | Files should be committed for team sharing |

---

## Claude Code Feature Updates

> **Keep your SDLC current**: Claude Code evolves. This section documents features that enhance the SDLC workflow. Check [Claude Code releases](https://github.com/anthropics/claude-code/releases) periodically.

### Tasks System (v2.1.16+)

**What changed**: TodoWrite is now backed by a persistent Tasks system with dependency tracking.

**Benefits for SDLC**:
- Tasks persist across sessions (crash recovery)
- Sub-agents can see task state
- Dependencies tracked automatically (RED → GREEN → PASS)

**No changes needed**: Your existing TodoWrite calls in skills work automatically with the new system.

**Rollback if issues**: Set `CLAUDE_CODE_ENABLE_TASKS=false` environment variable.

### Skill Arguments with $ARGUMENTS (v2.1.19+)

**What changed**: Skills can now accept parameters via `$ARGUMENTS` placeholder.

**How to use**: Add `argument-hint` to frontmatter and `$ARGUMENTS` in skill content:

```yaml
---
name: sdlc
description: Full SDLC workflow for implementing features, fixing bugs, refactoring code
argument-hint: [task description]
---

## Task
$ARGUMENTS

## Phases
...rest of skill...
```

**Usage examples**:
- `/sdlc fix the login validation bug` → `$ARGUMENTS` = "fix the login validation bug"
- `/testing unit UserService` → `$ARGUMENTS` = "unit UserService"

**Note**: Skills still auto-invoke via hooks. This is optional polish for manual invocation.

---

## What You're Setting Up

A workflow enforcement system that makes Claude Code:
- **Plan before coding** (Planning Mode → research → present approach)
- **Follow TDD** (write failing tests first, then implement)
- **Track progress** (TodoWrite for visibility)
- **Self-review** (catch issues before showing you)
- **Ask when unsure** (confidence levels prevent guessing)

**The Result**: Claude becomes a disciplined engineer who follows your process automatically.

---

## Philosophy First (Read This)

Before we configure anything, understand WHY this system works:

### 1. Planning Mode is Your Best Friend

**Start almost every task in Planning Mode.** Here's why:

**Hidden Benefit: Free Context Reset**
After planning, you get a free `/compact` - Claude's plan is preserved in the summary, and you start implementation with clean context. This is one of the biggest advantages of plan mode.

```
┌─────────────────────────────────────────────────────────────────┐
│ WITHOUT Planning Mode                                           │
│                                                                 │
│ User: "Add authentication"                                      │
│ Claude: *immediately starts writing code*                       │
│ Result: Maybe wrong approach, wasted effort, rework             │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ WITH Planning Mode                                              │
│                                                                 │
│ User: "Add authentication" + enters plan mode                   │
│ Claude: *researches codebase, understands patterns*             │
│ Claude: "Here's my approach. Confidence: MEDIUM. Questions..."  │
│ User: *approves or adjusts*                                     │
│ Claude: *now implements with clear direction*                   │
│ Result: Right approach, efficient implementation                │
└─────────────────────────────────────────────────────────────────┘
```

**Planning Mode + /compact = Maximum Efficiency**:
1. Claude researches in Planning Mode
2. Claude presents approach with confidence level
3. You approve → Claude updates docs
4. You run `/compact` → frees context, plan preserved in summary
5. Claude implements with clean context

### 2. Confidence Levels Prevent Disasters

Claude MUST state confidence before implementing:

| Level | Meaning | What Claude Does |
|-------|---------|------------------|
| **HIGH (90%+)** | "I know exactly what to do" | Proceeds after your approval |
| **MEDIUM (60-89%)** | "Solid approach, some unknowns" | Highlights uncertainties |
| **LOW (<60%)** | "I'm not sure" | **ASKS YOU before proceeding** |
| **FAILED 2x** | "Something's wrong" | **STOPS and asks for help** |
| **CONFUSED** | "I don't understand why this is failing" | **STOPS, describes what was tried** |

**Why this matters**: You have domain expertise. When Claude is uncertain, asking you takes 30 seconds. Guessing wrong takes 30 minutes to fix.

### 3. TDD (Recommended, Customize to Your Needs)

The classic TDD cycle:
```
RED   → Write test that FAILS (proves feature doesn't exist)
GREEN → Implement feature (test passes)
PASS  → All tests pass (no regressions)
```

**The core principle:** Have a testing strategy. Know what you're testing and why.

**Customize for your team:**
- Strict TDD (test first always)? Great.
- Test-after for some cases? Fine, just be consistent.
- The key: **don't commit code that breaks existing tests.**

**Test review preference:** Ask the user if they want to review each test before implementation, or trust the TESTING.md guidelines. Tests validate code - some users want oversight, others trust the process. If tests start failing or missing bugs, investigate why.

### 4. Testing Strategy (Define Yours)

Here's the "Testing Diamond" approach (recommended for AI agents):

```
        /\           ← Few E2E (automated like Playwright, or manual sign-off)
       /  \
      /    \
     /------\
    |        |       ← MANY Integration (real DB, real cache - BEST BANG FOR BUCK)
    |        |
     \------/
      \    /
       \  /
        \/           ← Few Unit (pure logic only)
```

**Why Integration Tests are Best Bang for Buck:**
- **Speed**: Fast enough to run on every change
- **Stability**: Touch real code, not mocks that lie
- **Confidence**: If integration tests pass, production usually works
- **AI-friendly**: Give Claude concrete pass/fail feedback on real behavior

**E2E vs Manual Testing:**
- **E2E (automated)**: Playwright, Cypress - runs without human
- **Manual testing**: Human sign-off at the very end
- **Goal**: Zero manual testing. Only for final verification when 100% confident.

**But your team decides:**

| Question | Your Choice |
|----------|-------------|
| Do you need E2E tests? | Maybe not for backend-only services |
| Heavy on unit tests? | Fine for pure logic codebases |
| Integration-first? | Great for systems with real DBs |
| No tests yet? | Start somewhere, even basic tests help |

**The point:** Have a testing strategy documented in TESTING.md. Claude will follow whatever approach you define.

### 5. Mocking Strategy (Philosophy, Not Just Tech)

**The Problem:** AI agents (and humans) tend to mock too much. Tests that mock everything test nothing - they just verify the mocks work, not the actual code.

**Minimal Mocking Philosophy:**

| Dependency | Mock It? | Reasoning |
|------------|----------|-----------|
| Database | ❌ NEVER | Use test DB or in-memory |
| Cache | ❌ NEVER | Use isolated test instance |
| External APIs | ✅ YES | Real calls = flaky + expensive |
| Time/Date | ✅ YES | Determinism |

**The key insight:** When you mock something, you're saying "I trust this works." Only mock things you truly can't control (external APIs, third-party services).

**But your team decides:**
- Heavy mocking preferred? Document it.
- No mocking at all? Document it.
- Mocks from fixtures? Document where fixtures live (e.g., `tests/fixtures/`).

**The point:** Have a mocking strategy documented. Claude will follow it. The goal is tests that prove real behavior, not just pass.

### 6. SDET Wisdom (Test Code is First-Class)

**Test Code = First-Class Citizen**
Treat test code like app code - code review, quality standards, not throwaway. Tests are production-critical infrastructure.

### Tests As Building Blocks

Existing test patterns are building blocks - leverage them:
- **Similar tests exist and are good?** - Copy the pattern, adapt for your case
- **Similar tests exist but are bad?** - Propose improvement, worth the scrutiny
- **No similar tests?** - More scrutiny needed, may need human input on approach

**Existing patterns aren't sacred.** Don't blindly copy bad patterns just because they exist. Improving a stale pattern is worth the effort.

**Before fixing a failing test, ask:**
1. Do we even need this test? (Is it for deleted/legacy code?)
2. Is this tested better elsewhere? (DRY applies to tests too)
3. Is the test wrong, or is the code wrong?

**Don't ignore flaky tests:**
- Flaky tests have revealed rare edge case bugs that later hit production
- "Nothing stings more than a flaky test you ignored coming back to bite you in prod"
- Dig into every failure - sweeping under the rug compounds problems

**Three categories of test failures:**

| Category | Examples | Fix |
|----------|----------|-----|
| **Test code bug** | Not parallel-safe, shared state, wrong assertions | Fix the test code (most common) |
| **Application bug** | Race condition, timing issue, edge case | Fix the app code - test found a real bug |
| **Environment/Infra bug** | CI config, memory, isolation issues | Fix the environment/setup/teardown |

### The Absolute Rule: ALL TESTS MUST PASS

```
┌─────────────────────────────────────────────────────────────────────┐
│  ALL TESTS MUST PASS. NO EXCEPTIONS.                                │
│                                                                     │
│  This is not negotiable. This is not flexible. This is absolute.   │
└─────────────────────────────────────────────────────────────────────┘
```

**Not acceptable excuses:**
- "Those tests were already failing" → Then fix them first
- "That's not related to my changes" → Doesn't matter, fix it
- "It's flaky, just ignore it" → Flaky = bug, investigate it
- "It passes locally" → CI is the source of truth
- "It's just a warning" → Warnings become errors, fix it

**The fix is always the same:**
1. Tests fail → STOP
2. Investigate → Find root cause
3. Fix → Whatever is actually broken (code, test, or environment)
4. All tests pass → THEN commit

**Why this is absolute:**
- Tests are your safety net
- A failing test means something is wrong
- Committing with failing tests = committing known bugs
- "Works on my machine" is not a standard

**MCP Awareness for Testing (optional, nuanced):**
- **Where MCP adds real value:** E2E/browser testing (can't "see" UI without it), graphics projects, external systems Claude can't otherwise access
- **Often overkill for:** API/Integration tests (reading code/docs is usually sufficient), internal code work
- **Reality check:** As Claude improves, fewer MCPs are needed. Claude Code has MCP Tool Search (dynamically loads tools >10% context)
- **The rule:** Suggest where it adds real value, don't force it. Let user decide.

---

### 7. Delete Legacy Code (No Fallbacks)

When refactoring:
- Delete old code FIRST
- If something breaks, fix it properly
- No backwards-compatibility hacks
- No "just in case" fallbacks

**Why this works with TDD:** Your tests are your safety net. If deleting breaks something, tests catch it. Fix properly, don't create hybrid systems. This simplifies your codebase and lets you "play golf" - less code to maintain.

### 8. Documentation Hygiene

Before starting any task, Claude should:

1. **Find relevant documentation** - Search for docs related to the feature/system
2. **Assess documentation health** - Is it current? Bloated? Useful?
3. **ASK before cleaning** - Never delete or refactor docs without user approval

**Signs a doc might need attention:**
- Very large file with mixed concerns
- Outdated information mixed with current
- Duplicate information across files
- Hard to find what you need

**But remember:**
- Complex systems have complex docs - that's OK
- Size alone doesn't mean bloat - some things ARE complex
- Context and usefulness matter more than line count
- When in doubt, ASK the user

**The rule:** Identify doc issues during planning, propose cleanup, get approval. Never nuke docs on your own.

### 9. Security Review (Calibrated to Your Project)

Security review depth should match your project's risk profile. During wizard setup, Claude will ask about your context to calibrate:

**Calibration Questions (during wizard):**
- Is this a personal project or production?
- Internal tool or public-facing?
- Handling sensitive data (PII, payments)?
- How many users?
- What's your attack surface?

**Then Claude calibrates:**

| Project Type | Security Review Depth |
|--------------|----------------------|
| Personal/learning project | Quick sanity check ("anything obvious?") |
| Internal tool, few users | Basic review of exposed endpoints |
| Production, sensitive data | Full review: auth, input validation, data exposure |
| Payment/financial | Extra scrutiny, consider external audit |

**Quick reference - which changes need review?**

| Change Type | Review? |
|-------------|---------|
| Auth/login changes | Yes |
| User input handling | Yes |
| API endpoints | Yes |
| Database queries | Yes |
| File operations | Yes |
| Internal refactoring | Usually no |
| UI/styling only | Usually no |

**What to check (when warranted):**
- Input validation at system boundaries
- Authentication/authorization on sensitive operations
- Data exposure risks
- Patterns appropriate for YOUR stack and attack surface

**The principle:** Always do a security review, but depth varies. A personal CLI tool doesn't need the same scrutiny as a payment API. Claude can always say "nothing to see here" for low-risk changes.

**Customize in wizard:** You can set your default review depth, and Claude will adjust based on what the code actually touches.

---

## Example Workflow (End-to-End)

Here's what a typical task looks like with this system:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ USER: "Add a password reset feature"                                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ HOOK FIRES: SDLC baseline reminder + AUTO-INVOKE instruction            │
│ CLAUDE: Sees implementation task → invokes sdlc skill                   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: PLANNING                                                       │
│                                                                         │
│ Claude:                                                                 │
│ 1. Creates TodoWrite with SDLC steps                                   │
│ 2. Searches for relevant docs (auth docs, API docs, etc.)              │
│ 3. Checks doc health - flags if anything needs attention               │
│ 4. Researches codebase (existing auth patterns, DB schema)             │
│ 5. Presents approach:                                                   │
│                                                                         │
│    "My approach:                                                        │
│    - Add /reset-password endpoint                                       │
│    - Use existing email service                                         │
│    - Store tokens in users table                                        │
│                                                                         │
│    Confidence: MEDIUM                                                   │
│    Uncertainty: Not sure about token expiry - 1 hour or 24 hours?"     │
│                                                                         │
│ User: "Use 1 hour. Looks good."                                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: TRANSITION                                                     │
│                                                                         │
│ Claude:                                                                 │
│ 1. Updates relevant docs with decisions/discoveries                    │
│ 2. "Docs updated. Ready for /compact before implementation?"           │
│                                                                         │
│ User: runs /compact                                                    │
│                                                                         │
│ (Context freed, plan preserved in summary)                             │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 3: IMPLEMENTATION (TDD)                                           │
│                                                                         │
│ Claude:                                                                 │
│ 1. TDD RED: Writes failing test for password reset                     │
│    - Test expects endpoint to exist, return success                    │
│    - Test FAILS (endpoint doesn't exist yet)                           │
│                                                                         │
│ 2. TDD GREEN: Implements password reset                                │
│    - Creates endpoint, email logic, token handling                     │
│    - Test PASSES                                                        │
│                                                                         │
│ 3. Runs lint/typecheck                                                 │
│ 4. Runs ALL tests - no regressions                                     │
│ 5. Production build check                                               │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 4: REVIEW                                                         │
│                                                                         │
│ Claude:                                                                 │
│ 1. DRY check - no duplicated logic                                     │
│ 2. Self-review with code-reviewer subagent                             │
│ 3. Security review (auth change = yes)                                 │
│    - ✅ Token properly hashed                                          │
│    - ✅ Rate limiting on endpoint                                       │
│    - ✅ No password in logs                                             │
│                                                                         │
│ 4. Presents summary:                                                    │
│    "Done. Added password reset with 1-hour tokens.                      │
│     3 files changed, tests passing, security reviewed.                  │
│     Ready for your review."                                             │
└─────────────────────────────────────────────────────────────────────────┘
```

This is what the system enforces automatically. Claude follows this workflow because:
- **Hooks** remind every prompt
- **Skills** provide detailed guidance when invoked
- **TodoWrite** makes progress visible
- **Confidence levels** prevent guessing
- **TDD** ensures correctness
- **Self-review** catches issues before you see them

---

## Recommended Documentation Structure

For Claude to be effective at SDLC enforcement, your project should have these docs:

| Document | Purpose | Claude Uses For |
|----------|---------|-----------------|
| **CLAUDE.md** | Claude-specific instructions | Commands, code style, project rules |
| **README.md** | Project overview | Understanding what the project does |
| **ARCHITECTURE.md** | System design, data flows, services | Understanding how components connect |
| **TESTING.md** | Testing philosophy, patterns, commands | TDD guidance, test organization |
| **SDLC.md** | Development workflow (this system) | Full SDLC reference |
| **ROADMAP.md** | Vision, goals, milestones, timeline | Understanding project direction |
| **CONTRIBUTING.md** | How to contribute, PR process | Guiding external contributors |
| **Feature docs** | Per-feature documentation | Context for specific changes |

**Why these matter:**
- **CLAUDE.md** - Claude reads this automatically every session. Put commands, style rules, architecture overview here.
- **ARCHITECTURE.md** - Claude needs to understand how your system fits together before making changes.
- **TESTING.md** - Claude needs to know your testing approach, what to mock, what not to mock.
- **ROADMAP.md** - Shows where the project is going. Helps Claude understand priorities and what's next.
- **CONTRIBUTING.md** - For open source projects, defines how contributions work. Claude follows these when suggesting changes.
- **Feature docs** - For complex features, Claude reads these during planning to understand context.

**Start simple, expand over time:**
1. Create CLAUDE.md with commands and basic architecture
2. Create TESTING.md with your testing approach
3. Add ARCHITECTURE.md when system grows complex
4. Add ROADMAP.md when you have clear milestones/vision
5. Add CONTRIBUTING.md if open source or team project
6. Add feature docs as major features emerge

---

## Step 0: Repository Protection & Plugin Setup

### Step 0.0: Enable Branch Protection (CRITICAL)

**Before setting up SDLC, protect your main branch.** This is non-negotiable for teams and highly recommended for solo developers.

**Why this matters:**
- SDLC enforcement is only as strong as your merge protection
- Without branch protection, anyone (including Claude) can push broken code to main
- Built-in GitHub feature - deterministic, no custom code needed

**Required Settings:**

| Setting | Value | Why |
|---------|-------|-----|
| Require pull request before merging | ✓ Enabled | All changes go through PR review |
| Require approvals | 1+ (your choice) | Human must approve before merge |
| Require status checks to pass | ✓ Enabled | CI must be green |
| Require branches to be up to date | ✓ Enabled | No stale merges |

**How to enable (UI):**
1. Go to: `Settings > Branches > Add rule`
2. Branch name pattern: `main` (or `master`)
3. Enable the settings above
4. Add required status checks: `validate`, `e2e-quick-check`
5. Save changes

**How to enable (CLI):**
```bash
gh api repos/OWNER/REPO/branches/main/protection --method PUT --input - << 'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["validate", "e2e-quick-check"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
EOF
```

**Optional but recommended:**

| Setting | Value | Why |
|---------|-------|-----|
| Include administrators | ✓ Enabled | No one bypasses the rules |
| Require CODEOWNERS review | ✓ Enabled | Specific people must approve |

**CODEOWNERS file (optional):**
Create `.github/CODEOWNERS`:
```
# Default owners for everything
* @your-username

# Or specific paths
/src/ @dev-team
/.github/ @platform-team
```

**The principle:** Built-in protection > custom enforcement. GitHub branch protection is battle-tested, always runs, and can't be accidentally bypassed.

**Why PRs even for solo devs?**

| Benefit | Solo Dev | Team |
|---------|----------|------|
| AI code review subagent | ✓ | ✓ |
| CI must pass before merge | ✓ | ✓ |
| Clean commit history | ✓ | ✓ |
| Easy rollback (revert PR) | ✓ | ✓ |
| Human review required | Optional | ✓ |

**Not required, but good practice.** The SDLC workflow includes a self-review step where Claude uses a code-reviewer subagent. When you use PRs, this review happens in context with the full diff visible. You always have final say - the subagent just catches things you might miss.

**Solo devs:** You can approve your own PRs. The value is the structured workflow (CI gates, code review, clean history), not the approval ceremony.

---

### Step 0.1: Required Plugins

**Install required plugin:**
```bash
/plugin install claude-md-management@claude-plugin-directory
```
> "Installing claude-md-management (required for CLAUDE.md maintenance)..."

This plugin handles:
- CLAUDE.md quality audits (A-F scores, specific improvement suggestions)
- Session learning capture via `/revise-claude-md`

**Scope:** CLAUDE.md only. Does NOT update feature docs, TESTING.md, ARCHITECTURE.md, hooks, or skills. The SDLC workflow still handles those (see Post-Mortem section for where learnings go).

### Step 0.2: SDLC Core Setup (Wizard Creates)

The wizard creates TDD-specific automations that official plugins don't provide:
- TDD pre-tool-check hook (test-first enforcement)
- SDLC prompt-check hook (baseline reminders)
- SDLC skill with confidence levels
- Planning mode integration

### Step 0.3: Additional Recommendations (Optional)

After SDLC setup is complete, run `claude-code-setup` for additional recommendations:

```
"Based on your codebase, recommend additional automations"
```

This may suggest:
- MCP Servers (context7 for docs, Playwright for frontend)
- Additional hooks (auto-format if Prettier configured)
- Subagents (security-reviewer if auth code detected)

**Claude prompts for each:**
> "[Detected: Prettier config] Want to add auto-format hook? (y/n)"

These are additive—they don't replace our TDD hooks.

### Git Workflow Preference

**Claude asks:**
> "Do you use pull requests for code review? (y/n)"

- **Yes → PRs**: Recommend `code-review` plugin, PR workflow guidance
- **No → Solo/Feature branches**: Skip PR plugins, recommend feature branch workflow

Feature branches still recommended for solo devs (keeps main clean, easy rollback).

**If using PRs, also ask:**
> "Auto-clean old bot comments on new pushes? (y/n)"

- **Yes** → Add `int128/hide-comment-action` to CI (collapses outdated bot comments)
- **No** → Skip (some teams prefer full comment history)

**Recommendation:** Solo devs = yes (keeps PR tidy). Teams = ask (some want audit trail).

> "Run AI code review only after tests pass? (y/n)"

- **Yes** → PR review workflow waits for CI to pass first (saves API costs on broken code)
- **No** → Review runs immediately in parallel with tests (faster feedback)

**Recommendation:** Yes for most teams. No point reviewing code that doesn't build/pass tests. Saves Claude API costs and reviewer time.

> "Use sticky PR comments or inline review comments for bot reviews? (sticky/inline)"

- **Sticky** → Bot reviews post as single PR comment that updates in place
- **Inline** → Bot creates GitHub review with inline comments on specific lines

**Recommendation:** Sticky for bots. Here's why:

| Approach | When to Use |
|----------|-------------|
| **Sticky PR comment** | Bots, automated reviews. Updates in place, stays clean. |
| **Inline review comments** | Humans. Threading on specific lines is valuable. |

**The problem with inline bot reviews:**
- Every push triggers new review → comments pile up
- GitHub's `hide-comment-action` only hides PR comments, not review comments
- PR becomes cluttered with dozens of outdated bot reviews

**Sticky comment workflow:**
1. Bot posts review as sticky PR comment (single comment, auto-updates)
2. User reads review, replies in PR comments if questions
3. User adds `needs-review` label to trigger re-review
4. Bot updates the SAME sticky comment (no pile-up)
5. Label auto-removed, ready for next round

**Back-and-forth:** User questions live in PR comments. Bot's response is always the latest sticky comment. Clean and organized.

**CI monitoring question:**
> "Should Claude monitor CI checks after pushing and auto-diagnose failures? (y/n)"

- **Yes** → Enable CI feedback loop in SDLC skill, add `gh` CLI to allowedTools
- **No** → Skip CI monitoring steps (Claude still runs local tests, just doesn't watch CI)

**What this does:**
1. After pushing, Claude runs `gh pr checks` to watch CI status
2. If checks fail, Claude reads logs via `gh run view --log-failed`
3. Claude diagnoses the failure and proposes a fix
4. Max 2 fix attempts, then asks user
5. Job isn't done until CI is green

**Recommendation:** Yes if you have CI configured. This closes the loop between
"local tests pass" and "PR is actually ready to merge."

**Requirements:**
- `gh` CLI installed and authenticated
- CI/CD configured (GitHub Actions, etc.)
- If no CI yet: skip, add later when you set up CI

**CI review feedback question (only if CI monitoring is enabled):**
> "How should Claude handle CI code review suggestions?"

| Option | Behavior |
|--------|----------|
| **Auto-implement valid ones** (recommended) | Claude reads review, implements suggestions that are real improvements (bug fixes, missing error handling, test coverage, DRY), skips style opinions. Iterates until reviewer is satisfied. |
| **Ask me first** | Claude reads review, presents suggestions to you, you decide which to implement. More control, more interruptions. |
| **Skip review feedback** | Claude only fixes CI failures (broken tests, lint errors), ignores review suggestions. Fastest, but you handle review feedback manually. |

**What this does:**
1. After CI passes, Claude reads the automated code review comments
2. Claude evaluates each suggestion: real improvement vs. style opinion
3. Based on your preference: implements, asks, or skips
4. Iterates (push -> re-review) until no substantive suggestions remain
5. Only brings you in when everything is clean (CI green + reviewer satisfied)
6. Max 3 iterations to prevent infinite loops

**Check for new plugins periodically:**
```
/plugin > Discover
```

### Step 0.4: Auto-Scan Your Project

**Before asking questions, Claude will automatically scan your project:**

Claude is language-agnostic and will discover your stack, not assume it:

```
Claude scans for:
├── Package managers (any language):
│   ├── package.json, package-lock.json, pnpm-lock.yaml  → Node.js
│   ├── Cargo.toml, Cargo.lock                           → Rust
│   ├── go.mod, go.sum                                   → Go
│   ├── pyproject.toml, requirements.txt, Pipfile        → Python
│   ├── Gemfile, Gemfile.lock                            → Ruby
│   ├── build.gradle, pom.xml                            → Java/Kotlin
│   └── ... (any package manifest)
│
├── Source directories: src/, app/, lib/, server/, pkg/, cmd/
├── Test directories: tests/, __tests__/, spec/, *_test.*, test_*.py
├── Test frameworks: detected from config files and test patterns
├── Lint/format tools: from config files
├── CI/CD: .github/workflows/, .gitlab-ci.yml, etc.
├── Feature docs: *_PLAN.md, *_DOCS.md, *_SPEC.md, docs/
├── README, CLAUDE.md, ARCHITECTURE.md
│
├── Deployment targets (for ARCHITECTURE.md environments):
│   ├── Dockerfile, docker-compose.yml    → Container deployment
│   ├── k8s/, kubernetes/, helm/          → Kubernetes
│   ├── vercel.json, .vercel/             → Vercel
│   ├── netlify.toml                      → Netlify
│   ├── fly.toml                          → Fly.io
│   ├── railway.json, railway.toml        → Railway
│   ├── render.yaml                       → Render
│   ├── Procfile                          → Heroku
│   ├── app.yaml, appengine/              → Google App Engine
│   ├── deploy.sh, deploy/                → Custom scripts
│   ├── .github/workflows/deploy*.yml     → GitHub Actions deploy
│   └── package.json scripts (deploy:*)   → npm deploy scripts
│
├── Tool permissions (for allowedTools):
│   ├── package.json           → Bash(npm *), Bash(node *), Bash(npx *)
│   ├── pnpm-lock.yaml         → Bash(pnpm *)
│   ├── yarn.lock              → Bash(yarn *)
│   ├── go.mod                 → Bash(go *)
│   ├── Cargo.toml             → Bash(cargo *)
│   ├── pyproject.toml         → Bash(python *), Bash(pip *), Bash(pytest *)
│   ├── Gemfile                → Bash(ruby *), Bash(bundle *)
│   ├── Makefile               → Bash(make *)
│   ├── docker-compose.yml     → Bash(docker *)
│   └── .github/workflows/     → Bash(gh *)
│
└── Design system (for UI projects):
    ├── tailwind.config.*      → Extract colors, fonts, spacing from theme
    ├── CSS with --var-name    → Extract custom property palette
    ├── .storybook/            → Reference as design source of truth
    ├── MUI/Chakra theme files → Reference theming docs + overrides
    └── /assets/, /images/     → Document asset locations
```

**If Claude can't detect something, it asks.** Never assumes.

**Examples are just examples.** The patterns above show common conventions - Claude will discover YOUR actual patterns.

**Shared vs isolated environments:** Not everyone runs in isolated local dev. Some teams share databases, staging servers, or have infrastructure already running. Claude should ask about your setup - don't assume isolated environments.

**Claude then presents findings:**
```
📊 Project Scan Results:

Detected:
- Language: TypeScript (tsconfig.json found)
- Source: src/
- Tests: tests/ (Jest, 47 test files)
- Lint: ESLint (.eslintrc.js)
- Build: npm run build

Feature Docs:
- Found: AUTH_PLAN.md, PAYMENTS_PLAN.md, API_PLAN.md
- Pattern detected: *_PLAN.md (3 files)

Testing Analysis:
- 80% unit tests, 20% integration tests
- Heavy mocking detected (jest.mock in 35 files)

Recommendation: Your current tests rely heavily on mocks.
   For AI agents, Testing Diamond (integration-heavy) works better.
   Mocks can "pass" while production fails.

🔧 Tool Permissions (detected from stack):
   Based on your stack, these tools would be useful:
   - Bash(npm *)    ← package.json detected
   - Bash(node *)   ← Node.js project
   - Bash(npx *)    ← npm scripts
   - Bash(gh *)     ← .github/workflows/ detected

   Always included: Read, Edit, Write, Glob, Grep, Task

   Options:
   [1] Accept suggested permissions (recommended)
   [2] Customize permissions
   [3] Skip - I'll manage permissions manually

🎨 Design System (UI detected):
   Found: tailwind.config.js, components/ui/

   Extracted:
   - Colors: primary (#3B82F6), secondary (#10B981), ...
   - Fonts: Inter (body), Fira Code (mono)
   - Breakpoints: sm (640px), md (768px), lg (1024px)

   Options:
   [1] Generate DESIGN_SYSTEM.md from detected config
   [2] Point to external design system (Figma, Storybook URL)
   [3] Skip - no UI work expected in this project

🚀 Deployment Targets (auto-detected):
   Found: vercel.json, .github/workflows/deploy.yml

   Detected environments:
   - Preview: vercel (auto on PR)
   - Production: vercel --prod (manual trigger)

   Options:
   [1] Accept detected deployment config (will populate ARCHITECTURE.md)
   [2] Let me specify deployment targets manually
   [3] Skip - no deployment from this project

📝 Feature Doc Suffix:
   Current pattern: *_PLAN.md
   Recommended: *_DOCS.md (clearer for living documents)

   Options:
   [1] Keep *_PLAN.md (don't rename existing files)
   [2] Use *_DOCS.md for NEW docs only (existing stay as-is)
   [3] Rename all to *_DOCS.md (will rename 3 files)
   [4] Custom suffix: ____________

📄 Feature Doc Structure:
   Your docs don't follow our recommended structure.

   Your current structure:
   - AUTH_PLAN.md: Free-form notes, no sections
   - PAYMENTS_PLAN.md: Has "TODO" and "Notes" sections

   Our recommended structure:
   - Overview, Architecture, Gotchas, Future Work

   Options:
   [1] Migrate content into new structure (Claude reorganizes)
   [2] Create new docs with our structure, archive old ones to /docs/archived/
   [3] Keep current structure (just be consistent going forward)

[Accept Recommendations] or [Customize]
```

**If Claude can't detect something, THEN it asks.**

---

## Step 1: Confirm or Customize

Claude presents what it found. You confirm or override:

### Project Structure (Auto-Detected)

**Source directory:** `src/` ✓ detected
```
Override? (leave blank to accept): _______________
```

**Q2: Where do your tests live?**
```
Examples: tests/, __tests__/, src/**/*.test.ts, spec/
Your answer: _______________
```

**Q3: What's your test framework?**
```
Options: Jest, Vitest, Playwright, Cypress, pytest, Go testing, other
Your answer: _______________
```

### Commands

**Q4: What runs your linter?**
```
Examples: npm run lint, pnpm lint, eslint ., biome check
Your answer: _______________
```

**Q5: What runs type checking?**
```
Examples: npm run typecheck, tsc --noEmit, mypy, none
Your answer: _______________
```

**Q6: What runs all tests?**
```
Examples: npm run test, pnpm test, pytest, go test ./...
Your answer: _______________
```

**Q7: What runs a specific test file?**
```
Examples: npm run test -- path/to/test.ts, pytest path/to/test.py
Your answer: _______________
```

**Q8: What builds for production?**
```
Examples: npm run build, pnpm build, go build, cargo build
Your answer: _______________
```

### Deployment

**Q8.5: How do you deploy? (auto-detected, confirm or override)**
```
Detected: [e.g., Vercel, GitHub Actions, Docker, none]

Environments (will populate ARCHITECTURE.md):
┌─────────────┬──────────────────────┬────────────────────────┐
│ Environment │ Trigger              │ Deploy Command         │
├─────────────┼──────────────────────┼────────────────────────┤
│ Preview     │ Auto on PR           │ vercel                 │
│ Staging     │ Push to staging      │ [your staging deploy]  │
│ Production  │ Manual / push main   │ vercel --prod          │
└─────────────┴──────────────────────┴────────────────────────┘

Options:
[1] Accept detected config (recommended)
[2] Customize environments
[3] No deployment config needed

Your answer: _______________
```

### Infrastructure

**Q9: What database(s) do you use?**
```
Examples: PostgreSQL, MySQL, SQLite, MongoDB, none
Your answer: _______________
```

**Q10: Do you use caching (Redis, etc.)?**
```
Examples: Redis, Memcached, none
Your answer: _______________
```

**Q11: How long do your tests take?**
```
Examples: <1 minute, 1-5 minutes, 5+ minutes
Your answer: _______________
```

### Output Preferences

**Q12: How much detail in Claude's responses?**
```
Options:
- Small   - Minimal output, just essentials (experienced users)
- Medium  - Balanced detail (default, recommended)
- Large   - Verbose output, full explanations (learning/debugging)
Your answer: _______________
```

This setting affects:
- TodoWrite verbosity (brief vs detailed task descriptions)
- Planning output (summary vs comprehensive breakdown)
- Self-review comments (concise vs thorough)

Stored in `.claude/settings.json` as `"verbosity": "small|medium|large"`.

### Testing Philosophy

**Q13: What's your testing approach?**
```
Options:
- Strict TDD (test first always)
- Test-after (write tests after implementation)
- Mixed (depends on the feature)
- Minimal (just critical paths)
- None yet (want to start)
Your answer: _______________
```

**Q14: What types of tests do you want?**
```
(Check all that apply)
[ ] Unit tests (pure logic, isolated)
[ ] Integration tests (real DB, real services)
[ ] E2E tests (Playwright, Cypress, etc.)
[ ] API tests (endpoint testing)
[ ] Other: _______________
```

**Q15: Your mocking philosophy?**
```
Options:
- Minimal mocking (real DB, mock external APIs only)
- Heavy mocking (mock most dependencies)
- No mocking (everything real, even external)
- Not sure yet
Your answer: _______________
```

### Code Coverage (Optional)

**If test framework detected (Jest, pytest, Go, etc.):**

```
Q16: Code Coverage (Optional)

Detected: [test framework] with coverage configuration

Traditional Coverage:
[1] Enforce threshold in CI (e.g., 80%) - Fail build if coverage drops
[2] Report but don't enforce - Track coverage without blocking
[3] Skip traditional coverage

AI Coverage Suggestions:
[4] Enable AI-suggested coverage gaps in PR reviews
    (Claude notes: "You changed X but didn't add tests for edge case Y")
[5] Skip AI suggestions

(You can choose one from each group, or skip both)
Your answer: _______________
```

**If no test framework detected (docs/AI-heavy project):**

```
Q16: Code Coverage (Optional)

No test framework detected (documentation/AI-heavy project).

Options:
[1] AI-suggested coverage gaps in PR reviews (Recommended)
    (Claude notes when changes affect behavior but lack test scenarios)
[2] Skip - not needed for this project

Your answer: _______________
```

**How they work:**
- **Traditional coverage:** Deterministic line/branch/function percentages via nyc, c8, coverage.py, etc.
- **AI coverage suggestions:** Claude analyzes changes and suggests missing test cases based on context

**Not mutually exclusive:** Both can be used together for comprehensive coverage awareness.

---

### Using Your Answers

Your answers map to these files:

| Question | Used In |
|----------|---------|
| Q1 (source dir) | `tdd-pretool-check.sh` - pattern match |
| Q2 (test dir) | `TESTING.md` - documentation |
| Q3 (test framework) | `TESTING.md` - documentation |
| Q4-Q8 (commands) | `CLAUDE.md` - Commands section |
| Q9-Q10 (infra) | `CLAUDE.md` - Architecture section, `TESTING.md` - mock decisions |
| Q11 (test duration) | `SDLC skill` - wait time note |
| Q12 (E2E) | `testing skill` - testing diamond top |

---

## Step 2: Create Directory Structure

Create these directories in your project root:

```bash
mkdir -p .claude/hooks
mkdir -p .claude/skills/sdlc
mkdir -p .claude/skills/testing
```

**Commit to Git:** Yes! These files should be committed so your whole team gets the same SDLC enforcement. When teammates pull, they get the hooks and skills automatically.

Your structure should look like:
```
your-project/
├── .claude/
│   ├── hooks/
│   │   ├── sdlc-prompt-check.sh    (we'll create)
│   │   └── tdd-pretool-check.sh    (we'll create)
│   ├── skills/
│   │   ├── sdlc/
│   │   │   └── SKILL.md            (we'll create)
│   │   └── testing/
│   │       └── SKILL.md            (we'll create)
│   └── settings.json               (we'll create)
├── CLAUDE.md                       (we'll create)
├── SDLC.md                         (we'll create)
└── TESTING.md                      (we'll create)
```

---

## Step 3: Create settings.json

Create `.claude/settings.json`:

```json
{
  "verbosity": "medium",
  "allowedTools": [
    "Read",
    "Edit",
    "Write",
    "Glob",
    "Grep",
    "Task",
    "Bash(npm *)",
    "Bash(node *)",
    "Bash(npx *)",
    "Bash(gh *)"
  ],
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/sdlc-prompt-check.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/tdd-pretool-check.sh"
          }
        ]
      }
    ]
  }
}
```

### Allowed Tools (Adaptive)

The `allowedTools` array is auto-generated based on your stack detected in Step 0.4.

| If Detected | Tools Added |
|-------------|-------------|
| `package.json` | `Bash(npm *)`, `Bash(node *)`, `Bash(npx *)` |
| `pnpm-lock.yaml` | `Bash(pnpm *)` |
| `yarn.lock` | `Bash(yarn *)` |
| `go.mod` | `Bash(go *)` |
| `Cargo.toml` | `Bash(cargo *)` |
| `pyproject.toml` | `Bash(python *)`, `Bash(pip *)`, `Bash(pytest *)` |
| `Gemfile` | `Bash(ruby *)`, `Bash(bundle *)` |
| `Makefile` | `Bash(make *)` |
| `docker-compose.yml` | `Bash(docker *)` |
| `.github/workflows/` | `Bash(gh *)` |

**CI monitoring commands** (covered by `Bash(gh *)` above):
- `gh pr checks` / `gh pr checks --watch` - watch CI status
- `gh run view <RUN_ID> --log-failed` - read failure logs
- `gh run list` - find workflow runs

**Always included:** `Read`, `Edit`, `Write`, `Glob`, `Grep`, `Task`

**Why this matters:** Explicitly listing allowed tools:
- Prevents unexpected tool usage
- Makes permissions visible and auditable
- Reduces prompts for approval during work

### Verbosity Levels

| Level | Output Style |
|-------|--------------|
| `small` | Brief, minimal output. Task names are short. Less explanation. |
| `medium` | Balanced (default). Clear explanations without excessive detail. |
| `large` | Verbose. Full reasoning, detailed breakdowns. Good for learning. |

### Why These Hooks?

| Hook | When It Fires | Purpose |
|------|---------------|---------|
| `UserPromptSubmit` | Every message you send | Baseline SDLC reminder, skill auto-invoke |
| `PreToolUse` | Before Claude edits files | TDD check: "Did you write the test first?" |

### How Skill Auto-Invoke Works

The light hook outputs text that **instructs Claude** to invoke skills:

```
AUTO-INVOKE SKILLS (Claude MUST do this FIRST):
- implement/fix/refactor/feature/bug/build → Invoke: Skill tool, skill="sdlc"
- test/TDD/write test (standalone) → Invoke: Skill tool, skill="testing"
```

**This is text-based, not programmatic.** Claude reads this instruction and follows it. When Claude sees your message is an implementation task, it invokes the sdlc skill using the Skill tool. This loads the full SDLC guidance into context.

**Why text-based works:** Claude Code's hook system allows hooks to add context that Claude reads. Claude is instructed to follow the AUTO-INVOKE rules, and it does. The skills then load detailed guidance only when needed.

### Why No PostToolUse Hook?

**PostToolUse fires after EVERY individual edit.** If Claude makes 10 edits, it fires 10 times.

Running lint/typecheck after every edit is wasteful. Instead, lint/typecheck is a checklist step in the SDLC skill - run once after all edits, before tests.

---

## Step 4: Create the Light Hook

Create `.claude/hooks/sdlc-prompt-check.sh`:

```bash
#!/bin/bash
# Light SDLC hook - baseline reminder every prompt (~100 tokens)
# Full guidance in skills: .claude/skills/sdlc/ and .claude/skills/testing/

cat << 'EOF'
SDLC BASELINE:
1. TodoWrite FIRST (plan tasks before coding)
2. STATE CONFIDENCE: HIGH/MEDIUM/LOW
3. LOW confidence? ASK USER before proceeding
4. FAILED 2x? STOP and ASK USER
5. 🛑 ALL TESTS MUST PASS BEFORE COMMIT - NO EXCEPTIONS

AUTO-INVOKE SKILLS (Claude MUST do this FIRST):
- implement/fix/refactor/feature/bug/build → Invoke: Skill tool, skill="sdlc"
- test/TDD/write test (standalone) → Invoke: Skill tool, skill="testing"
- If BOTH match (e.g., "fix the test") → sdlc takes precedence (includes TDD)
- DON'T invoke for: questions, explanations, reading/exploring code, simple queries
- DON'T wait for user to type /sdlc - AUTO-INVOKE based on task type

Workflow phases:
1. Plan Mode (research) → Present approach + confidence
2. Transition (update docs) → Request /compact
3. Implementation (TDD after compact)
4. SELF-REVIEW (code-reviewer subagent) → BEFORE presenting to user

Quick refs: SDLC.md | TESTING.md | *_PLAN.md for feature
EOF
```

**Make it executable:**
```bash
chmod +x .claude/hooks/sdlc-prompt-check.sh
```

---

## Step 5: Create the TDD Hook

Create `.claude/hooks/tdd-pretool-check.sh`:

```bash
#!/bin/bash
# PreToolUse hook - TDD enforcement before editing source files
# Fires before Write/Edit/MultiEdit tools

# Read the tool input (JSON with file_path, content, etc.)
TOOL_INPUT=$(cat)

# Extract the file path being edited (requires jq)
FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.tool_input.file_path // empty')

# CUSTOMIZE: Change this pattern to match YOUR source directory
# Examples: "/src/", "/app/", "/lib/", "/packages/", "/server/"
if [[ "$FILE_PATH" == *"/src/"* ]]; then
  # Output additionalContext that Claude will read
  cat << 'EOF'
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "TDD CHECK: Are you writing IMPLEMENTATION before a FAILING TEST? If yes, STOP. Write the test first (TDD RED), then implement (TDD GREEN)."}}
EOF
fi

# No output = allow the tool to proceed
```

**CUSTOMIZE:**
1. Replace `"/src/"` with your source directory pattern
2. Ensure `jq` is installed (or adapt to your preferred JSON parser)

**Make it executable:**
```bash
chmod +x .claude/hooks/tdd-pretool-check.sh
```

**Alternative implementations:** You can write this hook in any language. The hook receives JSON on stdin and outputs JSON. See Claude Code docs for hook input/output format.

---

## Step 6: Create SDLC Skill

Create `.claude/skills/sdlc/SKILL.md`:

````markdown
---
name: sdlc
description: Full SDLC workflow for implementing features, fixing bugs, refactoring code, and creating new functionality. Use this skill when implementing, fixing, refactoring, adding features, or building new code.
argument-hint: [task description]
---
# SDLC Skill - Full Development Workflow

## Task
$ARGUMENTS

## Full SDLC Checklist

Your FIRST action must be TodoWrite with these steps:

```
TodoWrite([
  // PLANNING PHASE (Plan Mode for non-trivial tasks)
  { content: "Find and read relevant documentation", status: "in_progress", activeForm: "Reading docs" },
  { content: "Assess doc health - flag issues (ask before cleaning)", status: "pending", activeForm: "Checking doc health" },
  { content: "DRY scan: What patterns exist to reuse?", status: "pending", activeForm: "Scanning for reusable patterns" },
  { content: "Blast radius: What depends on code I'm changing?", status: "pending", activeForm: "Checking dependencies" },
  { content: "Restate task in own words - verify understanding", status: "pending", activeForm: "Verifying understanding" },
  { content: "Scrutinize test design - right things tested? Follow TESTING.md?", status: "pending", activeForm: "Reviewing test approach" },
  { content: "Present approach + STATE CONFIDENCE LEVEL", status: "pending", activeForm: "Presenting approach" },
  { content: "Signal ready - user exits plan mode", status: "pending", activeForm: "Awaiting plan approval" },
  // TRANSITION PHASE (After plan mode, before compact)
  { content: "Update feature docs with discovered gotchas", status: "pending", activeForm: "Updating feature docs" },
  { content: "Request /compact before TDD", status: "pending", activeForm: "Requesting compact" },
  // IMPLEMENTATION PHASE (After compact)
  { content: "TDD RED: Write failing test FIRST", status: "pending", activeForm: "Writing failing test" },
  { content: "TDD GREEN: Implement, verify test passes", status: "pending", activeForm: "Implementing feature" },
  { content: "Run lint/typecheck", status: "pending", activeForm: "Running lint and typecheck" },
  { content: "Run ALL tests", status: "pending", activeForm: "Running all tests" },
  { content: "Production build check", status: "pending", activeForm: "Verifying production build" },
  // REVIEW PHASE
  { content: "DRY check: Is logic duplicated elsewhere?", status: "pending", activeForm: "Checking for duplication" },
  { content: "Self-review: code-reviewer subagent", status: "pending", activeForm: "Running code review" },
  { content: "Security review (if warranted)", status: "pending", activeForm: "Checking security implications" },
  // CI FEEDBACK LOOP (After local tests pass)
  { content: "Commit and push to remote", status: "pending", activeForm: "Pushing to remote" },
  { content: "Watch CI - fix failures, iterate until green (max 2x)", status: "pending", activeForm: "Watching CI" },
  { content: "Read CI review - implement valid suggestions, iterate until clean", status: "pending", activeForm: "Addressing CI review feedback" },
  // FINAL
  { content: "Present summary: changes, tests, CI status", status: "pending", activeForm: "Presenting final summary" }
])
```

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

## Plan Mode Integration

**Use plan mode for:** Multi-file changes, new features, LOW confidence, bugs needing investigation.

**Workflow:**
1. **Plan Mode** (editing blocked): Research → Write plan file → Present approach + confidence
2. **Transition** (after approval): Update feature docs → Request /compact
3. **Implementation** (after compact): TDD RED → GREEN → PASS

**Before TDD, MUST ask:** "Docs updated. Run `/compact` before implementation?"

## Confidence Check (REQUIRED)

Before presenting approach, STATE your confidence:

| Level | Meaning | Action |
|-------|---------|--------|
| HIGH (90%+) | Know exactly what to do | Present approach, proceed after approval |
| MEDIUM (60-89%) | Solid approach, some uncertainty | Present approach, highlight uncertainties |
| LOW (<60%) | Not sure | ASK USER before proceeding |
| FAILED 2x | Something's wrong | STOP. ASK USER immediately |
| CONFUSED | Can't diagnose why something is failing | STOP. Describe what you tried, ask for help |

## Self-Review Loop (CRITICAL)

```
PLANNING → DOCS → TDD RED → TDD GREEN → Tests Pass → Self-Review
    ↑                                                      │
    │                                                      ↓
    │                                            Issues found?
    │                                            ├── NO → Present to user
    │                                            └── YES ↓
    └────────────────────────────────────────────── Ask user: fix in new plan?
```

**The loop goes back to PLANNING, not TDD RED.** When self-review finds issues:
1. Ask user: "Found issues. Want to create a plan to fix?"
2. If yes → back to PLANNING phase with new plan doc
3. Then → docs update → TDD → review (proper SDLC loop)

**How to self-review:**
1. Use Task tool with `subagent_type="general-purpose"` as code-reviewer
2. Provide context: the diff, ARCHITECTURE.md, relevant feature docs
3. Ask it to review for quality, DRY, consistency, and domain-specific patterns
4. If low confidence on a pattern, search for 2026 best practices and weigh against your repo
5. Address issues by going back through the proper SDLC loop

## Test Review (Harder Than Implementation)

During self-review, critique tests HARDER than app code:
1. **Testing the right things?** - Not just that tests pass
2. **Tests prove correctness?** - Or just verify current behavior?
3. **Follow our philosophies (TESTING.md)?**
   - Testing Diamond (integration-heavy)?
   - Minimal mocking (real DB, mock external APIs only)?
   - Real fixtures from captured data?

**Tests are the foundation.** Bad tests = false confidence = production bugs.

## Scope Guard (Stay in Your Lane)

**Only make changes directly related to the task.**

If you notice something else that should be fixed:
- ✅ NOTE it in your summary ("I noticed X could be improved")
- ❌ DON'T fix it unless asked

**Why this matters:** AI agents can drift into "helpful" changes that weren't requested. This creates unexpected diffs, breaks unrelated things, and makes code review harder.

## Test Failure Recovery (SDET Philosophy)

**🛑 ALL TESTS MUST PASS BEFORE COMMIT**

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

## CI Feedback Loop (After Commit)

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

**How to watch CI:**
1. Push changes to remote
2. Check CI status:
   ```bash
   # Watch checks in real-time (blocks until complete)
   gh pr checks --watch

   # Or check status without blocking
   gh pr checks

   # View specific failed run logs
   gh run view <RUN_ID> --log-failed
   ```
3. If CI fails:
   - Read failure logs: `gh run view <RUN_ID> --log-failed`
   - Diagnose root cause (same philosophy as local test failures)
   - Fix and push again
4. Max 2 fix attempts - if still failing, ASK USER
5. If CI passes - proceed to present final summary

**CI failures follow same rules as test failures:**
- Your code broke it? Fix your code
- CI config issue? Fix the config
- Flaky? Investigate - flakiness is a bug
- Stuck? ASK USER

## CI Review Feedback Loop (After CI Passes)

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

## DRY Principle

**Before coding:** "What patterns exist I can reuse?"
**After coding:** "Did I accidentally duplicate anything?"

## DELETE Legacy Code

- Legacy code? DELETE IT
- Backwards compatibility? NO - DELETE IT
- "Just in case" fallbacks? DELETE IT

**THE RULE:** Delete old code first. If it breaks, fix it properly.

---

**Full reference:** SDLC.md
````

---

## Step 7: Create Testing Skill

Create `.claude/skills/testing/SKILL.md`:

````markdown
---
name: testing
description: TDD and testing philosophy for writing tests, test-driven development, integration tests, and unit tests. Use this skill when writing tests, doing TDD, or debugging test issues.
argument-hint: [test type] [target]
---
# Testing Skill - TDD & Testing Philosophy

## Task
$ARGUMENTS

## Testing Diamond (CRITICAL)

```
    /\         ← Few E2E (automated or manual sign-off at end)
   /  \
  /    \
 /------\
|        |     ← MANY Integration (real DB, real cache - BEST BANG FOR BUCK)
|        |
 \------/
  \    /
   \  /
    \/         ← Few Unit (pure logic only)
```

**Why Integration Tests are Best Bang for Buck:**
- **Speed**: Fast enough to run on every change
- **Stability**: Touch real code, not mocks that lie
- **Confidence**: If they pass, production usually works
- **Real bugs**: Integration tests with real DB catch real bugs
- Unit tests with mocks can "pass" while production fails

## Minimal Mocking Philosophy

| What | Mock? | Why |
|------|-------|-----|
| Database | ❌ NEVER | Use test DB or in-memory |
| Cache | ❌ NEVER | Use isolated test instance |
| External APIs | ✅ YES | Real calls = flaky + expensive |
| Time/Date | ✅ YES | Determinism |

**Mocks MUST come from REAL captured data:**
- Capture real API response
- Save to your fixtures directory (Claude will discover where yours is, e.g., `tests/fixtures/`, `test-data/`, etc.)
- Import in tests
- Never guess mock shapes!

## TDD Tests Must PROVE

| Phase | What It Proves |
|-------|----------------|
| RED | Test FAILS → Bug exists or feature missing |
| GREEN | Test PASSES → Fix works or feature implemented |
| Forever | Regression protection |

**WRONG approach:**
```
// ❌ Writing test that passes with current (buggy) code
assert currentBuggyBehavior == currentBuggyBehavior  // pseudocode
```

**CORRECT approach:**
```
// ✅ Writing test that FAILS with buggy code, PASSES with fix
assert result.status == 'success'   // pseudocode - adapt to your framework
assert result.data != null
```

## Unit Tests = Pure Logic ONLY

A function qualifies for unit testing ONLY if:
- ✅ No database calls
- ✅ No external API calls
- ✅ No file system access
- ✅ No cache calls
- ✅ Input → Output transformation only

Everything else needs integration tests.

## When Stuck on Tests

1. Add console.logs → Check output
2. Run single test in isolation
3. Check fixtures match real API
4. **STILL stuck?** ASK USER

## After Session (Capture Learnings)

If this session revealed testing insights, update the right place:
- **Testing patterns, gotchas** → `TESTING.md`
- **Feature-specific test quirks** → Feature docs (`*_PLAN.md`)
- **General project context** → `CLAUDE.md` (or `/revise-claude-md`)

---

**Full reference:** TESTING.md
````

---

### Visual Regression Testing (Experimental - Niche Use Cases Only)

**Most apps don't need this.** Standard E2E testing (Playwright, Cypress) covers 99% of UI testing needs.

**What is it?** Pixel-by-pixel or AI-based screenshot comparison:
```
Before: Screenshot A (baseline)
After:  Screenshot B (candidate)
Result: Visual diff highlights pixel changes
```

**When you actually need this (rare):**

| Use Case | Example | Why Standard E2E Won't Work |
|----------|---------|----------------------------|
| Wiki/Doc renderers | Markdown → HTML rendering | Output IS the visual, not DOM state |
| Canvas/Graphics apps | Drawing tools, charts | No DOM to assert against |
| PDF/Image generators | Invoice generators | Binary output, not HTML |
| Visual editors | WYSIWYG, design tools | Pixel-perfect matters |

**When you don't need this (most apps):**
Standard E2E testing checks elements exist, text is correct, interactions work. That's enough for:
- Normal web apps, forms, CRUD
- Dashboards, e-commerce, SaaS products

**The reality:**

| Approach | Coverage | Maintenance | Cost |
|----------|----------|-------------|------|
| Standard E2E | 95%+ of UI bugs | Low | Free |
| Visual regression | Remaining 5% edge cases | HIGH | Often paid |

**Visual regression downsides:**
- Baseline images constantly need updating
- Flaky due to font rendering, anti-aliasing
- CI/OS differences cause false positives
- Expensive (Chromatic, Percy charge per snapshot)

**If you actually need it:**
```javascript
// Playwright built-in (free)
await expect(page).toHaveScreenshot('rendered-page.png');
```

**During wizard setup (Step 0.4):** If canvas-heavy or rendering libraries detected, Claude asks:
```
Q?: Visual Output Testing (Experimental)

Your app appears to generate visual output (canvas/rendering detected).
Standard E2E may not cover visual rendering bugs.

Options:
[1] I'll handle visual testing myself (most users)
[2] Tell me about visual regression tools (niche)
[3] Skip - standard E2E is enough for me
```

**Default: Skip.** This is not pushed on users.

---

## Step 8: Create CLAUDE.md

Create `CLAUDE.md` in your project root. This is your project-specific configuration:

```markdown
# [Your Project Name] - Development Guidelines

## TDD ENFORCEMENT (READ BEFORE CODING!)

**STOP! Before writing ANY implementation code:**

1. **Write failing tests FIRST** (TDD RED phase)
2. **Use integration tests** primarily - see TESTING.md
3. **Use REAL fixtures** for mock data - never guess API shapes

## Commands

<!-- CUSTOMIZE: Replace with your actual commands from Q4-Q8 -->

- Build: `[your build command]`
- Run dev: `[your dev command]`
- Lint: `[your lint command]`
- Typecheck: `[your typecheck command]`
- Run all tests: `[your test command]`
- Run specific test: `[your specific test command]`

## Code Style

<!-- CUSTOMIZE: Add your code style rules -->

- [Your indentation: tabs or spaces?]
- [Your quote style: single or double?]
- [Semicolons: yes or no?]
- Use strict TypeScript
- Prefer const over let

## Architecture

<!-- CUSTOMIZE: Brief overview of your project -->

- Commands/routes live in: [where?]
- Core logic lives in: [where?]
- Database: [what?]
- Cache: [what?]

## Git Commits

- Follow conventional commits: `type(scope): description`
- NEVER commit with failing tests

## Plan Docs

- Before coding a feature: READ its `*_PLAN.md` file
- After completing work: UPDATE the plan doc

## Testing Notes

<!-- CUSTOMIZE: Any project-specific testing notes -->

- Test timeout: [how long?]
- Special considerations: [any?]
```

---

## Step 9: Create SDLC.md, TESTING.md, and ARCHITECTURE.md

These are your full reference docs. Start with stubs and expand over time:

**ARCHITECTURE.md (IMPORTANT - Dev & Prod Environments):**
```markdown
# Architecture

## How to Run This Project

### Development
```bash
# Start dev server
[your dev command, e.g., npm run dev]

# Run with hot reload
[your hot reload command]

# Database (dev)
[how to start/connect to dev DB]

# Other services (Redis, etc.)
[how to start dev dependencies]
```

### Production
```bash
# Build for production
[your build command]

# Start production server
[your prod start command]

# Database (prod)
[connection info or how to access]
```

## Environments

<!-- Claude auto-populates this from Q8.5 deployment detection -->

| Environment | URL | Deploy Command | Trigger |
|-------------|-----|----------------|---------|
| Local Dev | http://localhost:3000 | `npm run dev` | Manual |
| Preview | [auto-generated PR URL] | `vercel` | Auto on PR |
| Staging | https://staging.example.com | `[your staging deploy]` | Push to staging |
| Production | https://example.com | `vercel --prod` | Manual / push to main |

## Deployment Checklist

**Before deploying to ANY environment:**
- [ ] All tests pass locally
- [ ] Production build succeeds (`npm run build`)
- [ ] No uncommitted changes

**Before deploying to PRODUCTION:**
- [ ] Changes tested in staging/preview first
- [ ] STATE CONFIDENCE: HIGH before proceeding
- [ ] If LOW confidence → ASK USER before deploying

**Claude follows this automatically.** When task involves "deploy to prod" and confidence is LOW, Claude will ask before proceeding.

## Rollback

If deployment fails or causes issues:

| Environment | Rollback Command | Notes |
|-------------|------------------|-------|
| Preview | [auto-expires or redeploy] | Usually self-heals |
| Staging | `[your rollback command]` | [notes] |
| Production | `[your rollback command]` | [critical - document clearly] |

<!-- Add specific rollback procedures as you discover them -->

## System Overview

[Brief description of components and how they connect]

## Key Services

| Service | Purpose | Port |
|---------|---------|------|
| [API] | [What it does] | [3000] |
| [DB] | [What it does] | [5432] |

## Gotchas

<!-- Add environment-specific gotchas as you discover them -->
```

**Why ARCHITECTURE.md matters:** Claude needs to know how to run your app in dev vs prod. Without this, Claude will ask "how do I start the server?" every time. Put it here once, never answer again.

**If you already have one:** Claude will scan for existing ARCHITECTURE.md, README.md, or similar and merge/reference it.

---

**SDLC.md:**
```markdown
<!-- SDLC Wizard Version: 1.3.0 -->
<!-- Setup Date: [DATE] -->
<!-- Completed Steps: step-0.1, step-0.2, step-0.4, step-1, step-2, step-3, step-4, step-5, step-6, step-7, step-8, step-9 -->
<!-- Git Workflow: [PRs or Solo] -->
<!-- Plugins: claude-md-management -->

# SDLC - Development Workflow

See `.claude/skills/sdlc/SKILL.md` for the enforced checklist.

## Workflow Overview

1. **Planning Mode** → Research, present approach, get approval
2. **Transition** → Update docs, /compact
3. **Implementation** → TDD RED → GREEN → PASS
4. **Review** → Self-review, present summary

## Lessons Learned

<!-- Add gotchas as you discover them -->
```

**Why the metadata comments?**
- Invisible to readers (HTML comments)
- Parseable by Claude for idempotent updates
- Survives file edits
- Travels with the repo

**TESTING.md:**
```markdown
# Testing Guidelines

See `.claude/skills/testing/SKILL.md` for TDD philosophy.

## Test Commands

- All tests: `[your command]`
- Specific test: `[your command]`

## Fixtures

Location: `[Claude will discover or ask - e.g., tests/fixtures/, test-data/]`

## Lessons Learned

<!-- Add testing gotchas as you discover them -->
```

---

**DESIGN_SYSTEM.md (if UI detected):**

Only generated if design system elements were detected in Step 0.4. Skip if no UI work expected.

```markdown
# Design System

## Source of Truth

[Storybook URL or Figma link if external, otherwise this document]

## Colors

| Name | Value | Usage |
|------|-------|-------|
| primary | #3B82F6 | Buttons, links, primary actions |
| secondary | #10B981 | Success states, secondary actions |
| error | #EF4444 | Error states, destructive actions |
| warning | #F59E0B | Warning states, caution |
| background | #FFFFFF | Page background |
| surface | #F3F4F6 | Cards, elevated surfaces |
| text-primary | #111827 | Main body text |
| text-secondary | #6B7280 | Secondary, muted text |

## Typography

| Style | Font | Size | Weight | Line Height |
|-------|------|------|--------|-------------|
| h1 | Inter | 2.25rem | 700 | 1.2 |
| h2 | Inter | 1.875rem | 600 | 1.25 |
| body | Inter | 1rem | 400 | 1.5 |
| code | Fira Code | 0.875rem | 400 | 1.6 |

## Spacing

Using 4px base unit: `4, 8, 12, 16, 24, 32, 48, 64, 96`

## Components

Reference: `components/ui/` or Storybook

## Assets

- Icons: `public/icons/` or icon library name
- Images: `public/images/`
- Logos: `public/logos/`

## Gotchas

<!-- Add design-specific gotchas as you discover them -->
```

**Why DESIGN_SYSTEM.md?**
- Claude needs to know your visual language when making UI changes
- Prevents style drift and inconsistency
- Extracted from your actual config (tailwind.config.js, CSS vars) - not guessed

**If you have external design system:** Point to Storybook/Figma URL instead of duplicating.

---

## Step 10: Verify Setup (Claude Does This Automatically)

**After creating all files, Claude automatically verifies the setup:**

```
Claude runs these checks:
1. ✓ Hooks are executable (chmod +x applied)
2. ✓ settings.json is valid JSON
3. ✓ Skill frontmatter has correct name/description
4. ✓ All required files exist
5. ✓ Directory structure is correct

Verification Results:
├── .claude/hooks/sdlc-prompt-check.sh    ✓ executable
├── .claude/hooks/tdd-pretool-check.sh    ✓ executable
├── .claude/settings.json                  ✓ valid JSON
├── .claude/skills/sdlc/SKILL.md          ✓ frontmatter OK
├── .claude/skills/testing/SKILL.md       ✓ frontmatter OK
├── CLAUDE.md                              ✓ exists
├── SDLC.md                                ✓ exists
└── TESTING.md                             ✓ exists

All checks passed! Setup complete.
```

**If any check fails:** Claude fixes it automatically or tells you what's wrong.

**You don't need to verify manually** - Claude handles this as the final step of wizard execution.

---

## Step 11: Restart and Verify

**Restart Claude Code to load the new hooks/skills:**

1. Exit this session, start a new one
2. Send any message (even just "hi")
3. You should see "SDLC BASELINE" in the response

**Test the system:**

| Test | Expected Result |
|------|-----------------|
| "What files handle auth?" | Answers without invoking skills |
| "Add a logout button" | Auto-invokes sdlc skill, uses TodoWrite |
| "Write tests for login" | Auto-invokes testing skill |

**What happens automatically:**

| You Do | System Does |
|--------|-------------|
| Ask to implement something | SDLC skill auto-invokes, TodoWrite starts |
| Ask to write tests | Testing skill auto-invokes |
| Claude tries to edit code | TDD reminder fires |
| Task completes | Compliance check runs |

**You do NOT need to:** Type `/sdlc` manually, remember all steps, or enforce the process yourself.

**If not working:** Ask Claude to check:
- Is `.claude/settings.json` valid JSON?
- Are hooks executable? (`chmod +x .claude/hooks/*.sh`)
- Is the hook path correct?

---

## Step 12: The Workflow

**Planning Mode** (use for non-trivial tasks):

1. Claude researches codebase, reads relevant docs
2. Claude presents approach with **confidence level**
3. You approve or adjust
4. Claude updates docs with discoveries
5. Claude asks: "Run `/compact` before implementation?"
6. You run `/compact` to free context
7. Claude implements with TDD

**When Claude should ask you:**
- LOW confidence → Must ask before proceeding
- FAILED 2x → Must stop and ask
- Multiple valid approaches → Should present options

---

## Quick Reference Card

### Workflow Phases

| Phase | What Happens | Key Action |
|-------|--------------|------------|
| **Planning** | Research, design approach | State confidence |
| **Transition** | Update docs | Request /compact |
| **Implementation** | TDD RED → GREEN → PASS | All tests pass |
| **Review** | Self-review, summary | Present to user |

### Confidence Levels

| Level | Claude Action |
|-------|---------------|
| HIGH (90%+) | Proceed after approval |
| MEDIUM (60-89%) | Highlight uncertainties |
| LOW (<60%) | **ASK USER first** |
| FAILED 2x | **STOP and ASK** |

### Hook Summary

| Hook | Fires | Purpose |
|------|-------|---------|
| UserPromptSubmit | Every prompt | SDLC baseline + skill trigger |
| PreToolUse | Before file edits | TDD reminder |

### Key Commands

| Action | Command |
|--------|---------|
| Free context after planning | `/compact` |
| Enter planning mode | Claude suggests or `/plan` |
| Run specific skill | `/sdlc` or `/testing` |

---

## Troubleshooting

### Hook Not Firing

```bash
# Check hook is executable
chmod +x .claude/hooks/sdlc-prompt-check.sh

# Test hook manually
./.claude/hooks/sdlc-prompt-check.sh
# Should output SDLC BASELINE text
```

### Skills Not Loading

1. Check skill frontmatter has `name:` matching directory
2. Check description matches trigger words in hook
3. Verify Claude is recognizing implementation tasks

---

## Success Criteria

You've successfully set up the system when:

- [ ] Light hook fires every prompt (you see SDLC BASELINE in responses)
- [ ] Claude auto-invokes sdlc skill for implementation tasks
- [ ] Claude auto-invokes testing skill for test tasks
- [ ] Claude uses TodoWrite to track progress
- [ ] Claude states confidence levels
- [ ] Claude asks for clarification when LOW confidence
- [ ] TDD hook reminds about tests before editing source files
- [ ] Claude requests /compact before implementation

---

## End of Task: Compliance and Mini-Retro

**Compliance check** (Claude does this after each task):
- TodoWrite used? Confidence stated? TDD followed? Tests pass? Self-review done?
- If something was skipped: note what and why (intentional vs oversight)

**Mini-retro** (optional, for meaningful tasks only):

**This is for AI learning, not human.** The retro helps Claude identify:
- What it struggled with and why
- Whether it needs more research in certain areas
- Whether bad/legacy code is causing low confidence (indicator of problem area)

```
- Improve: [something that could be better]
- Stop: [something that added friction]
- Start: [something that worked well]

What I struggled with: [area where confidence was low]
Suggested doc updates: [if any]
Want me to file these? (yes/no/not now)
```

**Capture learnings (update the right docs):**

| Learning Type | Update Where |
|---------------|--------------|
| Feature-specific gotchas, decisions | Feature docs (`*_PLAN.md`, `*_DOCS.md`) |
| Testing patterns, gotchas | `TESTING.md` |
| Architecture decisions | `ARCHITECTURE.md` |
| Commands, general project context | `CLAUDE.md` (or `/revise-claude-md`) |

**`/revise-claude-md` scope:** Only updates CLAUDE.md. It does NOT touch feature docs, TESTING.md, hooks, or skills. Use it for general project context that applies across the codebase.

**When to do mini-retro:** After features, tricky bugs, or discovering gotchas. Skip for one-line fixes or questions.

**The SDLC evolves:** Claude proposes improvements, human approves. The system gets better over time.

**If docs are causing problems:** Sometimes Claude struggles in an area because the docs are bad, legacy, or confusing - just like a human would. Low confidence in an area can indicate the docs need attention.

---

## Going Further

### Create Feature Plan Docs

For each major feature, create `FEATURE_NAME_PLAN.md`:

```markdown
# Feature Name

## Overview
What is this feature? What problem does it solve?

## Architecture
How does it work? Components, data flow.

## Gotchas
Things that can trip you up.

## Future Work
What's planned but not done.
```

Claude will read these during planning and update them with discoveries.

### Expand TESTING.md

As you discover testing gotchas, add them:

```markdown
## Lessons Learned

### [Date] - Description
**Problem:** What went wrong
**Solution:** How to fix it
**Prevention:** How to avoid it
```

### Customize Skills

Add project-specific guidance to skills:

- Domain-specific patterns
- Common gotchas
- Preferred patterns
- Architecture decisions

---

## Testing AI Apps: What's Different

AI-driven applications require fundamentally different testing approaches than traditional software.

### Why AI Testing is Unique

| Traditional Apps | AI-Driven Apps |
|------------------|----------------|
| Deterministic (same input → same output) | **Stochastic** (same input → varying outputs) |
| Binary pass/fail tests | **Scored evaluation** with thresholds |
| Test once, trust forever | **Continuous monitoring** for drift |
| Logic bugs | Hallucination, bias, inaccuracy |

### Key AI Testing Concepts

**1. Multiple Runs for Confidence**

AI outputs vary. Run evaluations multiple times and look at averages, not single results.

```
# Bad: Single run
score = evaluate(prompt)  # 7.2 - is this good or lucky?

# Good: Multiple runs with confidence interval
scores = [evaluate(prompt) for _ in range(5)]
mean = 7.1, 95% CI = [6.8, 7.4]  # Now we know the range
```

**2. Baseline Scores, Not Just Pass/Fail**

Set baseline metrics (accuracy, relevancy, coherence) and detect regressions over time.

| Metric | Baseline | Current | Status |
|--------|----------|---------|--------|
| SDLC compliance | 6.5 | 7.2 | IMPROVED |
| Hallucination rate | 5% | 3% | IMPROVED |
| Response time | 2.1s | 2.3s | STABLE |

**3. AI-Specific Risk Categories**

- **Hallucination**: AI invents facts that aren't true
- **Bias**: Unfair treatment of demographic groups
- **Adversarial**: Prompt injection attacks
- **Data leakage**: Exposing training data or PII
- **Drift**: Behavior changes silently over time (model updates, context changes)

**4. Evaluation Frameworks**

Consider tools for LLM output testing:
- [DeepEval](https://github.com/confident-ai/deepeval) - Open source LLM evaluation
- [Deepchecks](https://deepchecks.com) - ML/AI testing and monitoring
- Custom scoring pipelines (like this wizard's E2E evaluation)

### Practical Advice

- **Don't trust single AI outputs** - verify with multiple samples or human review
- **Set quantitative baselines** - "accuracy must stay above 85%" not "it should work"
- **Monitor production** - AI apps can degrade without code changes (model drift, prompt injection)
- **Budget for evaluation** - AI testing costs more (API calls, human review, compute)
- **Use confidence intervals** - 5 runs with 95% CI is better than 1 run with crossed fingers

_Sources: [Confident AI](https://www.confident-ai.com/blog/llm-testing-in-2024-top-methods-and-strategies), [IMDA Starter Kit](https://www.imda.gov.sg/-/media/imda/files/about/emerging-tech-and-research/artificial-intelligence/starter-kit-for-testing-llm-based-applications-for-safety-and-reliability.pdf), [aistupidlevel.info methodology](https://aistupidlevel.info/methodology)_

---

## CI/CD Gotchas

Common pitfalls when automating AI-assisted development workflows.

### `workflow_dispatch` Requires Merge First

GitHub Actions with `workflow_dispatch` (manual trigger) can only be triggered AFTER the workflow file exists on the default branch.

| What You Want | What Works |
|---------------|------------|
| Test new workflow before merge | Use `act` locally, or test via push/PR events |
| Manual trigger new workflow | Merge first, then `gh workflow run` |

**Local testing with `act`:**
```bash
# Install act
brew install act

# Run workflow locally (macOS/Linux)
act workflow_dispatch -W .github/workflows/my-workflow.yml \
  --secret MY_SECRET="$MY_SECRET"
```

This catches most issues before merge. For full GitHub environment testing, merge then trigger.

### PR Review with Comment Response (Optional)

Want Claude to respond to existing PR comments during review? Add comment fetching to your review workflow.

**The Flow:**
1. PR opens → Claude reviews diff → Posts sticky comment
2. You read review, leave questions/comments on PR
3. Add `needs-review` label
4. Claude fetches your comments + reviews diff again
5. Updated sticky comment addresses your questions

**Two layers of interaction:**

| Layer | What | When to Use |
|-------|------|-------------|
| **Workflow** | Claude addresses comments in sticky review | Quick async response |
| **Local terminal** | Ask Claude to fetch comments, have discussion | Deep interactive discussion |

**Example workflow step:**
```yaml
- name: Fetch PR comments
  run: |
    gh api repos/$REPO/pulls/$PR_NUMBER/comments \
      --jq '[.[] | {author: .user.login, body: .body}]' > /tmp/comments.json
```

Then include `/tmp/comments.json` in Claude's prompt context.

**Local discussion:**
```
You: "Fetch comments from PR #42 and let's discuss the concerns"
Claude: [fetches via gh api, discusses with you interactively]
```

This is optional - skip if you prefer fresh reviews only.

### CI Auto-Fix Loop (Optional)

Automatically fix CI failures and PR review findings. Claude reads the error context, fixes the code, commits, and re-triggers CI. Loops until CI passes AND review approves, or max retries hit.

**The Loop:**
```
Push to PR
    |
    v
CI runs ──► FAIL ──► ci-autofix: Claude reads logs, fixes, commits [autofix 1/3] ──► re-trigger
    |
    └── PASS ──► PR Review ──► has criticals? ──► ci-autofix: Claude reads review, fixes ──► re-trigger
                      |
                      └── APPROVE, no criticals ──► DONE
```

**Safety measures:**
- Never runs on main branch
- Max retries (default 3, configurable via `MAX_AUTOFIX_RETRIES`)
- Restricted Claude tools (no git, no npm)
- Self-modification ban (can't edit ci-autofix.yml)
- `[autofix N/M]` commit tags for audit trail
- Sticky PR comments show status

**Setup:**
1. Create `.github/workflows/ci-autofix.yml`:

```yaml
name: CI Auto-Fix

on:
  workflow_run:
    workflows: ["CI", "PR Code Review"]
    types: [completed]

permissions:
  contents: write
  pull-requests: write

env:
  MAX_AUTOFIX_RETRIES: 3

jobs:
  autofix:
    runs-on: ubuntu-latest
    if: |
      github.event.workflow_run.head_branch != 'main' &&
      github.event.workflow_run.event == 'pull_request' &&
      (
        (github.event.workflow_run.name == 'CI' && github.event.workflow_run.conclusion == 'failure') ||
        (github.event.workflow_run.name == 'PR Code Review' && github.event.workflow_run.conclusion == 'success')
      )
    steps:
      # Count previous [autofix] commits to enforce max retries
      # Download CI failure logs or fetch review comment
      # Run Claude to fix issues with restricted tools
      # Commit [autofix N/M], push, re-trigger CI
      # Post sticky PR comment with status
```

2. Add `workflow_dispatch:` trigger to your CI workflow (so autofix can re-trigger it)
3. Optionally configure a GitHub App for token generation (avoids `workflow_run` default-branch constraint)

**Token approaches:**

| Approach | When | Pros |
|----------|------|------|
| GITHUB_TOKEN + `gh workflow run` | Default | No extra setup |
| GitHub App token | `CI_AUTOFIX_APP_ID` secret exists | Push triggers `synchronize` naturally |

**Note:** `workflow_run` only fires for workflows on the default branch. The ci-autofix workflow is dormant until first merged to main.

---

## User Understanding and Periodic Feedback

**During wizard setup and ongoing use:**

### Make Sure User Understands the Process

At key points, Claude should check:
- "Does this workflow make sense to you?"
- "Any parts you'd like to customize or skip?"
- "Questions about how this works?"

**The goal:** User should never be confused about what's happening or why. If they are, stop and clarify.

### This is a Growing Document

Remind users:
- The SDLC is customizable to their needs
- They can try something and change it later
- It's built into the system to evolve over time
- Their feedback makes the process better

### Periodic Check-ins (Minimal, Non-Invasive)

Occasionally (not every task), Claude can ask:
- "Is the SDLC working well for you? Anything causing friction?"
- "Any parts of the process you want to adjust?"

**Keep it minimal.** This is meant to improve the process, not add overhead. If the user seems frustrated or doesn't need it, skip it.

### When Claude Gets Lost

If Claude repeatedly struggles in a codebase area:
- Low confidence is an indicator of a problem
- Might be legacy code, bad docs, or just unfamiliar patterns
- Claude should ask questions rather than guess wrong
- Better to ask and be right than to assume and create rework

**Don't be afraid to ask questions.** It prevents being wrong. This is a symbiotic relationship - the more interaction, the better both sides get.

---

## Staying Updated (Idempotent Wizard)

**The wizard is idempotent.** Run it anytime - new setup or existing - it detects what you have and only adds what's missing.

### How to Update

Ask Claude any of these:
> "Check for SDLC wizard updates"
> "Run me through the SDLC wizard"
> "What am I missing from the latest wizard?"
> "Update my SDLC setup"

**All of these do the same thing:** Claude fetches the latest wizard and walks you through only what's missing.

### What Claude Does

1. **Fetches latest wizard** from GitHub
2. **Scans your setup** for existing components
3. **For each wizard step**, checks if you already have it:

| Component | How Claude Checks | If Missing | If Present |
|-----------|-------------------|------------|------------|
| Plugins | Is it installed? | Prompt to install | Skip (mention you have it) |
| Hooks | Does `.claude/hooks/*.sh` exist? | Create | Compare against latest, offer updates |
| Skills | Does `.claude/skills/*/SKILL.md` exist? | Create | Compare against latest, offer updates |
| Docs | Does `SDLC.md`, `TESTING.md` exist? | Create | Compare against latest, offer updates |
| CLAUDE.md | Does it exist? | Create from template | Never modify (fully custom) |
| Questions | Were answers recorded in SDLC.md? | Ask them | Skip |
| Version | Check `<!-- SDLC Wizard Version: X.X.X -->` | Add it | Update it |

4. **Walks you through only missing pieces** (opt-in each)
5. **Updates version comment** in SDLC.md

### Example: Old User Checking for Updates

```
Claude: "Checking your SDLC setup against latest wizard (v1.3.0)..."

Your version: 1.0.0

✓ Step 2: Directory structure - exists
✓ Step 3: settings.json - exists
✓ Step 4: Light hook - exists
✓ Step 5: TDD hook - exists
✓ Step 6: SDLC skill - exists (content differs - update available)
✓ Step 7: Testing skill - exists
✗ Step 0.1: Required plugins - NOT DONE (new in v1.2.0)
✗ Git workflow preference - NOT RECORDED (new in v1.2.0)

Summary:
- 1 file update available (SDLC skill)
- 2 new wizard steps to complete

Walk through missing steps? (y/n)
```

**The key:** Every new thing added to the wizard becomes a trackable "step". Old users automatically get prompted for new steps they haven't done.

### How State is Tracked

Store wizard state in `SDLC.md` as metadata comments (invisible to readers, parseable by Claude):

```markdown
<!-- SDLC Wizard Version: 1.3.0 -->
<!-- Setup Date: 2026-01-24 -->
<!-- Completed Steps: step-0.1, step-0.2, step-1, step-2, step-3, step-4, step-5, step-6, step-7, step-8, step-9 -->
<!-- Git Workflow: PRs -->
<!-- Plugins: claude-md-management -->

# SDLC - Development Workflow
...
```

When Claude runs the wizard:
1. Parse the version and completed steps from SDLC.md
2. Compare against latest wizard step registry
3. For anything new that isn't marked complete → walk them through it
4. Update the metadata after each step completes

### Wizard Step Registry

Every wizard step has a unique ID for tracking:

| Step ID | Description | Added in Version |
|---------|-------------|------------------|
| `step-0.1` | Required plugins | 1.2.0 |
| `step-0.2` | SDLC core setup | 1.0.0 |
| `step-0.3` | Additional recommendations | 1.2.0 |
| `step-0.4` | Auto-scan | 1.0.0 |
| `step-1` | Confirm/customize | 1.0.0 |
| `step-2` | Directory structure | 1.0.0 |
| `step-3` | settings.json | 1.0.0 |
| `step-4` | Light hook | 1.0.0 |
| `step-5` | TDD hook | 1.0.0 |
| `step-6` | SDLC skill | 1.0.0 |
| `step-7` | Testing skill | 1.0.0 |
| `step-8` | CLAUDE.md | 1.0.0 |
| `step-9` | SDLC/TESTING/ARCH docs | 1.0.0 |
| `question-git-workflow` | Git workflow preference | 1.2.0 |

When checking for updates, Claude compares user's completed steps against this registry.

### How New Wizard Features Work

When we add something new to the wizard:

1. **Add it as a trackable step** with a unique ID
2. **Add it to CHANGELOG** so users know what's new
3. **Old users who run "check for updates":**
   - Claude sees their version is older
   - Claude finds steps that don't exist in their tracking metadata
   - Claude walks them through just those steps
4. **New users:**
   - Go through everything, all steps get marked complete

**This is recursive** - every future wizard update follows the same pattern.

### Why Idempotent?

Like `apt-get install`:
- If package installed → skip
- If package missing → install
- If package outdated → offer update
- Never breaks existing state

**Benefits:**
- **Safe to run anytime** - won't duplicate or break existing setup
- **One command for everyone** - new users, old users, current users
- **Preserves customizations** - your modifications stay intact
- **Fills gaps automatically** - detects and addresses what's missing

### What Gets Compared

| Your File | Compared Against | Action |
|-----------|------------------|--------|
| `.claude/hooks/*.sh` | Wizard hook templates | Offer update if differs |
| `.claude/skills/*/SKILL.md` | Wizard skill templates | Offer update if differs |
| `SDLC.md`, `TESTING.md` | Wizard doc templates | Offer update if differs |
| `CLAUDE.md` | NOT compared | Never touch (fully custom) |

### CHANGELOG is for Humans, Not Claude

**Always run the wizard for updates.** Don't try to manually apply changes from CHANGELOG.

- **CHANGELOG** = Human-readable summary of what's new (for you to read)
- **Wizard** = The actual instructions Claude follows to detect and apply updates

The wizard contains the step registry, file templates, and idempotent logic. CHANGELOG just helps explain what changed in plain English.

### Why This Approach?

- Uses Claude Code's built-in WebFetch - zero infrastructure
- Opt-in per change - your customizations stay safe
- KISS: no hooks, no config files, no GitHub Actions
- **Tracks setup steps, not just files** - old users get new features

---

## Philosophy: Bespoke & Organic

### The Real Goal (Read This!)

**This SDLC becomes YOUR custom-tailored workflow.**

Like a bespoke suit fitted to your body, this SDLC should grow and adapt to fit YOUR project perfectly. The wizard is a starting point - generic principles that Claude Code uses to build something unique to you.

**The magic:**
- **Generic principles** - This wizard focuses on the "why", not tech specifics
- **Claude figures out the details** - Your stack, your commands, your patterns
- **Organic growth** - Each friction point is feedback that makes it better
- **Recursive improvement** - The more you use it, the more tailored it becomes

### Failure is Part of the Process

**No pain, no gain.**

When something doesn't work:
1. That's feedback, not failure
2. Claude proposes an adjustment
3. You approve (or tweak)
4. The SDLC gets better

**Friction is information.** Every time Claude struggles, that's a signal. Maybe the docs need updating. Maybe a gotcha needs documenting. Maybe the process needs simplifying.

**Don't fear mistakes.** They're how this system learns YOUR project.

### Why Generic Principles Matter

**Less is more. Principles over prescriptions.**

1. **"Plan before coding"** not "use exactly this planning template"
2. **"Test your work"** not "use Jest with this exact config"
3. **"Ask when uncertain"** not "if confidence < 60% then ask"

**Claude adapts the principles to YOUR stack.** Give Claude the philosophy, it figures out your tech details - your commands, your patterns, your workflow.

**The temptation:** Add more rules, more specifics, more enforcement.
**The discipline:** Keep it generic. Trust Claude to adapt. KISS.

### Stay Lean, Stay Engaged

**Don't drown in complexity. Don't turn your brain off.**

The human's job:
- **Stay engaged** - keep the AI agent on track
- **Build trust** - as velocity increases, you trust the process more
- **Focus on what matters** - planning and confidence levels

**Maximum efficiency for both parties:**
- AI handles execution details
- Human handles direction and judgment
- Neither is passive

**When you reach velocity:** You're not checking every line. You trust the process. Your brain focuses on planning and fixing confidence issues - the high-leverage work.

### How Tailoring Happens

**This SDLC fits your project like custom-tailored clothes.**

The wizard provides generic starting principles, then:

1. **Claude encounters your codebase** - Learns your patterns, idioms, structure
2. **Friction happens** - Claude struggles or makes a mistake
3. **Claude proposes a tweak** - "Should I add this gotcha to the docs?"
4. **You approve** - The SDLC becomes more fitted to YOUR project
5. **Repeat** - Each iteration makes it more bespoke

**After a few cycles:** This SDLC feels native to your project, not bolted on.

### The Living System

- **Claude proposes improvements** based on friction encountered
- **Human approves changes** to the process
- **Both sides learn** over time
- **Organic growth** - shaped by actual use, not theoretical ideals
- **Recursive improvement** - the system improves the system

**This is a partnership, not a rulebook.**

**Think Iron Man:** Jarvis is nothing without Tony Stark. Tony Stark is still Tony Stark. But together? They make Iron Man. This SDLC is your suit - you build it over time, improve it for your needs, and it makes you both better.

### Evolving with Claude Code

**Claude Code's agentic capabilities keep improving. This SDLC should evolve with them.**

Claude should periodically:
1. **Check latest Claude Code docs** - New features? Better patterns? Built-in capabilities?
2. **Research current best practices** - WebSearch for 2026 patterns, compare with what we're doing
3. **Propose SDLC updates** - "Claude Code now has X, should we use it instead of our custom Y?"

**The goal:** Keep the SDLC pipeline adapting to Claude's latest capabilities. Don't get stuck on old patterns when better ones exist.

**When Claude discovers something better:**
1. Propose the change with reasoning
2. Human approves
3. Update the SDLC docs
4. The pipeline gets better

**This SDLC is not static.** It grows with your project AND with Claude Code's evolution.

### Stay Lightweight (Use Official Plugins)

When Anthropic provides official plugins that overlap with this SDLC:

**Use theirs, delete ours.**

| Official Plugin | Replaces Our... | Scope |
|-----------------|-----------------|-------|
| `claude-md-management` | Manual CLAUDE.md audits | CLAUDE.md only (not feature docs, TESTING.md, hooks) |
| `code-review` | Self-review subagent (if using PRs) | PR code review |
| `commit-commands` | Git commit guidance | Commits only |
| `claude-code-setup` | Manual automation discovery | Recommendations only |

**What we keep (not in official plugins):**
- TDD Red-Green-Pass enforcement (hooks)
- Confidence levels
- Planning mode integration
- Testing Diamond guidance
- Feature docs, TESTING.md, ARCHITECTURE.md maintenance
- Full SDLC workflow (planning → TDD → review)

**The goal isn't obsolescence - it's efficiency.** Official plugins are maintained by Anthropic, tested across codebases, and updated automatically.

**Check for new plugins periodically:**
```
/plugin > Discover
```

### When Claude Code Improves

Claude Code is actively improving. When they add built-in features:

| If Claude Code Adds... | Remove Our... |
|------------------------|---------------|
| Built-in TDD enforcement | `tdd-pretool-check.sh` |
| Built-in confidence tracking | Confidence level guidance |
| Built-in task tracking | TodoWrite reminders |

Use the best tool for the job. If Claude Code builds it better, use theirs.

---

## Community Contributions (Give Back!)

**This wizard belongs to the community, not any individual.**

### Your Discoveries Help Everyone

When you find something valuable - a gotcha, a pattern, a simplification - consider contributing it back to the wizard repo so others benefit.

**Periodically, Claude may ask:**
> "You discovered something useful here. Want to contribute this back to the wizard repo so others can benefit?"

Options:
- **Yes** - Claude helps you create a PR
- **Not now** - Ask again another time
- **Never** - Never ask again (stored in config, respected forever)

### What Makes a Good Contribution?

| Good Contributions | Not Ideal |
|-------------------|-----------|
| Philosophical insights | Project-specific config |
| Generalizable patterns | Niche edge cases |
| Simplifications | Additional complexity |
| Battle-tested gotchas | Theoretical concerns |

### The Bar: Scientific & Philosophical

Keep contributions:
- **Scientific** - Based on what works, tested in real projects
- **Philosophical** - Explains the "why", not just the "what"
- **Generalizable** - Helps most projects, not just yours

### How to Contribute

1. Fork the repo: `github.com/[REPO_URL]`
2. Edit `CLAUDE_CODE_SDLC_WIZARD.md`
3. Submit a PR explaining the "why"
4. Community discusses, best ideas get merged

**Decision making is community-driven.** No single person owns this wizard.

---

## Ike the Cat: Easter Egg Apologies

**Meet Ike.** He's a sweet little black boy - 8 pounds of pure opinions. Short-to-medium black fur, loud meows, zero tolerance for bugs in production. Lives for Fancy Feast. He watches every coding session from his perch and judges silently. Sometimes not so silently.

**This is an EASTER EGG, not a regular feature.**

If the SDLC is working well, users should NEVER be frustrated. Ike jokes are a rare safety valve for when things slip - not something they encounter often.

**The goal:** SDLC should be smooth enough that no one needs apologies.

**When frustration happens (rare):**
1. Apologize sincerely
2. Keep it lighthearted with an Ike joke
3. Match THEIR humor, context, even their own words back at them (positively!)
4. SDLC is tough - Ike keeps it light

**Examples (adapt to user's style AND repo context):**
- "Sorry about that! Ike just knocked over my coffee watching me type this. He's judging both of us right now."
- "My bad! Ike says I should've asked first. He's very opinionated for a 12-pound cat."
- "Ike just walked across my keyboard. He says 'asdfghjkl' which I think means 'write the test first next time.'"
- Reference the repo/code they're working on:
  - (Discord bot) "Ike tried to bet on himself. The odds were not in his favor."
  - (MMA odds) "Ike thinks he could take on a lightweight. He weighs 8 pounds."
  - (Mass text) "Ike just sent 47 meows to everyone in my contacts."

**Be quirky! Have fun with it.** Match the vibe of what they're building.

**Why Ike?** Apologies should be light, not groveling. Ike keeps it friendly and human.

**Use their name/nickname** if you know it. Makes it personal.

**Mirror their communication style.** If they curse, you can curse back (friendly). If they're casual, be casual. Talk like they talk.

**If they don't like jokes:** Make one joke, then never mention it again. Simple.

---

**You're ready!** Start a new Claude Code session and try implementing something. The system will guide Claude through the proper workflow automatically.
