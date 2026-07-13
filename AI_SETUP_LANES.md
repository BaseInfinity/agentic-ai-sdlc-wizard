# AI Setup Lanes

Four recommended AI coding setups for this repo. Setups A, B, and C are complete triads: **planner → driver → reviewer**. Setup D is a lightweight driver-only lane for operational grunt work.

This is **guidance, not a hard rule**. Maintainer override is always allowed.

## Setup A — Sonnet 5 + Fable Advisor (Recommended)

| Role | Model | Effort |
|------|-------|--------|
| **Advisor** | Fable 5 (via `advisorModel: "fable"`) | `high` (server-side) |
| **Driver** | Sonnet 5 (`claude-sonnet-5`) | `medium` default, escalate `high` → `xhigh` for hard tasks |
| **Reviewer** | Codex (GPT-5.6 Sol) xhigh | — |
| **Escalation** | Opus 4.8 xhigh or Fable 5 review | When stuck or high-stakes |

The new standard. Sonnet 5 beats Opus 4.6 on every coding benchmark (SWE-bench Verified 85.2% vs 80.8%, Terminal-Bench 80.4% vs 65.4%) and generally uses less Max quota — but the savings are not a fixed ratio: Sonnet 5's newer tokenizer produces ~30% more tokens for the same text than Opus 4.6's (per Anthropic's pricing docs), and community cost reports suggest the advantage narrows at `high`/`xhigh`. No controlled Sonnet-5-vs-Opus-4.6 quota measurement exists — check your own burn with `/usage`. Fable 5 advises at key decision points via native `advisorModel` (v2.1.170+). GPT-5.6 Sol xhigh reviews cross-family. Escalate to Opus 4.8 xhigh for the hardest debugging or architecture decisions — don't run Opus as the daily driver.

**Effort escalation ladder:** Start at `medium` — CodeRabbit's testing found it captures most of Sonnet 5's upside at the lowest cost. Raise to `high` when medium struggles, `xhigh` for hard debugging, multi-file migrations, or long agent runs. `max` is rarely worth it — doubles cost for marginal gains per the same CodeRabbit testing.

**Requires:** Claude Code v2.1.197+ (Sonnet 5 alias resolution), Fable 5 access for advisor.

## Setup B — Opus 4.6 Stability (Legacy Flagship)

| Role | Model | Effort |
|------|-------|--------|
| **Advisor** | Fable 5 (via `advisorModel: "fable"`) | `high` (server-side) |
| **Driver** | Opus 4.6 (`claude-opus-4-6`) | `max` |
| **Reviewer** | Codex (GPT-5.6 Sol) xhigh | — |

The consistency-first lane. Opus 4.6 is the only model where `max` effort works without overthinking — months of field data, Active through at least Feb 2027, proven predictable. Lower benchmark scores than Sonnet 5 but higher consistency. Choose this when you've tuned prompts to Opus 4.6 behavior and reliability matters more than peak capability.

**Effort:** Opus 4.6 at `max` (no xhigh support — only low/medium/high/max). This is the sweet spot; community reports confirm 4.6 is the only Opus where `max` doesn't over-engineer.

## Setup C — OpusPlan Hybrid (Saver)

| Role | Model | Effort |
|------|-------|--------|
| **Planner** | Opus 4.8 (via Plan Mode — Shift+Tab) | `xhigh` |
| **Advisor** | Fable 5 or Opus 4.8 (via `advisorModel`) | — |
| **Driver** | Sonnet 5 (auto execute mode) | `medium`, escalate `high` for hard runs |
| **Reviewer** | Codex (GPT-5.6 Sol) xhigh | — |

Cost-efficient hybrid using CC's native `opusplan` alias. Opus 4.8 reasons during Plan Mode, Sonnet 5 executes. Max-bundled — no API credit drain. Pin `model: "opusplan"` + `advisorModel: "fable"` in project settings. Sonnet 5 now uses 1M context natively (no `[1m]` suffix needed). GPT-5.6 Sol xhigh is the cross-model reviewer.

**Note:** Opus 4.6 cannot advise Sonnet 5 (rejected in the advisor pairing table). Use Fable 5 or Opus 4.8 as advisor for this lane.

## Setup D — Claude Lite

| Role | Model | Effort | Notes |
|------|-------|--------|-------|
| **Planner** | You (the user) | — | Task is pre-planned, no model reasoning needed |
| **Driver** | Sonnet 5 | `medium` | Max-bundled, ≈ Sonnet 4.6 at high quality |
| **Reviewer** | None | — | Blast radius too low for cross-model overhead |

The "just do the thing" lane. No TDD enforcement, no cross-model review, no planning phase. You already know what to do — you just need a fast, cheap pair of hands.

## When to Use Setup A

The default choice for most SDLC work — full discipline (TDD, cross-model review) at generally lower quota cost than Setup B (see Credit-Spend Warning below):

- Feature implementation and routine development
- Documentation and examples
- Test writing
- Normal CLI changes
- Mechanical refactors
- Anything where you'd reach for Setup B out of habit rather than a specific need for Opus 4.6's proven consistency

## When to Use Setup B

Reach for Setup B when the change can damage a consumer repo, has high blast radius, or you've specifically tuned your workflow to Opus 4.6's behavior:

- Architecture or methodology changes
- Tagged release prep
- Installer behavior (`cli/`, `init`, `setup-wizard`)
- Destructive file operations
- Package publishing
- Generated repo modifications (template changes)
- CI / release automation
- Security-sensitive behavior
- Anything that could damage a consumer repo

## When to Use Setup C

Setup C is sufficient for routine work where a Sonnet driver can ship with a strong reviewer and you want the Max-bundled cost profile of `opusplan`:

- Routine implementation
- Documentation
- Examples
- Tests
- Normal CLI changes (non-installer)
- Low-risk methodology edits
- Mechanical refactors

## When to Use Setup D

Setup D is for work where SDLC discipline overhead exceeds the value:

- Run a script with basic intelligence
- Deploy to staging (prod deploys need Setup A's or B's discipline — human gate + rollback plan)
- Config updates, env var changes
- File moves, renames, bulk operations
- Repo maintenance (dependency bumps, lockfile refreshes)
- Simple administrative tasks across repos like `~/afterhours`
- Anything where blast radius is low and you need speed, not depth

**Not Lite — escalate to A or B:** env vars that touch secrets or credentials, dependency bumps with security advisories, destructive bulk ops (rm -rf, drop table), migrations, prod-like shared staging, anything security-sensitive. If you're unsure, it's not Lite.

## What Setup D explicitly skips

- No TDD (no test-first for running a deploy script)
- No cross-model review (not worth the cost or time for grunt work)
- No planning phase (you are the planner)
- No effort escalation (Sonnet standard is plenty)

**The discipline of knowing when NOT to use discipline.** Documenting this lane tells users "here's when to switch off the heavy methodology" rather than silently tempting them to skip it. If the task turns out to be harder than expected, escalate to Setup A or B.

## Final Review Policy

**Setups A, B, and C end at GPT-5.6 Sol xhigh as the cross-model reviewer.** Claude can't grade its own homework — the reviewer always belongs to a different lab with different blind spots. See [CLAUDE_CODE_SDLC_WIZARD.md → "Cross-Model Review (Codex)"](CLAUDE_CODE_SDLC_WIZARD.md) for the handoff protocol.

**Setup D has no reviewer** — the blast radius doesn't justify it. If you're unsure whether a task is truly Lite, it probably isn't. Escalate.

If GPT-5.6 Sol isn't available on your OpenAI account, Codex auto-falls back to Terra — still keep `model_reasoning_effort="xhigh"`. Lower reasoning misses subtle bugs that the reviewer is the last gate to catch.

**Escalation for unusually risky PRs:** `xhigh` is the evidence-based default — OpenAI's own migration guidance is to preserve the prior effort baseline, and no published data shows `max` or Pro mode catching meaningfully more real bugs than `xhigh` on ordinary PR review. For a PR you'd genuinely lose sleep over (security-sensitive, high blast radius, touches the installer or a consumer-facing template), escalate the reviewer to `max` or Pro mode — a once-per-PR gate is exactly the kind of low-frequency, high-stakes call site where the extra cost is easiest to justify. Don't make it the default.

## Version Requirement

`advisorModel` in settings.json requires **Claude Code v2.1.170+**. Check your version with `claude --version`. If below v2.1.170, update from inside a CC session:

```
! claude update
```

The `!` prefix runs shell commands inside your CC session — no need to exit and re-enter. After updating, restart the session for the advisor to activate.

Fable 5 as advisor also requires Fable 5 access for your organization/plan. Fable's inclusion in subscriptions has run in separate windows rather than continuously — free through June 22, 2026, then a second window July 1-7, 2026 (up to 50% of weekly usage limits), then usage-credit metered. Check [anthropic.com/claude/fable](https://www.anthropic.com/claude/fable) for current status rather than assuming either window is still open.

## When the Advisor Is Unavailable

If the advisor returns "Advisor unavailable," the server-side harness failed to initialize. No in-session action (`/model`, `/clear`) can recover it.

**Step 1 — restart the session.** Exit and run `claude` (not `--resume`). A fresh process re-initializes the server handshake. This resolves most advisor failures.

**Step 2 — if the API incident persists:**

- Continue with your driver model and no advisor — `/model sonnet` for Setup A, `/model claude-opus-4-6` for Setup B. Interactive — stays on your Max subscription.
- Or proceed without the advisor and let the Codex xhigh PR gate catch issues.

**Last resort (scripted/CI only):**

- `claude --model fable --effort high -p "$(cat <file>)"` — headless mode bills API credits, not your Max subscription.

Check [status.claude.com](https://status.claude.com) if the advisor fails across multiple fresh sessions.

Whichever path you use, the cross-model PR review gate still applies.

## Credit-Spend Warning

**Setup B (Opus 4.6 max as both planner and driver) burns the 5-hour cap faster than Setup A** — Opus 4.6 max driving implementation is the expensive path; Sonnet 5 at `medium`/`high` generally uses less quota for comparable benchmark results (the advantage narrows at `xhigh` — more turns per task plus tokenizer overhead). If you're hitting the cap mid-session on Setup B:

- Drop to Setup A (Sonnet 5) for the remainder of the day — same discipline, typically lower quota burn (widest advantage at `medium`)
- Or drop to Setup D for grunt work that doesn't need deep reasoning
- Or use Sonnet directly for the final mechanical edits, then run the GPT-5.6 Sol reviewer over the whole diff at the end

**Setup D uses Sonnet** — same model as Setup A's driver, Max-bundled. One less model to manage if you're already on Setup A.

The reviewer (GPT-5.6 Sol xhigh) is billed against your OpenAI account, separately. Watch both bills.

## Autocompact Thresholds

For recommended `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` values per context window and task shape, see [CLAUDE_CODE_SDLC_WIZARD.md → Autocompact Tuning](CLAUDE_CODE_SDLC_WIZARD.md#autocompact-tuning). Sonnet 5 (Setup A, D) has its own native ~967K-token proactive-compaction default at 1M context — don't carry over Opus-era 1M threshold guidance unexamined.

## How Billing Works — 1M Context, Max Plan, and the June 15 Split

A common question: **"does the `[1m]` model alias get billed differently? Does it pull from my Max plan or from API credits?"**

The short answer: **Setup A (Sonnet 5, native 1M) and Setup C (opusplan, Opus plan-mode + Sonnet execute) are both fully Max-bundled in interactive sessions. Setup B (Opus 4.6 max) is also Max-bundled, including its 1M context.** Here's the detail.

### 1M context is free on Max — no API premium

[Anthropic 2026-03-13](https://claude.com/blog/1m-context-ga): 1M context is GA at standard $5/$25 per million tokens for Opus 4.6 (also 4.7, 4.8). No long-context multiplier. **No beta header required**, requests over 200K tokens just work. Sonnet 5 always runs at 1M natively (see [`code.claude.com/docs/en/model-config#sonnet-5-context-window`](https://code.claude.com/docs/en/model-config#sonnet-5-context-window)) — no `[1m]` suffix, no separate billing tier.

For Claude Code on Max / Team / Enterprise plans, **1M context is included automatically** with no extra usage allocation for supported models. Whether you set `claude-opus-4-6` or `claude-opus-4-6[1m]` doesn't change *what* you're billed — both pull from the same per-token budget on your subscription. The `[1m]` suffix just makes the alias explicit so it sticks across alias-resolution changes; functionally Opus 4.6 in Claude Code today *is* the 1M-context model on a Max plan.

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

- **Setup A — Sonnet 5 + Fable advisor:** Sonnet 5's native 1M context — interactive session, Max-bundled, no `[1m]` suffix needed. Fable 5 advisor via `advisorModel: "fable"` — also Max-bundled. GPT-5.6 Sol xhigh reviewer on ChatGPT subscription. Generally lower Max quota consumption than Setup B at the `medium` default (savings shrink at higher effort).
- **Setup B — Opus 4.6 Stability:** Opus 4.6 max driver on Max, 1M context included at standard rates (see above). Fable 5 advisor, Max-bundled. GPT-5.6 Sol xhigh reviewer, separate.
- **Setup C — OpusPlan Hybrid:** **fully Max-bundled.** `opusplan` uses Opus (plan mode) + Sonnet (execute mode), both at their native context windows — no credit drain.
  - **⚠️ Avoid `sonnet[1m]` as a manual pin outside Setup A/C:** if your provider or gateway doesn't resolve Sonnet 5 to its native 1M automatically, forcing a `[1m]`-suffixed pin on an older Sonnet can draw from your usage credits pool ($3/$15 per Mtok) instead of your Max subscription. The `/model` picker shows this explicitly — watch for "Draws from usage credits."
- **Reviewer (GPT-5.6 Sol xhigh) in all three triads:** billed against your OpenAI account, completely separate from Anthropic.
- **CI loops that use `claude -p` post-June-15:** these now bill against the separate Anthropic credit pool, not your Max subscription. The wizard's CI shepherd loops (E2E scoring, weekly-update jobs) are local-only on the maintainer's machine and stay on Max; consumer-repo CI integrations may need to budget the new credit pool.

### Bottom line

If you're using Claude Code interactively (you, in your terminal, doing `/sdlc` work), **all three full-discipline lanes ride your existing Max subscription**, and 1M context (whether Sonnet 5's native window or an explicit `[1m]` alias) doesn't add extra charges on Max/Team/Enterprise. The June 15 split only affects programmatic / headless / CI use of Claude Code.

Watch the headless surface if you've automated `claude -p` calls in your project — those now bill differently as of June 15, 2026.

## Maintainer Override

**Override at any time.** A blanket setup choice doesn't replace judgment per change. If you're touching CI but the change is a one-line typo, Setup C is fine. If you're touching docs but the section is the wizard's safety-critical hook ordering, Setup A or B is the call.

The wizard does not enforce setup lane selection — it documents the recommended default per change shape. Whatever ships is your call.

## See Also

- [`CLAUDE_CODE_SDLC_WIZARD.md`](CLAUDE_CODE_SDLC_WIZARD.md) — Full wizard doc, including Stability tier opt-in for the wider model choice
- [`README.md` § Choosing Your Model](README.md#choosing-your-model) — Model selection philosophy
- [`AGENTS.md`](AGENTS.md) — Codex/reviewer guidelines used in all three full-discipline lanes
