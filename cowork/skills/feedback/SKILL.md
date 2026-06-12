---
name: feedback
description: Submit feedback, bug reports, feature requests, or share SDLC patterns you've discovered. Privacy-first — always asks before scanning.
argument-hint: [optional: bug | feature | pattern | improvement]
effort: medium
---
# Feedback — Community Contribution Loop

## Task
$ARGUMENTS

## Purpose

Help users contribute back to the SDLC wizard: bug reports, feature requests, pattern sharing, and SDLC improvements. Privacy-first — never scan without explicit permission.

## Privacy & Permission (MANDATORY)

**NEVER scan the user's repo without explicit consent.** Always ask first:

> "I can scan your SDLC setup to identify what you've customized vs wizard defaults. This helps me create a more specific report. May I scan? (Only file names and SDLC config are read — no source code, secrets, or business logic.)"

**What IS scanned (with permission):**
- SDLC.md, TESTING.md, CLAUDE.md structure (not content details)
- Hook file names and which hooks are active
- Skill names and which skills exist
- .claude/settings.json hook configuration (not allowedTools or secrets)

**What is NEVER scanned:**
- Source code files
- .env files, secrets, credentials
- Business logic or proprietary code
- Git history or commit messages

## Feedback Types

### Bug Report
1. Ask user to describe the issue
2. With permission, check which wizard version is installed (`SDLC.md` metadata)
3. Check if hooks are properly configured
4. Create a GitHub issue with reproduction steps

### Feature Request
1. Ask user what they want
2. With permission, check if a similar capability already exists in their setup
3. Create a GitHub issue with the request and context

### Pattern Sharing
1. Ask user what pattern they've discovered (custom hook, modified philosophy, test approach)
2. With permission, diff their SDLC setup against wizard defaults to identify customizations
3. Ask: "Which of these customizations worked well for you?"
4. Create a GitHub issue describing the pattern and evidence it works

### SDLC Improvement
1. Ask what could be better about the SDLC workflow
2. With permission, check which SDLC steps they use most/least
3. Create a GitHub issue with the improvement suggestion

## Creating the Issue

Use `gh issue create` on the wizard repo:

```bash
gh issue create \
  --repo BaseInfinity/claude-sdlc-wizard \
  --title "[feedback-type]: Brief description" \
  --body "$(cat <<'EOF'
## Feedback Type
bug / feature / pattern / improvement

## Description
[User's description]

## Context
- Wizard version: [from SDLC.md metadata]
- Setup type: [detected stack if permission granted]

## Evidence (if pattern sharing)
[What the user customized and why it worked]

---
Submitted via `/feedback` skill
EOF
)"
```

## Rules

- **Privacy first** — always ask before scanning anything
- **Opt-in only** — if user declines scan, still create the issue with whatever they tell you manually
- **No source code** — never include source code snippets in issues
- **Be specific** — vague issues waste maintainer time. Ask clarifying questions
- **Check for duplicates** — `gh issue list --repo BaseInfinity/claude-sdlc-wizard --search "keywords"` before creating
