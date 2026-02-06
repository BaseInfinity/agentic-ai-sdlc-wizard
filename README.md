# Claude Code SDLC Wizard

A **self-evolving SDLC enforcement system for AI coding agents**. Makes Claude plan before coding, test before shipping, and ask when uncertain. Measures itself getting better over time.

## What This Actually Is

Five layers working together:

```
Layer 5: SELF-IMPROVEMENT
  Daily/weekly/monthly workflows detect changes, test them
  statistically, create PRs. Baselines evolve organically.

Layer 4: STATISTICAL VALIDATION
  E2E scoring with 95% CI (5 trials, t-distribution).
  SDP normalizes for model quality. CUSUM catches drift.

Layer 3: SCORING ENGINE
  7 criteria, 10/11 points. Claude evaluates Claude.
  Before/after wizard A/B comparison in CI.

Layer 2: ENFORCEMENT
  Hooks fire every interaction (~100 tokens).
  PreToolUse blocks source edits without tests.

Layer 1: PHILOSOPHY
  The wizard document. KISS. TDD. Confidence levels.
  Copy it, run setup, get a bespoke SDLC.
```

## Why Someone Uses This

You want Claude Code to follow engineering discipline automatically:
- **Plan before coding** (not guess-and-check)
- **Write tests first** (TDD enforced via hooks)
- **State confidence** (LOW = ask user, don't guess)
- **Track work visibly** (TaskCreate)
- **Self-review before presenting**

The wizard auto-detects your stack (package.json, test framework, deployment targets) and generates bespoke hooks + skills + docs.

## What's Novel

| Innovation | Status |
|---|---|
| E2E scoring of AI agent SDLC behavior in CI | Nobody else does this |
| Before/after wizard A/B testing in CI | Nobody else does this |
| SDP: normalizing scores against external benchmarks | Nobody else does this |
| Robustness ratio (SDLC resilience vs model quality) | Nobody else does this |
| CUSUM drift detection for AI behavior | Borrowed from manufacturing QC |
| Pre-tool hooks enforcing TDD on AI agents | Guardrails exist for safety, not discipline |

**What exists elsewhere:** LLM eval frameworks (Promptfoo, DeepEval), code quality (SonarQube), LLM monitoring (Arize, Langfuse), AI benchmarks (SWE-bench). **The unique value = the integration into a self-improving loop.**

## How It Works

**Think Iron Man:** Jarvis is nothing without Tony Stark. Tony Stark is still Tony Stark. But together? They make Iron Man. This SDLC is your suit - you build it over time, improve it for your needs, and it makes you both better.

```
WIZARD FILE (CLAUDE_CODE_SDLC_WIZARD.md)
  - Setup guide, used once
  - Lives on GitHub, fetched when needed
        |
        | generates
        v
GENERATED FILES (in your repo)
  - .claude/hooks/*.sh
  - .claude/skills/*/SKILL.md
  - .claude/settings.json
  - CLAUDE.md, SDLC.md, TESTING.md, ARCHITECTURE.md
        |
        | validated by
        v
CI/CD PIPELINE
  - E2E: simulate SDLC task -> score 0-10
  - Before/after: main vs PR wizard
  - Statistical: 5x trials, 95% CI
  - Model-aware: SDP adjusts for external conditions
```

## Using It

**Copy-paste:** Download `CLAUDE_CODE_SDLC_WIZARD.md` to your project and follow setup instructions inside.

**Raw URL:** Point Claude to:
```
https://raw.githubusercontent.com/BaseInfinity/sdlc-wizard/main/CLAUDE_CODE_SDLC_WIZARD.md
```

**Check for updates:** Ask Claude "Check if the SDLC wizard has updates" - Claude reads [CHANGELOG.md](CHANGELOG.md), shows what's new, and offers to apply changes (opt-in each).

## Self-Evolving System

| Cadence | Source | Action |
|---------|--------|--------|
| Daily | Claude Code releases | PR with analysis + E2E test |
| Weekly | Community (Reddit, HN) | Issue digest |
| Monthly | Deep research, papers | Trend report |

Every update: regression tested -> AI reviewed -> human approved.

## E2E Scoring

Like evaluating scientific method adherence - we measure **process compliance**:

| Criterion | Points | Type |
|-----------|--------|------|
| TodoWrite/TaskCreate | 1 | Deterministic |
| Confidence stated | 1 | Deterministic |
| Plan mode | 2 | AI-judge |
| TDD RED | 2 | Deterministic |
| TDD GREEN | 2 | Deterministic |
| Self-review | 1 | AI-judge |
| Clean code | 1 | AI-judge |

60% deterministic + 40% AI-judged. 5 trials handle variance.

## Model-Adjusted Scoring (SDP)

| Metric | Meaning |
|--------|---------|
| **Raw** | Actual score (Layer 2: SDLC compliance) |
| **SDP** | Adjusted for model conditions |
| **Robustness** | How well SDLC holds up vs model changes |

- **Robustness < 1.0** = SDLC is resilient (good!)
- **Robustness > 1.0** = SDLC is sensitive (investigate)

## Tests Are The Building Blocks

Tests aren't just validation - they're the foundation everything else builds on.

- **Tests >= App Code** - Critique tests as hard (or harder) than implementation
- **Tests prove correctness** - Without them, you're just hoping
- **Tests enable fearless change** - Refactor confidently

## Official Plugin Integration

| Plugin | Purpose | Scope |
|--------|---------|-------|
| `claude-md-management` | **Required** - CLAUDE.md maintenance | CLAUDE.md only |
| `claude-code-setup` | Recommends automations | Recommendations |
| `code-review` | PR review (optional) | PRs only |

## Contributing

PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for evaluation methodology and testing.
