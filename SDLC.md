# SDLC Configuration

## Wizard Version Tracking

| Property | Value |
|----------|-------|
| Wizard Version | 1.0.0 |
| Last Updated | 2024-01-26 |
| Claude Code Baseline | v2.1.15+ |

## SDLC Enforcement

This repository uses the SDLC Wizard to enforce:

### 1. Planning Before Coding
- Complex tasks require `EnterPlanMode`
- Multi-step tasks use `TaskCreate`
- Confidence levels stated before implementation

### 2. TDD Approach
- Write failing tests first
- Implement to pass tests
- Refactor while keeping green

### 3. Self-Review
- Review changes before presenting
- Verify tests pass
- Check for obvious issues

## Hooks Installed

| Hook | Trigger | Purpose |
|------|---------|---------|
| `sdlc-prompt-check.sh` | Every prompt | SDLC baseline reminder |
| `tdd-pretool-check.sh` | Before Write/Edit | TDD reminder for workflows |

## Skills Available

| Skill | Invocation | Purpose |
|-------|------------|---------|
| SDLC | `/sdlc` | Full SDLC workflow guidance |
| Testing | `/testing` | TDD and testing strategy |

## Compliance Verification

To verify SDLC compliance:

1. **Manual check**: Start new Claude session, observe hook output
2. **E2E test**: Run `./tests/e2e/run-simulation.sh`
3. **PR review**: All PRs trigger AI code review workflow

## Updating the Wizard

When Claude Code releases new features:

1. Daily workflow checks for updates
2. HIGH/MEDIUM relevance creates PR
3. Review and merge if valuable
4. Update version tracking here

## Configuration Files

```
.claude/
├── settings.json           # Hook configuration
├── hooks/
│   ├── sdlc-prompt-check.sh    # SDLC baseline
│   └── tdd-pretool-check.sh    # TDD enforcement
└── skills/
    ├── sdlc/SKILL.md           # SDLC workflow
    └── testing/SKILL.md        # Testing strategy
```
