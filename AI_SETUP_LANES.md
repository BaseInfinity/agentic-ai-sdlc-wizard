# AI Setup Lanes

Three recommended AI coding setups for this repo. Setups A and B are complete triads: **planner → driver → reviewer**. Setup C is a lightweight driver-only lane for operational grunt work.

This is **guidance, not a hard rule**. Maintainer override is always allowed.

## Setup A — Claude Premium

| Role | Model |
|------|-------|
| **Advisor** | Fable 5 (via `advisorModel: "fable"` in project settings — auto-consults at key decisions) |
| **Driver** | Opus 4.6 max |
| **Reviewer** | Codex (GPT-5.5) xhigh |
| **Escalation** | + Fable 5 review (security, releases, wide-blast architecture only) |

Quality-first lane. Fable 5 advises automatically at key decision points (architecture, complexity, blast-radius) via native `advisorModel` (v2.1.170+), Opus 4.6 max implements (stable, Max-bundled), GPT-5.5 xhigh reviews (cross-family, free on ChatGPT sub, catches blind spots Fable can't see in its own work). Escalate to Fable review for the ~5% of PRs where stakes justify it.

## Setup B — Claude Saver (OpusPlan)

| Role | Model |
|------|-------|
| **Planner** | Opus 4.6 max (via Plan Mode — Shift+Tab) |
| **Advisor** | Opus 4.6 (via `advisorModel: "claude-opus-4-6"` — compensates for Sonnet driver) |
| **Driver** | Sonnet (latest, auto execute mode) |
| **Reviewer** | Codex (GPT-5.5) xhigh |

Cost-efficient lane using CC's native `opusplan` alias. Opus reasons during Plan Mode (Shift+Tab), Sonnet executes. Both 200K context, Max-bundled — no API credit drain. Pin `model: "opusplan"` + `advisorModel: "claude-opus-4-6"` + `CLAUDE_CODE_EFFORT_LEVEL=max` in project settings. The Opus advisor auto-compensates for Sonnet's lighter reasoning at key decision points. GPT-5.5 xhigh is the cross-model reviewer.

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

## Setup C — Claude Lite

| Role | Model | Notes |
|------|-------|-------|
| **Planner** | You (the user) | Task is pre-planned, no model reasoning needed |
| **Driver** | Sonnet 4.6 | Same model as Setup B driver — Max-bundled, no extra model to manage |
| **Reviewer** | None | Blast radius too low for cross-model overhead |

The "just do the thing" lane. No TDD enforcement, no cross-model review, no planning phase. You already know what to do — you just need a fast, cheap pair of hands.

## When to Use Setup C

Setup C is for work where SDLC discipline overhead exceeds the value:

- Run a script with basic intelligence
- Deploy to staging (prod deploys need Setup A's discipline — human gate + rollback plan)
- Config updates, env var changes
- File moves, renames, bulk operations
- Repo maintenance (dependency bumps, lockfile refreshes)
- Simple administrative tasks across repos like `~/afterhours`
- Anything where blast radius is low and you need speed, not depth

**Not Lite — escalate to A or B:** env vars that touch secrets or credentials, dependency bumps with security advisories, destructive bulk ops (rm -rf, drop table), migrations, prod-like shared staging, anything security-sensitive. If you're unsure, it's not Lite.

## What Setup C explicitly skips

- No TDD (no test-first for running a deploy script)
- No cross-model review (not worth the cost or time for grunt work)
- No planning phase (you are the planner)
- No effort escalation (Sonnet standard is plenty)

**The discipline of knowing when NOT to use discipline.** Documenting this lane tells users "here's when to switch off the heavy methodology" rather than silently tempting them to skip it. If the task turns out to be harder than expected, escalate to Setup B or A.

## Final Review Policy

**Setups A and B end at GPT-5.5 xhigh as the cross-model reviewer.** Claude can't grade its own homework — the reviewer always belongs to a different lab with different blind spots. See [CLAUDE_CODE_SDLC_WIZARD.md → "Cross-Model Review (Codex)"](CLAUDE_CODE_SDLC_WIZARD.md) for the handoff protocol.

**Setup C has no reviewer** — the blast radius doesn't justify it. If you're unsure whether a task is truly Lite, it probably isn't. Escalate.

If GPT-5.5 isn't available on your OpenAI account, Codex auto-falls back to GPT-5.4 — still keep `model_reasoning_effort="xhigh"`. Lower reasoning misses subtle bugs that the reviewer is the last gate to catch.

## Version Requirement

`advisorModel` in settings.json requires **Claude Code v2.1.170+**. Check your version with `claude --version`. If below v2.1.170, update from inside a CC session:

```
! claude update
```

The `!` prefix runs shell commands inside your CC session — no need to exit and re-enter. After updating, restart the session for the advisor to activate.

Fable 5 as advisor also requires Fable 5 access for your organization/plan (free on Max through June 22, 2026).

## Credit-Spend Warning

Setups A and B use Opus 4.6 max for at least the planner — that's the expensive half. On Max-plan subscriptions, **Premium can burn the 5-hour cap faster than Saver** because Opus 4.6 max drives implementation too. If you're hitting the cap mid-session:

- Drop to Setup B for the remainder of the day
- Or drop to Setup C for grunt work that doesn't need Opus reasoning
- Or use Sonnet directly for the final mechanical edits, then run the GPT-5.5 reviewer over the whole diff at the end

**Setup C uses Sonnet** — same model as Setup B's driver, Max-bundled. One less model to manage.

The reviewer (GPT-5.5 xhigh) is billed against your OpenAI account, separately. Watch both bills.

## How Billing Works — 1M Context, Max Plan, and the June 15 Split

A common question: **"does the `[1m]` model alias get billed differently? Does it pull from my Max plan or from API credits?"**

The short answer: **Setup A uses Fable planner (free during trial, API post-June 22) + Opus driver (Max-bundled). Setup B is fully Max-bundled via opusplan.** Here's the detail.

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

- **Setup A — Premium (Fable advisor + Opus driver):** Fable 5 advisor via `advisorModel: "fable"` in project settings — interactive session, Max-bundled. Opus 4.6 max driver on Max. GPT-5.5 xhigh reviewer on ChatGPT subscription.
- **Setup B — Saver (OpusPlan):** **fully Max-bundled.** `opusplan` uses Opus (plan mode) + Sonnet (execute mode), both at 200K context — no `[1m]` variants, no credit drain. This is why Setup B now recommends `opusplan` instead of the old `sonnet[1m]` pin (#390).
  - **⚠️ Avoid `sonnet[1m]`:** Sonnet with 1M context draws from your usage credits pool ($3/$15 per Mtok), NOT your Max subscription. The `/model` picker shows this explicitly. Plain `sonnet` (200K) or `opusplan` stays on Max.
- **Reviewer (GPT-5.5 xhigh) in both lanes:** billed against your OpenAI account, completely separate from Anthropic.
- **CI loops that use `claude -p` post-June-15:** these now bill against the separate Anthropic credit pool, not your Max subscription. The wizard's CI shepherd loops (E2E scoring, weekly-update jobs) are local-only on the maintainer's machine and stay on Max; consumer-repo CI integrations may need to budget the new credit pool.

### Caveat: Setup B's cost-saving has conditions

The savings argument for Setup B is "Sonnet driver is cheaper than Opus driver per turn." **That's true at standard 200K context.** If your Sonnet driver needs to load >200K tokens (large diff, multi-file refactor, monorepo audit), the bill quietly flips:

| Mode | Per-token rate | Pool |
|---|---|---|
| Setup A — Opus 4.6 1M | $5/$25 per Mtok | **Max subscription** |
| Setup B — Sonnet 4.6 standard | $3/$15 per Mtok | **Max subscription** |
| Setup B — Sonnet 4.6 1M | $3/$15 per Mtok | **Credits pool** |

So **for context-heavy work that crosses 200K, Setup A on Max is actually cheaper than Setup B on credits** — because Setup A's Opus stays on the Max pool while Setup B's Sonnet 1M draws down a separately-metered $100/mo (Max 5x) or $200/mo (Max 20x) credit budget.

**Practical guidance:**

- **Subscription-first mindset (recommended):** Use Setup A unless you're confident the Sonnet driver in Setup B stays under 200K context. The Opus 4.6 max planner+driver combo lives entirely on Max — no credit-pool drawdown.
- **Setup B is a real cost win only when:** the driver task fits in ≤ 200K (routine implementation, single-file work, small refactors, docs). Use B specifically for those, not as a blanket choice.
- **Watch the picker.** When you swap to Sonnet 1M, Claude Code shows "Draws from usage credits" explicitly. That's your billing flip signal — choose Opus 1M instead if you want to stay on Max.

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
