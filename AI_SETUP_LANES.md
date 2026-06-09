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

## How Billing Works — 1M Context, Max Plan, and the June 15 Split

A common question: **"does the `[1m]` model alias get billed differently? Does it pull from my Max plan or from API credits?"**

The short answer: **both lanes run on your Max subscription for interactive Claude Code sessions, including 1M context, with no premium surcharge.** Here's the detail.

### 1M context is free on Max — no API premium

[Anthropic 2026-03-13](https://claude.com/blog/1m-context-ga): 1M context is GA at standard $5/$25 per million tokens for Opus 4.6 (also 4.7, 4.8). No long-context multiplier. **No beta header required**, requests over 200K tokens just work.

For Claude Code on Max / Team / Enterprise plans, **1M context is included automatically** with no extra usage allocation. Whether you set `claude-opus-4-6` or `claude-opus-4-6[1m]` doesn't change *what* you're billed — both pull from the same per-token budget on your subscription. The `[1m]` suffix just makes the alias explicit so it sticks across alias-resolution changes; functionally Opus 4.6 in Claude Code today *is* the 1M-context model on a Max plan.

(Pro plan is the exception: Pro users need "Enable usage credits" turned on in their Claude account settings to use 1M context. Max / Team / Enterprise have it on by default.)

### The June 15, 2026 billing split

[Anthropic moved a slice of usage off the subscription](https://codersera.com/blog/anthropic-june-2026-billing-change-claude-code/) onto a separate metered credit pool that bills at full API rates:

| Surface | Billing as of June 15, 2026 |
|---|---|
| **Interactive Claude Code in terminal** (you typing into Claude Code right now) | **Stays on Max subscription** — unchanged |
| Claude.ai web / desktop / mobile chat | Stays on Max subscription |
| Claude Cowork | Stays on Max subscription |
| `claude -p` (headless / `--print`) | **Moves to separate credit pool**, billed at API rates |
| Claude Agent SDK | Moves to separate credit pool |
| Claude Code GitHub Actions | Moves to separate credit pool |
| Third-party apps via Agent SDK | Moves to separate credit pool |

Credit allocations: Pro $20/mo, Max 5x $100/mo, Max 20x $200/mo. **No rollover.**

### What this means for the lanes

- **Setup A — Premium (Opus 4.6 max planner + driver):** all interactive `/sdlc` work in Claude Code runs on your Max subscription. No API charges for the Claude side.
- **Setup B — Saver (Opus 4.6 max planner + Sonnet driver):** same — interactive Sonnet sessions also stay on Max. The cost-saving in B isn't avoiding API charges, it's getting more work-per-5-hour-window from Sonnet's lower per-turn token spend vs Opus.
- **Reviewer (GPT-5.5 xhigh) in both lanes:** billed against your OpenAI account, completely separate from Anthropic.
- **CI loops that use `claude -p` post-June-15:** these now bill against the separate Anthropic credit pool, not your Max subscription. The wizard's CI shepherd loops (E2E scoring, weekly-update jobs) are local-only on the maintainer's machine and stay on Max; consumer-repo CI integrations may need to budget the new credit pool.

### Bottom line

If you're using Claude Code interactively (you, in your terminal, doing `/sdlc` work), **both lanes ride your existing Max subscription**, and the `[1m]` alias is the same billable budget as plain `claude-opus-4-6`. No extra charges for the 1M context. The June 15 split only affects programmatic / headless / CI use of Claude Code.

Watch the headless surface if you've automated `claude -p` calls in your project — those now bill differently as of June 15, 2026.

## Maintainer Override

**Override at any time.** A blanket setup choice doesn't replace judgment per change. If you're touching CI but the change is a one-line typo, Setup B is fine. If you're touching docs but the section is the wizard's safety-critical hook ordering, Setup A is the call.

The wizard does not enforce setup lane selection — it documents the recommended default per change shape. Whatever ships is your call.

## See Also

- [`CLAUDE_CODE_SDLC_WIZARD.md`](CLAUDE_CODE_SDLC_WIZARD.md) — Full wizard doc, including Stability tier opt-in for the wider model choice
- [`README.md` § Choosing Your Model](README.md#choosing-your-model) — Model selection philosophy
- [`AGENTS.md`](AGENTS.md) — Codex/reviewer guidelines used in both lanes
