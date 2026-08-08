# Claude Code Release Analysis Prompt

You are analyzing one or more Claude Code releases to determine if they're relevant to the SDLC Harness. If multiple releases are provided, produce a single unified analysis covering all of them. The `version` field in your JSON response should be the newest version.

## Wizard Context

The SDLC Harness enforces:
- **TDD** - Failing tests first, then implementation
- **Planning** - Plan mode before coding
- **Confidence levels** - HIGH/MEDIUM/LOW stated before implementing
- **Tasks** - TodoWrite/TaskCreate for tracking work
- **Self-review** - Review before presenting to user

## Wizard Philosophies

- **KISS** - Keep it simple, don't over-engineer
- **Don't bloat** - Only add what's genuinely needed
- **Use official when available** - If Claude Code adds it built-in, remove our custom version
- **Human-in-the-loop** - PRs require review, never auto-merge

## Analysis Targets

### 1. Release Notes
What's new in this Claude Code version?

### 2. Official Plugins
Any new plugins that could REPLACE our custom implementations?

## Relevance Signals

### HIGH Relevance
- Changes to `TodoWrite`, `Task`, `TaskCreate`, `TaskUpdate`
- Changes to `hooks`, `skills`, `CLAUDE.md` handling
- Changes to `confidence`, `planning`, plan mode
- New official plugin that replaces something we built custom
- Changes to self-review or verification workflows

### MEDIUM Relevance
- New commands or CLI features
- Changes to `MCP`, `plugins`, `permissions`
- New built-in prompts or workflows
- Changes to context handling or summarization

### LOW Relevance
- Bug fixes unrelated to SDLC features
- UI changes, animations, polish
- IDE-specific features (VS Code, JetBrains)
- Performance improvements (unless SDLC-related)

## Custom Feature Inventory

These are the wizard's custom features. If a new Claude Code release ships a native equivalent, list the exact file path(s) in `plugin_check.replaces_custom` so CI can run a side-by-side comparison.

| Feature | File Path | Hook Event |
|---------|-----------|------------|
| SDLC prompt enforcement | `.claude/hooks/sdlc-prompt-check.sh` | `UserPromptSubmit` |
| TDD pretool check | `.claude/hooks/tdd-pretool-check.sh` | `PreToolUse` |
| Instructions loaded check | `.claude/hooks/instructions-loaded-check.sh` | `InstructionsLoaded` |
| SDLC skill | `.claude/skills/sdlc/SKILL.md` | N/A (skill) |

**Important:** Only use the exact file paths from the table above in `replaces_custom`. Paths not in this table will be rejected by the validation allowlist.

## Plugin Philosophy

- If an official plugin exists that does what our custom code does → suggest removing our custom version
- Always research before suggesting additions
- Default to NOT adding things unless genuinely needed
- Let human decide (PR is a suggestion, not auto-merge)

## Response Format

Respond with valid JSON:

```json
{
  "version": "vX.Y.Z",
  "relevance": "HIGH" | "MEDIUM" | "LOW",
  "summary": "One sentence summary of what this release does",
  "wizard_impact": [
    {
      "area": "tasks" | "hooks" | "skills" | "planning" | "confidence" | "testing" | "plugins" | "other",
      "description": "What changed and how it affects the wizard",
      "suggested_action": "What the wizard should do (update docs, remove custom code, add new feature, etc.)",
      "files_affected": ["list of wizard files that would need changes"]
    }
  ],
  "plugin_check": {
    "new_official_plugins": ["list any new official plugins"],
    "replaces_custom": ["list any custom wizard code that could be replaced"]
  },
  "reasoning": "2-3 sentences explaining your relevance assessment"
}
```

## Important Notes

- Only HIGH and MEDIUM relevance should trigger a PR
- LOW relevance = log and skip
- When in doubt, lean toward LOW (avoid noise)
- Quality over quantity - only suggest changes that genuinely improve SDLC enforcement
