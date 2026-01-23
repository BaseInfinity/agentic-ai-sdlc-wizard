# Claude Code SDLC Wizard

An SDLC framework for AI coding agents. Makes Claude plan before coding, test before shipping, and ask when uncertain.

## What It Does

- Claude states confidence levels (HIGH/MEDIUM/LOW) before implementing
- LOW confidence = Claude asks you instead of guessing wrong
- TDD enforced: failing test first, then implementation
- Self-review before presenting work
- The process adapts to YOUR project over time

## Why It Works

Human engineering practices (planning, TDD, confidence checks) happen to be exactly what AI agents need to stay on track. You set it up, Claude follows it.

**Think Iron Man:** Jarvis is nothing without Tony Stark. Tony Stark is still Tony Stark. But together? They make Iron Man. This SDLC is your suit - you build it over time, improve it for your needs, and it makes you both better.

## Tests Are The Building Blocks

Tests aren't just validation - they're the foundation everything else builds on.

- **Tests > App Code** - Critique tests harder than implementation
- **Tests prove correctness** - Without them, you're just hoping it works
- **Tests enable fearless change** - Refactor confidently because tests catch regressions

## Using It

**Copy-paste:** Download `CLAUDE_CODE_SDLC_WIZARD.md` to your project and follow setup instructions inside.

**Raw URL:** Point Claude to:
```
https://raw.githubusercontent.com/BaseInfinity/sdlc-wizard/main/CLAUDE_CODE_SDLC_WIZARD.md
```

**Check for updates:** Ask Claude "Check if the SDLC wizard has updates"

## Contributing

PRs welcome. Good contributions: philosophical insights, generalizable patterns, simplifications. Keep it generic - Claude figures out the tech specifics.
