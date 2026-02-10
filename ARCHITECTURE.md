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
       ├─→ If HIGH/MEDIUM: Create PR
       │
       └─→ If LOW: Direct commit (no PR needed)
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
    ┌────┴────┐
    ▼         ▼
HIGH/MED     LOW
    │         │
    ▼         ▼
Create PR   Commit directly
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
├── README.md                      # Project introduction
├── CHANGELOG.md                   # Version history
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
    ├── fixtures/
    │   └── releases/              # Golden test fixtures
    └── e2e/
        ├── fixtures/test-repo/    # Template for simulations
        ├── scenarios/             # Test scenario definitions
        ├── run-simulation.sh      # Main E2E runner
        └── check-compliance.sh    # SDLC compliance checker
```
