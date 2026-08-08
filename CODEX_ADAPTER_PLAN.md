# Codex SDLC Adapter Plan

## What This Is

A plan for `BaseInfinity/codex-sdlc-wizard` — an adapter that brings SDLC wizard enforcement to OpenAI's Codex CLI. Claude Code is the main product; this adapter translates our proven patterns to Codex's config format.

## Why

Users who use Codex CLI get zero SDLC enforcement today. This adapter gives them ~70% of what CC users get — same hook architecture, adapted to Codex's Bash-only tool model.

## Codex Capabilities (Verified from source: `openai/codex` codex-rs/ 2026-04-04)

**Critical finding from source code audit:** Codex's hook engine supports the same hooks.json format as Claude Code, but the **runtime only invokes PreToolUse/PostToolUse for Bash commands**. The `tool_name` is hardcoded to `"Bash"` in `hook_runtime.rs:131`. While the matcher engine supports regex on any tool name, no other tools are wired through PreToolUse. This means `Write|Edit` matchers will never fire.

**Codex tool model:** Unlike Claude Code (which has separate Write, Edit, Read tools), Codex routes ALL operations through shell commands. File edits use `apply_patch`, and the hook payload contains `tool_input.command` (the shell command string), NOT `tool_input.file_path`.

| Feature | What It Does | Enforcement Level |
|---------|-------------|-------------------|
| `AGENTS.md` | Instructions file (like CLAUDE.md) | Guidance only |
| `.codex/hooks.json` | Lifecycle hooks (5 events, same format as CC) | Can block Bash commands |
| `.codex/config.toml` | Settings (sandbox, model, approval policy) | Hard enforcement (sandbox) |
| PreToolUse | Fires for Bash tool ONLY (`tool_name: "Bash"`, `tool_input.command`) | Hard enforcement |
| UserPromptSubmit | Fires on every user prompt (no tool_name) | Soft enforcement (context injection) |
| SessionStart | Fires on session init | Soft enforcement (context injection) |

**Not available for repo-local enforcement:**
- `requirements.toml` — loaded from managed cloud/admin/system locations, not repo-local files

