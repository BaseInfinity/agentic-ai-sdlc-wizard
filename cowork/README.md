# SDLC Harness — Cowork Plugin

## The Shallow Surface — By Design

This project's primary target is **Claude Code (CLI)**. Cowork support is a bonus surface
and will never hold the CLI back. What ships here is deliberately the shallow version.

**You get:** the complete `/sdlc` operational checklist — byte-identical to the CLI skill,
nothing removed — plus the `/feedback` skill and two best-effort prompt hooks.

**You do not get:**

- **`CLAUDE_CODE_SDLC_WIZARD.md`** (the ~291 KB deep-protocol doc). The skill cites it for
  optional depth; in Cowork those citations are inert. The checklist is the complete
  contract on its own, and the skill says so at the top.
- Setup/update skills, shell hooks, the CLI installer, or cross-model review tooling.
- **Enforcement.** Live testing (GH #456) found the prompt hooks do not reliably gate, and
  the completion hook was removed in v1.92.0 after firing 12 times and being wrong 11. The
  two remaining hooks are nudges with **no enforcement guarantee**. That rewrite has not
  been re-validated live — treat enforcement as unproven, not merely absent.

**If you have a terminal, use the full wizard:** `npx agentic-sdlc-wizard init`.

**Why this is not forked into a Cowork-specific skill.** The skill is byte-identical across
both surfaces, enforced by `tests/test-cowork-drift.sh`. Two hand-maintained copies of a
20 KB operational contract would silently diverge — this repo's most reliable source of
defects — to fix pointers that are inert text here anyway.

## What You Get

| Component | Invocation / Event | Purpose |
|-----------|-------------------|---------|
| SDLC skill | `/sdlc-wizard-cowork:sdlc` | Full SDLC workflow: planning, TDD, self-review |
| Feedback skill | `/sdlc-wizard-cowork:feedback` | Privacy-first community feedback and pattern sharing |
| TDD hook | `PreToolUse` (Write/Edit) | Denies creating a new non-test file that doesn't look like a test (filename heuristic — see limits below) |
| ~~Completion hook~~ | ~~`Stop`~~ | **REMOVED in v1.92.0 (GH #484).** It fired 12 times in one session and was wrong 11 — blocking turns that changed no files, turns already verified, and repeatedly overriding its own stated exemptions. A `Stop` hook fires at the end of *every* turn, so a blocking one interrupts constantly. There is now **no completion enforcement in Cowork**; see the honesty note below. |

## Hooks — Prompt-Based Enforcement

This plugin ships 1 **prompt-based hook** (`"type": "prompt"`) — a narrow slice of SDLC discipline, without shell access. The `Stop` (completion) hook was removed in v1.92.0 (GH #484) and the `UserPromptSubmit` hook in v1.97.0 (GH #561).

| Cowork Hook | Claude Code Equivalent | Event |
|-------------|----------------------|-------|
| TDD check | `tdd-pretool-check.sh` | `PreToolUse` (Write/Edit/MultiEdit) |


**Prompt hooks do not inject text into the main conversation.** Per Anthropic's documented `prompt` hook contract (`code.claude.com/docs/en/hooks`), each hook sends its `prompt` field to a separate, single-turn evaluator model (Haiku by default), with the hook's JSON input either substituted at `$ARGUMENTS` or auto-appended if `$ARGUMENTS` is omitted. The evaluator must respond `{"ok": true}` to allow, or `{"ok": false, "reason": "..."}` to deny — no shell, no filesystem access needed, but also no soft reminders: it's a real gate, not a nudge.

**Known limit:** the `PreToolUse` TDD check can only see the current file write, not prior turns or the filesystem — it's a best-effort filename heuristic (denies creating a new non-test file), not proof a failing test was actually run first. A `type: "agent"` hook (multi-turn, with Read/Grep/Glob access) would be the mechanically correct fix for real TDD-order verification; that's a larger, separate change, tracked as a follow-up rather than attempted here.

> **Note:** Live-tested via Codex Desktop computer-use E2E runs (issue [#432](https://github.com/BaseInfinity/claude-sdlc-harness/issues/432), 2026-07-19/20). An earlier version of these hooks was authored against an incorrect understanding of the mechanism (wrong response schema, checklist-style prompts with no explicit final decision request) — see [#456](https://github.com/BaseInfinity/claude-sdlc-harness/issues/456) — and has since been rewritten to match Anthropic's documented examples. If hooks still misbehave after install, file a bug on the [wizard repo](https://github.com/BaseInfinity/claude-sdlc-harness/issues).

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

The methodology (plan → TDD → cross-model review → confidence check) is universal, and the skills describe all of it. **One hook remains, and it enforces very little** — do not read the table above as full enforcement. `PreToolUse` applies a filename heuristic to brand-new non-test files. That is the whole of it.

**There is no completion gate and no prompt gate.** The `Stop` hook was removed in v1.92.0 (GH #484) after scoring 11 false positives in 12 firings; the `UserPromptSubmit` classifier was removed in v1.97.0 (GH #561) after denying the maintainer's own instructions twice, the second time after a narrowing repair. Blocking hooks belong on ACTS, not on turn-level subject matter.

**The honest cost of that removal:** a prompt asking to skip planning or review, followed by edits to files that already exist, now hits no gate at all — `PreToolUse` fails open for edits, and the CLI's commit and merge gates cannot run in Cowork, which has no shell. Everything else is guidance you follow, not a gate that stops you.

## Installation

### From GitHub (recommended)

The plugin lives in a subdirectory of the main wizard repo, so it's registered as a second entry (`sdlc-wizard-cowork`) in the repo's root marketplace via a `git-subdir` source — a GitHub web-UI URL like `.../tree/main/cowork` is **not** a supported marketplace source on its own (only `owner/repo` shorthand, full git URLs, local paths, or direct `marketplace.json` URLs are). Add the whole repo as a marketplace, then install the Cowork-specific plugin from it:

```
/plugin marketplace add BaseInfinity/claude-sdlc-harness
/plugin install sdlc-wizard-cowork@sdlc-wizard-marketplace
```

In Claude Desktop's UI, this is Customize > Plugins > Add marketplace, entering `BaseInfinity/claude-sdlc-harness`, then selecting `sdlc-wizard-cowork` from the marketplace's plugin list (not the top-level `sdlc-wizard` entry, which is the CLI-based full wizard).

**Fallback (local ZIP upload):** if the marketplace/install flow isn't available in your Claude Desktop build, zip this `cowork/` directory (root must contain `.claude-plugin/`, `hooks/`, `skills/`, `README.md`) and use Customize > Plugins > Add plugin > Upload plugin instead.

### Local testing

```bash
claude --plugin-dir ./cowork
```

## Relationship to the Full Wizard

This is a **subset** of the [SDLC Harness](https://github.com/BaseInfinity/claude-sdlc-harness). The full wizard provides:

- 6 lifecycle hooks (command-based, bash)
- 4 skills (sdlc, setup, update, feedback)
- CLI installer (`npx agentic-sdlc-wizard init`)
- npm package distribution

This Cowork plugin provides 2 portable skills + 1 prompt-based hook — a narrow slice of enforcement without shell access.

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

Tracks the main wizard version: **1.96.0**
