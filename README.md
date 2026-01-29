# Claude Code SDLC Wizard

An organic **Secure Development Lifecycle** framework for AI coding agents. Makes Claude plan before coding, test before shipping, and ask when uncertain.

## What It Does

- Claude states confidence levels (HIGH/MEDIUM/LOW) before implementing
- LOW confidence = Claude asks you instead of guessing wrong
- TDD enforced: failing test first, then implementation
- Self-review before presenting work
- Integrates with official plugins (`claude-md-management`, `code-review`, etc.)

## Why It Works

Human engineering practices (planning, TDD, confidence checks) happen to be exactly what AI agents need to stay on track. You set it up, Claude follows it.

**Think Iron Man:** Jarvis is nothing without Tony Stark. Tony Stark is still Tony Stark. But together? They make Iron Man. This SDLC is your suit - you build it over time, improve it for your needs, and it makes you both better.

## Organic & Dynamic

**This isn't a static rulebook.** The SDLC evolves with your project AND with Claude Code's capabilities:

- **Bespoke fit** - Starts generic, becomes tailored to YOUR codebase through use
- **Built-in improvement loop** - Friction is feedback; Claude proposes adjustments, you approve
- **Adapts to Claude Code** - As Claude Code adds features, the SDLC leverages them (or removes redundant custom solutions)
- **Token-efficient** - Uses Claude Code's native tooling (hooks, skills, plugins) to enforce the process with minimal context overhead
- **Checks and balances** - Confidence levels, self-review, and TDD gates catch problems before they compound

**The goal:** A living system that gets better the more you use it - not documentation that rots.

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│ WIZARD FILE (CLAUDE_CODE_SDLC_WIZARD.md)                    │
│ - NOT in your repo                                          │
│ - Setup guide only - used once during initial setup         │
│ - Lives on GitHub, fetched when needed                      │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ generates
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ GENERATED FILES (in your repo, committed to git)            │
│ - .claude/hooks/*.sh                                        │
│ - .claude/skills/*/SKILL.md                                 │
│ - .claude/settings.json                                     │
│ - CLAUDE.md, SDLC.md, TESTING.md, ARCHITECTURE.md          │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ updates compare against
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ UPDATES (from GitHub)                                       │
│ - Fetch CHANGELOG.md from GitHub                           │
│ - Compare against your generated files                     │
│ - Propose changes one by one (opt-in)                      │
│ - Preserve your customizations                             │
└─────────────────────────────────────────────────────────────┘
```

**The wizard is a setup guide, not a file you keep.** Run it once to generate your SDLC files, then check for updates periodically.

## Tests Are The Building Blocks

Tests aren't just validation - they're the foundation everything else builds on.

- **Tests >= App Code** - Critique tests as hard (or harder) than implementation
- **Tests prove correctness** - Without them, you're just hoping it works
- **Tests enable fearless change** - Refactor confidently because tests catch regressions

## Using It

**Copy-paste:** Download `CLAUDE_CODE_SDLC_WIZARD.md` to your project and follow setup instructions inside.

**Raw URL:** Point Claude to:
```
https://raw.githubusercontent.com/BaseInfinity/sdlc-wizard/main/CLAUDE_CODE_SDLC_WIZARD.md
```

**Check for updates:** Ask Claude "Check if the SDLC wizard has updates" - Claude reads [CHANGELOG.md](CHANGELOG.md), shows what's new, and offers to apply changes (opt-in each)

## Self-Evolving System

The wizard actively improves itself through automated research and human-approved updates:

| Cadence | Source | Action |
|---------|--------|--------|
| Daily | Claude Code releases | PR with analysis |
| Weekly | Community (Reddit, HN) | Issue digest |
| Monthly | Deep research, papers | Trend report |

Every update goes through:
1. **Regression tests** - Does new Claude version still follow SDLC?
2. **AI code review** - Quality check like a senior engineer
3. **Human approval** - You always decide what merges

### Why This Matters

AI tools evolve fast. Yesterday's best practice is today's anti-pattern.
The wizard watches official releases AND community sentiment so you don't have to.
But it never auto-merges - you stay in control.

### What Gets Checked

| Trigger | Tests | Review | E2E Eval |
|---------|-------|--------|----------|
| Bot PRs | Yes | Yes | Yes |
| Owner PRs | Yes | Yes | Yes |
| External PRs | Yes | Yes | No |

**Why PRs even for solo devs?** Not required, but good practice. PRs give you: AI code review via subagent, CI gates before merge, clean history, easy rollback. You approve your own PRs - the value is the structured workflow, not the approval ceremony.

### How E2E Scoring Works

Like evaluating scientific method adherence - we measure **process compliance**, not outcome quality:

| SDLC Step | Evidence We Look For |
|-----------|---------------------|
| Plan | Stated approach BEFORE coding? |
| TDD RED | Test written BEFORE implementation? |
| TDD GREEN | Test passes after? |
| Self-review | Checked own work? |

Scores are based on consistent criteria. Conservative baselines that rise as we improve.

See `.github/workflows/` and `tests/e2e/` for implementation details.

## Official Plugin Integration

The wizard integrates with Anthropic's official plugins:

| Plugin | Purpose | Scope |
|--------|---------|-------|
| `claude-md-management` | **Required** - CLAUDE.md maintenance | CLAUDE.md only |
| `claude-code-setup` | Recommends automations | Recommendations |
| `code-review` | PR review (optional) | PRs only |

**What the wizard still handles:** TDD enforcement, confidence levels, planning mode, feature docs, TESTING.md, ARCHITECTURE.md, hooks, skills - the full SDLC workflow.

## Contributing

PRs welcome. Good contributions: philosophical insights, generalizable patterns, simplifications. Keep it generic - Claude figures out the tech specifics.