### hooks.json Format (verified from `codex-rs/hooks/src/engine/config.rs`)

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^Bash$",
        "hooks": [
          { "type": "command", "command": "path/to/script.sh" }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "path/to/script.sh" }
        ]
      }
    ]
  }
}
```

This is the SAME format as Claude Code's `settings.json` hooks section. Matchers are only meaningful for PreToolUse and PostToolUse (regex on tool_name). UserPromptSubmit and SessionStart ignore matchers.

### Blocking Protocol (verified from `codex-rs/hooks/src/engine/output_parser.rs`)

**PreToolUse** — three supported block paths:

1. **Legacy (recommended for simplicity)** — exit 0, stdout JSON:
```json
{"decision": "block", "reason": "TDD CHECK: Run tests before committing."}
```

2. **New hookSpecificOutput path** — exit 0, stdout JSON:
```json
{"hookSpecificOutput": {"permissionDecision": "deny", "permissionDecisionReason": "Run tests first."}}
```

3. **Exit code 2** — stderr plain text also blocks (reason = stderr content).

Empty or no output = allow. `decision: "approve"` returns unsupported error. We use path 1 (legacy) — simplest, well-tested.

**UserPromptSubmit** — output plain text on stdout = `additionalContext` (non-blocking, injected as developer message). Or JSON `{"decision": "block", "reason": "..."}` to block the prompt.

**SessionStart** — output JSON on stdout:
```json
{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "SDLC baseline loaded."}}
```

### Enforcement Strategy

Since PreToolUse only fires for Bash commands, our enforcement is:

| SDLC Goal | CC Wizard (has Write/Edit tools) | Codex Adapter (Bash only) |
|-----------|--------------------------------|---------------------------|
| TDD file-edit gate | PreToolUse blocks Write/Edit | **AGENTS.md guidance** (soft) + UserPromptSubmit reminder |
| git commit block | Context injection (reminder) | **PreToolUse blocks `git commit`** (HARD — stronger than CC!) |
| git push block | Context injection (reminder) | **PreToolUse blocks `git push`** (HARD — stronger than CC!) |
| SDLC baseline | UserPromptSubmit hook | **UserPromptSubmit hook** (same) |
| Session init | InstructionsLoaded | **SessionStart hook** (same concept) |

**Net: We lose the hard TDD file-edit gate but gain hard git commit/push blocking.** AGENTS.md compensates for the file-edit gap with strong guidance. Overall ~70% parity.

### What We Intentionally Scope Out for v1

| Hook/Feature | Why Not v1 |
|-------------|------------|
| **PostToolUse** | CC wizard doesn't use it either. Adds complexity without proven value |
| **Stop** | Could block session end, but git commit gate already catches. Overkill for v1 |

These are candidates for v2 if users request them. Less is more.

### What We CANNOT Enforce (different from CC)

- **TDD file-edit gate (hard)** — Codex has no Write/Edit tools; all edits go through Bash. We can't distinguish "editing src/app.js" from "running tests" in the command string reliably. AGENTS.md covers this with guidance
- **Skills system** — Codex has skills but different format (`.codex/agents/*.toml`). AGENTS.md covers this
- **Confidence levels** — No built-in tracking, guidance only via AGENTS.md
- Hooks require `codex_hooks = true` feature flag in config.toml
- **Windows** — Codex disables lifecycle hooks on Windows (`hooks/src/engine/mod.rs:83-91`)

### Dependencies

- `bash` (3.x+ on macOS, 4.x+ on Linux)
- `jq` — required for parsing hook input JSON in bash-guard.sh

## Repo Structure

```
BaseInfinity/codex-sdlc-wizard/
├── README.md                    # Install, usage, CC vs Codex comparison
├── AGENTS.md                    # SDLC instructions for Codex (TDD guidance)
├── .codex/
│   ├── config.toml              # Recommended settings (enables hooks)
│   ├── hooks.json               # SDLC enforcement hooks
│   └── hooks/
│       ├── sdlc-prompt-check.sh # UserPromptSubmit: SDLC baseline
│       ├── bash-guard.sh        # PreToolUse Bash: git commit/push gate
│       └── session-start.sh     # SessionStart: AGENTS.md check
├── install.sh                   # Non-destructive installer
├── UPSTREAM_VERSION             # Pinned sdlc-wizard version for sync tracking
├── .github/
│   └── workflows/
│       └── upstream-sync.yml    # Weekly check for sdlc-wizard updates
└── tests/
    └── test-adapter.sh          # Validates hook behavior
```

## File Specifications

### AGENTS.md

Translated from our SDLC wizard, adapted for Codex. Since we can't hard-block file edits, AGENTS.md carries the TDD enforcement:

```markdown
# SDLC Enforcement

## Before Every Task
1. Plan before coding — outline steps, state confidence (HIGH/MEDIUM/LOW)
2. LOW confidence? Research more or ASK USER
3. Write failing test FIRST (TDD RED), then implement (TDD GREEN)
4. ALL tests must pass before commit — no exceptions

## TDD Workflow (MANDATORY)
1. Write the test file FIRST — the test MUST FAIL initially
2. Run the test — confirm it fails (RED)
3. Write the minimum implementation to make the test pass
4. Run the test — confirm it passes (GREEN)
5. Only then: commit

## After Implementation
1. Self-review: read back your changes, check for bugs
2. Run full test suite — ALL tests must pass
3. Only then: commit and push

## Rules
- Delete legacy code — no backwards compatibility hacks
- Less is more — don't add what wasn't asked for
- Tests ARE code — treat test failures as bugs
- NEVER commit without running tests first
```

Keep concise — shorter = better model attention. Codex official limit is 32KiB (`project_doc_max_bytes`), but aim for under 2KB. This is a team heuristic, not an official recommendation.

### .codex/hooks.json

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".codex/hooks/sdlc-prompt-check.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "^Bash$",
        "hooks": [
          {
            "type": "command",
            "command": ".codex/hooks/bash-guard.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".codex/hooks/session-start.sh"
          }
        ]
      }
    ]
  }
}
```

### Hook Scripts

**sdlc-prompt-check.sh** — SDLC baseline on every prompt (non-blocking context injection):
```bash
#!/bin/bash
cat << 'EOF'
SDLC BASELINE:
1. Plan before coding — state confidence level
2. TDD: Write failing test FIRST, then implement
3. ALL tests must pass before commit
4. Self-review before presenting to user
EOF
```
Output is plain text → Codex treats it as `additionalContext` (developer message).

**bash-guard.sh** — Block git commit/push without tests:
```bash
#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -qE 'git\s+commit'; then
  echo '{"decision":"block","reason":"TDD CHECK: Did you run tests before committing? Run your full test suite first. ALL tests must pass."}'
  exit 0
fi

if echo "$COMMAND" | grep -qE 'git\s+push'; then
  echo '{"decision":"block","reason":"REVIEW CHECK: Did you self-review your changes and run all tests before pushing?"}'
  exit 0
fi
```
Hook input is JSON on stdin with `tool_input.command` containing the shell command string.

**session-start.sh** — Check AGENTS.md exists:
```bash
#!/bin/bash
if [ ! -f "AGENTS.md" ]; then
  cat << 'EOF'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"WARNING: No AGENTS.md found. SDLC enforcement requires AGENTS.md. Run install.sh to set up."}}
EOF
fi
```

### .codex/config.toml

```toml
[features]
codex_hooks = true
```

### install.sh

Non-destructive: backs up existing files, merges config.toml feature flag, never overwrites user config.

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing SDLC Harness for Codex CLI..."

# AGENTS.md — skip if exists
if [ ! -f "AGENTS.md" ]; then
  cp "$SCRIPT_DIR/AGENTS.md" .
  echo "Created AGENTS.md"
else
  echo "AGENTS.md already exists — skipping (review manually)"
fi

mkdir -p .codex/hooks

# config.toml — ensure codex_hooks = true, TOML-safe
if [ -f ".codex/config.toml" ]; then
  if grep -q 'codex_hooks\s*=\s*false' .codex/config.toml; then
    # Flip false to true
    sed -i.bak 's/codex_hooks\s*=\s*false/codex_hooks = true/' .codex/config.toml
    rm -f .codex/config.toml.bak
    echo "Set codex_hooks = true in existing config.toml"
  elif grep -q 'codex_hooks' .codex/config.toml; then
    echo "config.toml already has codex_hooks = true — skipping"
  elif grep -q '^\[features\]' .codex/config.toml; then
    # [features] table exists but no codex_hooks — append under it
    sed -i.bak '/^\[features\]/a\
codex_hooks = true' .codex/config.toml
    rm -f .codex/config.toml.bak
    echo "Added codex_hooks = true to existing [features] table"
  else
    # No [features] table at all — append new section
    printf '\n[features]\ncodex_hooks = true\n' >> .codex/config.toml
    echo "Added [features] codex_hooks = true to config.toml"
  fi
else
  cp "$SCRIPT_DIR/.codex/config.toml" .codex/
  echo "Created .codex/config.toml"
fi

# hooks.json — back up if exists, then install
if [ -f ".codex/hooks.json" ]; then
  cp .codex/hooks.json ".codex/hooks.json.bak.$(date +%s)"
  echo "Backed up existing hooks.json"
fi
cp "$SCRIPT_DIR/.codex/hooks.json" .codex/
echo "Installed .codex/hooks.json"

# Hook scripts — always overwrite (these are ours)
cp "$SCRIPT_DIR/.codex/hooks/"*.sh .codex/hooks/
chmod +x .codex/hooks/*.sh

echo ""
echo "SDLC Harness for Codex installed."
echo "Run 'codex' to start a session with SDLC enforcement."
```

## Test Plan

Tests validate BEHAVIOR against real Codex hook payloads, not just script existence:

### Hook behavior tests
1. **sdlc-prompt-check.sh outputs SDLC keywords** (TDD, confidence, test)
2. **bash-guard.sh blocks `git commit`** — feed `{"tool_input":{"command":"git commit -m 'test'"}}` on stdin, expect `decision:block` JSON on stdout
3. **bash-guard.sh blocks `git push`** — feed `{"tool_input":{"command":"git push origin main"}}`, expect `decision:block`
4. **bash-guard.sh allows other commands** — feed `{"tool_input":{"command":"npm test"}}`, expect no output
5. **bash-guard.sh allows git diff** — feed `{"tool_input":{"command":"git diff"}}`, expect no output
6. **session-start.sh warns when AGENTS.md missing** — run in dir without AGENTS.md, expect `additionalContext` JSON
7. **session-start.sh silent when AGENTS.md present** — run in dir with AGENTS.md, expect no output

### Payload format tests (verify against Codex source)
8. **bash-guard.sh reads `tool_input.command`** (NOT `tool_input.file_path` — that field doesn't exist in Codex PreToolUse)
9. **hooks.json PreToolUse matcher is `^Bash$`** (NOT `Write|Edit` — those tools don't exist in Codex runtime)
10. **hooks.json is valid JSON with correct event-keyed format**

### Config and install tests
11. **config.toml enables codex_hooks feature flag**
12. **install.sh doesn't overwrite existing AGENTS.md**
13. **install.sh merges codex_hooks into existing config.toml** (4 cases: false→true, already true, [features] exists, no [features])
14. **install.sh backs up existing hooks.json** (creates .bak file)
15. **AGENTS.md under 32KiB** (official Codex limit)

## CC vs Codex Comparison

| What | CC Wizard | Codex Adapter |
|------|-----------|---------------|
| hooks.json format | Same event-keyed structure | Same (verified from source) |
| TDD file-edit gate | PreToolUse blocks Write/Edit (HARD) | AGENTS.md guidance (SOFT — Codex has no Write/Edit tools) |
| git commit gate | Context injection (soft reminder) | **PreToolUse decision:block (HARD — stronger than CC!)** |
| git push gate | Context injection (soft reminder) | **PreToolUse decision:block (HARD — stronger than CC!)** |
| SDLC prompt reminder | UserPromptSubmit hook | UserPromptSubmit hook (same) |
| Session start check | InstructionsLoaded | SessionStart (same concept) |
| Skills system | .claude/skills/ SKILL.md | AGENTS.md (simpler but works) |
| Confidence enforcement | Hook + skill | AGENTS.md guidance only |
| Update notification | npm version check | Manual |
| Requires feature flag | No | Yes (codex_hooks = true) |
| Windows support | Yes | No (hooks disabled on Windows) |

## Source Code References

All claims verified against `openai/codex` commit as of 2026-04-04:

| File | What It Proves |
|------|---------------|
| `codex-rs/hooks/src/engine/config.rs` | hooks.json deserialization schema (HooksFile, HookEvents, MatcherGroup) |
| `codex-rs/hooks/src/engine/discovery.rs` | Hook file discovery, matcher validation |
| `codex-rs/hooks/src/engine/output_parser.rs` | Blocking protocol (decision:block, permissionDecision:deny, exit 2) |
| `codex-rs/core/src/hook_runtime.rs:131` | **PreToolUse hardcodes tool_name: "Bash"** — only Bash commands trigger hooks |
| `codex-rs/hooks/src/events/pre_tool_use.rs` | PreToolUse input schema (tool_input.command, NOT file_path) |
| `codex-rs/hooks/src/engine/mod.rs:83-91` | Lifecycle hooks disabled on Windows |

## Upstream Sync Architecture

The adapter is a **standalone repo** that translates sdlc-wizard patterns to Codex format. This matches how ESLint/Prettier adapters, Terraform providers, and Kubernetes staging repos work — separate repos with automated upstream awareness.

### Why Not Fork/Submodule

- **Fork**: Can't fork your own repo into the same account. Even if you could, every file is different (`.codex/` vs `.claude/`, `AGENTS.md` vs `CLAUDE.md`) — merges would be constant meaningless conflicts
- **Submodule**: The shared content needs *translation*, not wholesale inclusion. Users don't need sdlc-wizard installed to use the Codex adapter
- **Monorepo**: Different CI needs (testing against Codex CLI), different users, different release cadence

### How Sync Works

```
sdlc-wizard releases v1.26.0
        ↓
upstream-sync.yml (weekly cron) detects new version
        ↓
Opens GitHub issue: "Upstream sdlc-wizard v1.26.0 — review for Codex adaptation"
        ↓
Human/Codex reviews changes, translates what applies
        ↓
Updates UPSTREAM_VERSION to v1.26.0
```

### UPSTREAM_VERSION

Plain text file pinning which sdlc-wizard version this adapter is based on:
```
v1.25.0
```

### .github/workflows/upstream-sync.yml

```yaml
name: Upstream Sync Check
on:
  schedule:
    - cron: '0 9 * * 1'  # Weekly Monday 9am UTC
  workflow_dispatch:

jobs:
  check-upstream:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check for sdlc-wizard updates
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          LATEST=$(gh release view --repo BaseInfinity/claude-sdlc-wizard --json tagName -q .tagName 2>/dev/null || echo "unknown")
          CURRENT=$(cat UPSTREAM_VERSION 2>/dev/null || echo "none")

          if [ "$LATEST" = "unknown" ]; then
            echo "Could not fetch upstream version"
            exit 0
          fi

          if [ "$LATEST" != "$CURRENT" ]; then
            # Check if issue already exists
            EXISTING=$(gh issue list --search "Upstream sync: $LATEST" --json number -q '.[0].number' 2>/dev/null || echo "")
            if [ -z "$EXISTING" ]; then
              gh issue create \
                --title "Upstream sync: sdlc-wizard $LATEST" \
                --body "sdlc-wizard released **$LATEST** (adapter is based on **$CURRENT**).

          Review [release notes](https://github.com/BaseInfinity/claude-sdlc-wizard/releases/tag/$LATEST) and translate applicable changes to Codex format.

          After adapting, update \`UPSTREAM_VERSION\` to \`$LATEST\`." \
                --label "upstream-sync"
              echo "Created sync issue for $LATEST"
            else
              echo "Issue already exists: #$EXISTING"
            fi
          else
            echo "Already up to date: $CURRENT"
          fi
```

## Implementation Plan

1. **Claude** writes this plan (DONE)
2. **Codex** cross-reviews until CERTIFIED (DONE — 9/10, round 5)
3. **Claude** creates the GitHub repo `BaseInfinity/codex-sdlc-wizard` (DONE)
4. **Codex** implements from this plan (TDD: tests first, then code)
5. **Claude** reviews the implementation
6. **User** verifies and ships

## What Success Looks Like

A Codex CLI user runs `install.sh` in their repo and gets:
- SDLC reminders every prompt (UserPromptSubmit hook)
- git commit blocked until tests run (PreToolUse Bash hook — HARD block)
- git push blocked until self-review (PreToolUse Bash hook — HARD block)
- TDD guidance in AGENTS.md (soft enforcement — Codex has no file-edit tools to hook)
- Session start check for AGENTS.md
- Non-destructive install — merges into existing config, backs up existing hooks
- jq required as dependency
