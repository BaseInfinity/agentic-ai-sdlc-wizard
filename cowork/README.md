# SDLC Wizard — Cowork Plugin

Methodology guidance for Claude Cowork sessions. Provides the SDLC workflow and community feedback skills without enforcement hooks.

## What You Get

| Skill | Invocation | Purpose |
|-------|------------|---------|
| SDLC | `/sdlc-wizard-cowork:sdlc` | Full SDLC workflow: planning, TDD, self-review, CI shepherd |
| Feedback | `/sdlc-wizard-cowork:feedback` | Privacy-first community feedback and pattern sharing |

## What You Don't Get (and Why)

### No Hooks (Enforcement Gap)

The full SDLC wizard uses 6 lifecycle hooks to enforce discipline at every interaction (TDD reminders before file edits, model/effort checks at session start, etc.). **Cowork hook support is unverified** — the plugin system is shared between Code and Cowork, but hook execution in Cowork sessions has not been confirmed.

This plugin ships skills only. You get the methodology guidance; enforcement relies on you following it rather than hooks forcing it.

### No Setup or Update Skills

The `/setup` and `/update` skills are CLI-specific — they read version markers, write hooks to `.claude/`, and run shell commands. These don't translate to Cowork's sandboxed environment. Use the full wizard via `npx agentic-sdlc-wizard init` in a Claude Code session if you need setup/update.

### CLI-Dependent Sections in the SDLC Skill

The `/sdlc` skill references shell tooling you may not have in Cowork:

- **Cross-model review** (`codex exec`) — requires Codex CLI + OpenAI API key + shell access. In Cowork, skip this or use ChatGPT/Codex web manually as your cross-model check.
- **CI shepherd** (`gh pr`, `git push`) — requires terminal. In Cowork, these steps happen outside your session.
- **`/code-review`** — works in Cowork if the plugin is loaded; runs against your session context.

The methodology (plan → TDD → self-review → confidence check) is universal. The tooling commands are Claude Code shortcuts for steps you can do manually in any surface.

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

- 6 lifecycle hooks (enforcement)
- 4 skills (sdlc, setup, update, feedback)
- CLI installer (`npx agentic-sdlc-wizard init`)
- npm package distribution

This Cowork plugin provides the 2 portable skills (sdlc + feedback) that work without shell access or hook enforcement.

### Drift Prevention

The skills in this package are **copies** of the canonical skills in `skills/`. A CI test (`tests/test-cowork-drift.sh`) fails if they diverge. When the canonical skills update, the test forces this package to sync.

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

Tracks the main wizard version: **1.83.0**
