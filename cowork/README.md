# SDLC Wizard — Cowork Plugin

SDLC enforcement for Claude Cowork sessions. Provides methodology guidance via skills AND prompt-based hooks that enforce discipline without shell access.

> **Claude Cowork** is a separate product from Claude Code — it's a desktop application for knowledge workers. This plugin targets the shared plugin format that works in both Code and Cowork.

## What You Get

| Component | Invocation / Event | Purpose |
|-----------|-------------------|---------|
| SDLC skill | `/sdlc-wizard-cowork:sdlc` | Full SDLC workflow: planning, TDD, self-review |
| Feedback skill | `/sdlc-wizard-cowork:feedback` | Privacy-first community feedback and pattern sharing |
| TDD hook | `PreToolUse` (Write/Edit) | Denies creating a new non-test file that doesn't look like a test (filename heuristic — see limits below) |
| SDLC baseline hook | `UserPromptSubmit` | Denies prompts that explicitly ask to skip planning/testing/review |
| Completion hook | `Stop` | Denies stopping if code changed but tests weren't shown passing, self-review is missing, or no confidence was stated |

## Hooks — Prompt-Based Enforcement

This plugin ships 3 **prompt-based hooks** (`"type": "prompt"`) that enforce SDLC discipline without shell access. These are the Cowork equivalents of Claude Code's bash hooks:

| Cowork Hook | Claude Code Equivalent | Event |
|-------------|----------------------|-------|
| TDD check | `tdd-pretool-check.sh` | `PreToolUse` (Write/Edit/MultiEdit) |
| SDLC baseline | `sdlc-prompt-check.sh` | `UserPromptSubmit` |
| Completion check | _(new — no CC equivalent)_ | `Stop` |

**Prompt hooks do not inject text into the main conversation.** Per Anthropic's documented `prompt` hook contract (`code.claude.com/docs/en/hooks`), each hook sends its `prompt` field to a separate, single-turn evaluator model (Haiku by default), with the hook's JSON input either substituted at `$ARGUMENTS` or auto-appended if `$ARGUMENTS` is omitted. The evaluator must respond `{"ok": true}` to allow, or `{"ok": false, "reason": "..."}` to deny — no shell, no filesystem access needed, but also no soft reminders: it's a real gate, not a nudge. Blocking semantics differ per event — `Stop`'s reason is fed back to Claude and the turn continues (it can actually fix things and retry); `UserPromptSubmit`'s block ends the turn outright with no retry, so it's scoped narrowly (see the hook's own prompt in `hooks/hooks.json`).

**Known limit:** the `PreToolUse` TDD check can only see the current file write, not prior turns or the filesystem — it's a best-effort filename heuristic (denies creating a new non-test file), not proof a failing test was actually run first. A `type: "agent"` hook (multi-turn, with Read/Grep/Glob access) would be the mechanically correct fix for real TDD-order verification; that's a larger, separate change, tracked as a follow-up rather than attempted here.

> **Note:** Live-tested via Codex Desktop computer-use E2E runs (issue [#432](https://github.com/BaseInfinity/claude-sdlc-wizard/issues/432), 2026-07-19/20). An earlier version of these hooks was authored against an incorrect understanding of the mechanism (wrong response schema, checklist-style prompts with no explicit final decision request) — see [#456](https://github.com/BaseInfinity/claude-sdlc-wizard/issues/456) — and has since been rewritten to match Anthropic's documented examples. If hooks still misbehave after install, file a bug on the [wizard repo](https://github.com/BaseInfinity/claude-sdlc-wizard/issues).

### What's NOT Ported (and Why)

| Claude Code Hook | Why Not Ported |
|-----------------|----------------|
| `instructions-loaded-check.sh` | `InstructionsLoaded` event not available in Cowork plugin hooks |
| `model-effort-check.sh` | Effort levels are CC-specific; Cowork doesn't expose model config |
| `precompact-seam-check.sh` | Depends on `.git/` on disk (rebase/merge/cherry-pick state); Cowork may not have filesystem |

### What's NOT Included (and Why)

**No Setup or Update skills** — these are CLI-specific (read version markers, write hooks to `.claude/`, run shell commands). Use the full wizard via `npx agentic-sdlc-wizard init` in a Claude Code session.

**CLI-dependent SDLC sections** — the `/sdlc` skill references tools you may not have in Cowork:

- **Cross-model review** (`codex exec`) — use ChatGPT/Codex web manually as your cross-model check
- **CI shepherd** (`gh pr`, `git push`) — these steps happen outside your Cowork session
- **`/code-review`** — works in Cowork if the plugin is loaded

The methodology (plan → TDD → self-review → confidence check) is universal. The hooks enforce it; the tooling commands are Claude Code shortcuts for steps you can do manually.

## Installation

### From GitHub (recommended)

The plugin lives in a subdirectory of the main wizard repo, so it's registered as a second entry (`sdlc-wizard-cowork`) in the repo's root marketplace via a `git-subdir` source — a GitHub web-UI URL like `.../tree/main/cowork` is **not** a supported marketplace source on its own (only `owner/repo` shorthand, full git URLs, local paths, or direct `marketplace.json` URLs are). Add the whole repo as a marketplace, then install the Cowork-specific plugin from it:

```
/plugin marketplace add BaseInfinity/claude-sdlc-wizard
/plugin install sdlc-wizard-cowork@sdlc-wizard-marketplace
```

In Claude Desktop's UI, this is Customize > Plugins > Add marketplace, entering `BaseInfinity/claude-sdlc-wizard`, then selecting `sdlc-wizard-cowork` from the marketplace's plugin list (not the top-level `sdlc-wizard` entry, which is the CLI-based full wizard).

**Fallback (local ZIP upload):** if the marketplace/install flow isn't available in your Claude Desktop build, zip this `cowork/` directory (root must contain `.claude-plugin/`, `hooks/`, `skills/`, `README.md`) and use Customize > Plugins > Add plugin > Upload plugin instead.

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

Tracks the main wizard version: **1.89.0**
