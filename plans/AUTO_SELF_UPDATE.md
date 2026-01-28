# Auto Self-Update Plan

> Status: IMPLEMENTED - See `.github/workflows/`

## Overview

A self-evolving system that keeps the wizard in sync with Claude Code updates and community best practices through automated research and human-approved updates.

## What's Implemented

### Daily Update Check (`.github/workflows/daily-update.yml`)
- **Trigger:** Daily at 9 AM UTC + manual dispatch
- **Checks:** Claude Code GitHub releases
- **Action:** Creates PR for ALL updates (relevance shown in title)
- **Change:** Now creates PR for all updates, not just HIGH/MEDIUM

### Weekly Community Scan (`.github/workflows/weekly-community.yml`)
- **Trigger:** Sundays at 9 AM UTC + manual dispatch
- **Checks:** Reddit, HN, dev blogs, official channels
- **Action:** Creates digest issue for notable findings

### Monthly Research Deep Dive (`.github/workflows/monthly-research.yml`)
- **Trigger:** 1st of month at 9 AM UTC + manual dispatch
- **Checks:** Academic papers, major announcements, deep community analysis
- **Action:** Creates issue with trend report and recommendations

### PR Code Review (`.github/workflows/pr-review.yml`)
- **Trigger:** All PRs
- **Action:** AI code review using GitHub MCP tools
- **Tools:** Proper review workflow (pending review → comments → submit)

### CI with E2E Evaluation (`.github/workflows/ci.yml`)
- **Trigger:** All PRs and pushes to main
- **Tests:** YAML validation, shell checks, state files, unit tests
- **E2E:** Full SDLC evaluation for bot/owner PRs (score 0-10, threshold 7.0)

## Summary of Workflows

| Trigger | Workflow | What It Does |
|---------|----------|--------------|
| Daily 9AM | daily-update.yml | Check releases → Always PR |
| Sundays | weekly-community.yml | Scan community → Issue |
| 1st of month | monthly-research.yml | Deep research → Issue |
| On PR | ci.yml | Run tests + E2E eval |
| On PR | pr-review.yml | AI code review |

## Who Gets What on PR

| Source | Tests | Review | E2E Eval |
|--------|-------|--------|----------|
| Bot | Yes | Yes | Yes |
| Owner | Yes | Yes | Yes |
| External | Yes | Yes | No |

## Key Design Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Official sources | Daily | Releases every 1-2 days, need timely updates |
| Community sources | Weekly | Less urgent, more noise, digest format |
| Deep research | Monthly | Papers/trends don't change daily |
| State storage | Files in repo | Simple, transparent, version-controlled |
| Analysis | Claude API | Nuanced understanding of wizard philosophy |
| PR threshold | All updates | Human decides relevance, not automation |
| E2E threshold | 7.0/10 | Balance between strictness and practicality |
| Default stance | Don't add | Only suggest if genuinely needed |

## Files Structure

```
.github/
├── workflows/
│   ├── daily-update.yml      # Official release monitoring
│   ├── weekly-community.yml  # Community discussion scanning
│   ├── monthly-research.yml  # Deep research and trends
│   ├── ci.yml                # Tests + E2E evaluation
│   └── pr-review.yml         # AI code review
├── prompts/
│   ├── analyze-release.md    # Claude prompt for release analysis
│   └── analyze-community.md  # Claude prompt for community scan
├── last-checked-version.txt  # Last processed Claude Code version
└── last-community-scan.txt   # Last community scan date

tests/
└── e2e/
    ├── fixtures/             # Sample projects for testing
    │   ├── test-repo/        # Basic JS
    │   ├── nextjs-typescript/# Next.js + TS + Prisma
    │   ├── python-fastapi/   # FastAPI + LangChain
    │   ├── mern-stack/       # MongoDB + Express + React + Node
    │   ├── go-api/           # Go + PostgreSQL
    │   └── legacy-messy/     # Intentionally bad code
    ├── scenarios/            # Test scenarios
    │   ├── add-feature.md
    │   ├── fix-bug.md
    │   └── refactor.md
    ├── run-simulation.sh     # Full E2E test runner
    ├── evaluate.sh           # AI-powered scoring (0-10)
    └── check-compliance.sh   # Pattern-based checks
```

## E2E Evaluation Flow

```
1. Pick scenario (add-feature, fix-bug, refactor)
2. Set up fixture (nextjs-typescript, python-fastapi, etc.)
3. Run Claude with scenario task
4. AI evaluates output against SDLC criteria:
   - TodoWrite used? (1 point)
   - Confidence stated? (1 point)
   - Plan mode? (2 points)
   - TDD RED? (2 points)
   - TDD GREEN? (2 points)
   - Self-review? (1 point)
   - Clean code? (1 point)
5. Score 0-10, pass if >= 7.0
```

## Required Secrets

- `ANTHROPIC_API_KEY` - for Claude analysis in workflows
- `GITHUB_TOKEN` - for PR/issue creation (automatic)

## Philosophy Preserved

- KISS - minimal files, simple flow
- Human-in-the-loop - PRs/issues require review, you always decide
- Wizard philosophy - baked into analysis prompts
- Use official when available - prompts check for plugin replacements
- Self-evolving - system improves itself through research and feedback
