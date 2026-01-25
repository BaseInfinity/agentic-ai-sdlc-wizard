# Changelog

All notable changes to the SDLC Wizard.

> **Note:** This changelog is for humans to read. Don't manually apply these changes - just run the wizard ("Check for SDLC wizard updates") and it handles everything automatically.

## [1.3.0] - 2026-01-24

### Added
- Idempotent wizard - safe to run on any existing setup
- Setup tracking comments in SDLC.md (version, completed steps, preferences)
- Wizard step registry for tracking what's been done
- Backwards compatibility for old wizard users

### Changed
- "Staying Updated" section rewritten for idempotent approach
- Update flow now checks plugins and questions, not just files
- One unified flow for setup AND updates (no separate paths)

### How It Works
The wizard now tracks completed steps in SDLC.md metadata comments. Old users running "check for updates" will be walked through only the new steps they haven't done yet.

## [1.2.0] - 2026-01-24

### Added
- Official plugin integration (claude-md-management, code-review, claude-code-setup)
- Step 0.1-0.4: Plugin setup before auto-scan
- "Leverage Official Tools" principle in Philosophy section
- Post-mortem learnings table (what goes where)
- Testing skill "After Session" section for capturing learnings
- Clear update workflow in "Staying Updated" section

### Changed
- Step 0 restructured: plugins first, then SDLC setup, then auto-scan
- Stay Lightweight section now includes official plugin table
- Clarified plugin scope: claude-md-management = CLAUDE.md only

### Files Affected
- `.claude/skills/testing/SKILL.md` - Add "After Session" section
- `SDLC.md` - Consider adding version comment

## [1.1.0] - 2026-01-23

### Added
- Tasks system documentation (v2.1.16+)
- $ARGUMENTS skill parameter support (v2.1.19+)
- Ike the cat easter egg (8 pounds, Fancy Feast enthusiast)
- Iron Man analogy for human+AI partnership

### Changed
- Test review preference: user chooses oversight level
- Shared environment awareness (not everyone runs isolated)

## [1.0.0] - 2026-01-20

### Added
- Initial SDLC Wizard release
- TDD enforcement hooks
- SDLC and Testing skills
- Confidence levels (HIGH/MEDIUM/LOW)
- Planning mode integration
- Self-review workflow
- Testing Diamond philosophy
- Mini-retro after tasks
