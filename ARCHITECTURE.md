# Architecture

## Overview

The SDLC Wizard is a documentation-first approach to enforcing SDLC practices in Claude Code projects.

```
┌─────────────────────────────────────────────────────────────┐
│                     SDLC Wizard Repo                        │
├─────────────────────────────────────────────────────────────┤
│  CLAUDE_CODE_SDLC_WIZARD.md  ← Main wizard document        │
│  .claude/                     ← Hooks, skills, config       │
│  .github/workflows/           ← Auto-update automation      │
│  .github/prompts/             ← Claude analysis prompts     │
│  tests/                       ← Test scripts and fixtures   │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ User copies wizard to their repo
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     User's Project                          │
├─────────────────────────────────────────────────────────────┤
│  .claude/settings.json   ← Hook configuration               │
│  .claude/hooks/          ← SDLC enforcement scripts         │
│  .claude/skills/         ← SDLC/Testing guidance            │
│  CLAUDE.md               ← Project-specific instructions    │
│  SDLC.md                 ← SDLC configuration               │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. The Wizard Document

**File**: `CLAUDE_CODE_SDLC_WIZARD.md`

The main document that users copy to their repos. Contains:
- SDLC philosophy
- Installation instructions
- Hook/skill templates
- Usage guidelines

### 2. Hooks System

**Location**: `.claude/hooks/`

| Hook | Trigger | Purpose |
|------|---------|---------|
| `sdlc-prompt-check.sh` | UserPromptSubmit | SDLC baseline on every prompt |
| `tdd-pretool-check.sh` | PreToolUse (Write/Edit) | TDD reminder before code changes |

### 3. Skills System

**Location**: `.claude/skills/`

| Skill | Invocation | Purpose |
|-------|------------|---------|
| `/sdlc` | User invokes | Full SDLC workflow guidance |
| `/testing` | User invokes | TDD and testing philosophy |

### 4. Auto-Update System

**Location**: `.github/workflows/`

```
daily-update.yml
       │
       ├─→ Fetch latest Claude Code release
       │
       ├─→ Compare with last-checked-version.txt
       │
       ├─→ If new: Analyze with Claude
       │         │
       │         └─→ Output: { relevance, summary, impact }
       │
       └─→ Create PR (all updates, relevance shown in title)
```

## Data Flow

### Update Check Flow

```
GitHub Scheduled Trigger (9 AM UTC)
         │
         ▼
┌─────────────────────┐
│  Read last version  │
│  from state file    │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  Fetch latest from  │
│  claude-code repo   │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  Compare versions   │
│  Same? → Exit       │
│  Different? → ↓     │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  Analyze release    │
│  with Claude        │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  Parse response     │
│  (relevance level)  │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  Create PR          │
│  (relevance in      │
│   title)            │
└─────────────────────┘
```

### Hook Execution Flow

```
User types message
         │
         ▼
┌─────────────────────┐
│  UserPromptSubmit   │
│  hook fires         │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  sdlc-prompt-check  │
│  adds SDLC baseline │
└─────────────────────┘
         │
         ▼
Claude processes with SDLC context
         │
         ▼
┌─────────────────────┐
│  Claude wants to    │
│  Write/Edit file    │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  PreToolUse hook    │
│  fires              │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  tdd-pretool-check  │
│  adds TDD reminder  │
│  (if workflow file) │
└─────────────────────┘
         │
         ▼
Write/Edit proceeds
```

## File Structure

```
sdlc-wizard/
├── CLAUDE_CODE_SDLC_WIZARD.md    # Main wizard document
├── CLAUDE.md                      # This repo's instructions
├── SDLC.md                        # This repo's SDLC config
├── TESTING.md                     # Testing strategy
├── ARCHITECTURE.md                # This file
├── CI_CD.md                       # CI/CD documentation
├── CONTRIBUTING.md                # Contributor guide
├── README.md                      # Project introduction
├── CHANGELOG.md                   # Version history
│
├── plans/
│   └── AUTO_SELF_UPDATE.md        # Auto-update roadmap & design
│
├── .claude/
│   ├── settings.json              # Hook configuration
│   ├── settings.local.json        # Local permissions
│   ├── hooks/
│   │   ├── sdlc-prompt-check.sh   # SDLC baseline hook
│   │   └── tdd-pretool-check.sh   # TDD enforcement hook
│   └── skills/
│       ├── sdlc/SKILL.md          # SDLC workflow skill
│       └── testing/SKILL.md       # Testing skill
│
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                 # Validation & tests
│   │   ├── ci-autofix.yml         # Auto-fix loop (CI + review)
│   │   ├── daily-update.yml       # Auto-update check
│   │   ├── weekly-community.yml   # Community scan
│   │   ├── monthly-research.yml   # Deep research & trends
│   │   └── pr-review.yml          # AI code review
│   ├── prompts/
│   │   ├── analyze-release.md     # Release analysis prompt
│   │   └── analyze-community.md   # Community scan prompt
│   ├── last-checked-version.txt   # Version state
│   └── last-community-scan.txt    # Community scan state
│
└── tests/
    ├── test-version-logic.sh      # Version comparison tests
    ├── test-analysis-schema.sh    # Schema validation tests
    ├── test-workflow-triggers.sh   # Workflow trigger tests
    ├── test-cusum.sh              # CUSUM drift detection tests
    ├── test-stats.sh              # Statistical functions tests
    ├── test-hooks.sh              # Hook script tests
    ├── test-compliance.sh         # Compliance checker tests
    ├── test-sdp-calculation.sh    # SDP scoring tests
    ├── test-external-benchmark.sh # External benchmark tests
    ├── test-evaluate-bugs.sh      # Evaluate bug regression tests
    ├── test-score-analytics.sh    # Score analytics tests
    ├── fixtures/
    │   └── releases/              # Golden test fixtures
    └── e2e/
        ├── evaluate.sh            # AI-powered SDLC scoring
        ├── check-compliance.sh    # Pattern-based compliance
        ├── run-simulation.sh      # Main E2E runner
        ├── run-tier2-evaluation.sh # 5-trial statistical evaluation
        ├── cusum.sh               # CUSUM drift detection
        ├── pairwise-compare.sh    # Pairwise tiebreaker
        ├── score-analytics.sh     # Score history analytics
        ├── lib/
        │   ├── stats.sh           # 95% CI, t-distribution
        │   ├── json-utils.sh      # JSON extraction
        │   ├── eval-criteria.sh   # Per-criterion prompts (v3)
        │   ├── eval-validation.sh # Schema/bounds validation
        │   ├── deterministic-checks.sh # Grep-based scoring
        │   ├── scenario-selector.sh    # Scenario auto-discovery
        │   ├── external-benchmark.sh   # Benchmark fetcher
        │   └── sdp-score.sh       # SDP calculation
        ├── scenarios/             # 13 test scenarios
        ├── golden-outputs/        # Verified expected scores
        └── fixtures/test-repo/    # Template for simulations
```
