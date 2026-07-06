# SDLC Wizard — Cowork Plugin

SDLC enforcement for Claude Cowork sessions. Provides methodology guidance via skills AND prompt-based hooks that enforce discipline without shell access.

> **Claude Cowork** is a separate product from Claude Code — it's a desktop application for knowledge workers. This plugin targets the shared plugin format that works in both Code and Cowork.

## What You Get

| Component | Invocation / Event | Purpose |
|-----------|-------------------|---------|
| SDLC skill | `/sdlc-wizard-cowork:sdlc` | Full SDLC workflow: planning, TDD, self-review |
| Feedback skill | `/sdlc-wizard-cowork:feedback` | Privacy-first community feedback and pattern sharing |
| TDD hook | `PreToolUse` (Write/Edit) | Reminds you to write failing tests before implementation |
| SDLC baseline hook | `UserPromptSubmit` | Injects the SDLC checklist at every prompt |
| Completion hook | `Stop` | Checks confidence stated, self-review done, tests passing |

## Hooks — Prompt-Based Enforcement

This plugin ships 3 **prompt-based hooks** (`"type": "prompt"`) that enforce SDLC discipline without shell access. These are the Cowork equivalents of Claude Code's bash hooks:

| Cowork Hook | Claude Code Equivalent | Event |
|-------------|----------------------|-------|
| TDD check | `tdd-pretool-check.sh` | `PreToolUse` (Write/Edit/MultiEdit) |
| SDLC baseline | `sdlc-prompt-check.sh` | `UserPromptSubmit` |
| Completion check | _(new — no CC equivalent)_ | `Stop` |

Prompt hooks work by injecting instructions into Claude's context at the right moment — no bash, no shell, no filesystem access needed.

> **Note:** These hooks use the same format as Claude Code plugin hooks and match the spec documented in Anthropic's `cowork-plugin-management` plugin. However, they have not yet been tested in a live Cowork session. If hooks don't fire after install, file a bug on the [wizard repo](https://github.com/BaseInfinity/claude-sdlc-wizard/issues).

### What's NOT Ported (and Why)

| Claude Code Hook | Why Not Ported |
|-----------------|----------------|
| `instructions-loaded-check.sh` | `InstructionsLoaded` event not available in Cowork plugin hooks |
| `model-effort-check.sh` | Effort levels are CC-specific; Cowork doesn't expose model config |
| `precompact-seam-check.sh` | Depends on `.reviews/handoff.json` on disk; Cowork may not have filesystem |

### What's NOT Included (and Why)

**No Setup or Update skills** — these are CLI-specific (read version markers, write hooks to `.claude/`, run shell commands). Use the full wizard via `npx agentic-sdlc-wizard init` in a Claude Code session.

**CLI-dependent SDLC sections** — the `/sdlc` skill references tools you may not have in Cowork:

- **Cross-model review** (`codex exec`) — use ChatGPT/Codex web manually as your cross-model check
- **CI shepherd** (`gh pr`, `git push`) — these steps happen outside your Cowork session
- **`/code-review`** — works in Cowork if the plugin is loaded

The methodology (plan → TDD → self-review → confidence check) is universal. The hooks enforce it; the tooling commands are Claude Code shortcuts for steps you can do manually.

## Installation

### From GitHub (recommended)

Install as a plugin in Claude Desktop or claude.ai settings:

```
Plugin URL: https://github.com/BaseInfinity/claude-sdlc-wizard/tree/main/cowork
```

### Local testing

```bash
claude --plugin-dir ./cowork
```

## Relationship to the Full Wizard

This is a **subset** of the [SDLC Wizard](https://github.com/BaseInfinity/claude-sdlc-wizard). The full wizard provides:

- 6 lifecycle hooks (command-based, bash)
- 4 skills (sdlc, setup, update, feedback)
- CLI installer (`npx agentic-sdlc-wizard init`)
- npm package distribution

This Cowork plugin provides 2 portable skills + 3 prompt-based hooks — enforcement without shell access.

### Drift Prevention

The skills in this package are **copies** of the canonical skills in `skills/`. A CI test (`tests/test-cowork-drift.sh`) fails if they diverge. The test also validates hook format (prompt-only, correct events, valid JSON). When the canonical skills update, the test forces this package to sync.

## For Claude Code Users

If you have terminal access, use the full wizard instead:

```bash
npx agentic-sdlc-wizard init
```

This plugin is for Cowork-only users who want methodology guidance without the full CLI setup.

## Sibling Plugins

- [claude-gdlc-wizard](https://github.com/BaseInfinity/claude-gdlc-wizard) — Game Development (GDLC)
- [claude-rdlc-wizard](https://github.com/BaseInfinity/claude-rdlc-wizard) — Research (RDLC)

## Version

Tracks the main wizard version: **1.86.0**
