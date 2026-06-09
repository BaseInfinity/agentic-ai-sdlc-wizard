# AI Setup Lanes

Two recommended AI coding setups for this repo. Each is a complete triad: **planner → driver → reviewer**.

This is **guidance, not a hard rule**. Maintainer override is always allowed.

## Setup A — Claude Premium

| Role | Model |
|------|-------|
| **Planner** | Claude Code Opus 4.6 max |
| **Driver** | Claude Code Opus 4.6 max |
| **Reviewer** | Codex (GPT-5.5) xhigh |

Quality-first lane. Opus 4.6 max drives both the planning brain and the implementation hands; GPT-5.5 xhigh is the cross-model final gate that catches what Claude's self-review missed.

## Setup B — Claude Saver

| Role | Model |
|------|-------|
| **Planner** | Claude Code Opus 4.6 max |
| **Driver** | Claude Code Sonnet (latest available) |
| **Reviewer** | Codex (GPT-5.5) xhigh |

Cost-efficient lane. Keeps Opus 4.6 max as the planning brain — where context and reasoning matter most — but moves implementation to Sonnet for routine work. GPT-5.5 xhigh still the final reviewer. Use whatever Sonnet version the picker shows as latest.

## When to Use Setup A

Reach for Premium when the change can damage a consumer repo or has high blast radius:

- Architecture or methodology changes
- Tagged release prep
- Installer behavior (`cli/`, `init`, `setup-wizard`)
- Destructive file operations
- Package publishing
- Generated repo modifications (template changes)
- CI / release automation
- Security-sensitive behavior
- Anything that could damage a consumer repo

## When to Use Setup B

Setup B is sufficient for routine work where a Sonnet driver can ship with a strong reviewer:

- Routine implementation
- Documentation
- Examples
- Tests
- Normal CLI changes (non-installer)
- Low-risk methodology edits
- Mechanical refactors

## Final Review Policy

**Both lanes end at GPT-5.5 xhigh as the cross-model reviewer.** Claude can't grade its own homework — the reviewer always belongs to a different lab with different blind spots. See [CLAUDE_CODE_SDLC_WIZARD.md → "Cross-Model Review (Codex)"](CLAUDE_CODE_SDLC_WIZARD.md) for the handoff protocol.

If GPT-5.5 isn't available on your OpenAI account, Codex auto-falls back to GPT-5.4 — still keep `model_reasoning_effort="xhigh"`. Lower reasoning misses subtle bugs that the reviewer is the last gate to catch.

## Credit-Spend Warning

Both lanes use Opus 4.6 max for at least the planner — that's the expensive half. On Max-plan subscriptions, **Premium can burn the 5-hour cap faster than Saver** because Opus 4.6 max drives implementation too. If you're hitting the cap mid-session:

- Drop to Setup B for the remainder of the day
- Or stick with Premium but downshift effort to `xhigh` (Opus 4.6 still works well there)
- Or use Sonnet directly for the final mechanical edits, then run the GPT-5.5 reviewer over the whole diff at the end

The reviewer (GPT-5.5 xhigh) is billed against your OpenAI account, separately. Watch both bills.

## Maintainer Override

**Override at any time.** A blanket setup choice doesn't replace judgment per change. If you're touching CI but the change is a one-line typo, Setup B is fine. If you're touching docs but the section is the wizard's safety-critical hook ordering, Setup A is the call.

The wizard does not enforce setup lane selection — it documents the recommended default per change shape. Whatever ships is your call.

## See Also

- [`CLAUDE_CODE_SDLC_WIZARD.md`](CLAUDE_CODE_SDLC_WIZARD.md) — Full wizard doc, including Stability tier opt-in for the wider model choice
- [`README.md` § Choosing Your Model](README.md#choosing-your-model) — Model selection philosophy
- [`AGENTS.md`](AGENTS.md) — Codex/reviewer guidelines used in both lanes
