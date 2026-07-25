# AI Setup Lanes

Four recommended AI coding setups for this repo. Setups A, B, and C are complete triads: **planner → driver → reviewer**. Setup D is a lightweight driver-only lane for operational grunt work.

This is **guidance, not a hard rule**. Maintainer override is always allowed.

## Setup A — Opus 5 + Fable Advisor (Recommended default, trial-flagged)

**Default for genuine autonomous/agentic work on complex repos, trial-flagged not settled.** Opus 5 launched 2026-07-24; every capability claim behind this trial is Anthropic's own launch-day material, unreplicated by field data (confidence ~70%, not higher — see `project_opus5_launch_research` memory). Maintainer explicitly chose to adopt Opus 5 as default ahead of the 1-2 week field-data window this research recommended, judging the risk acceptable given Codex still gates every task and rollback is one settings change — an accepted-risk decision, not a refutation of the underlying uncertainty. Requires Claude Code v2.1.219+ (`claude update`) for the `opus` alias to resolve to Opus 5 — on older versions it still resolves to Opus 4.8. **Common gotcha:** a stale `ANTHROPIC_DEFAULT_OPUS_MODEL` env var (e.g. in `~/.zshrc`) silently pins an older Opus version and overrides `/model` picker choices — check your shell rc files if `/model opus` doesn't show Opus 5.

| Role | Model | Effort |
|------|-------|--------|
| **Advisor** | Fable 5 (via `advisorModel: "fable"`) — **currently server-side disabled** ("temporarily unavailable" pending an Anthropic rollout, confirmed 2026-07-24 per `code.claude.com/docs/en/advisor`). **On `advisor()` failure, immediately fall back to a Fable subagent call** (`Agent({model: "fable", effort: "xhigh"})`) — do not wait or retry, go straight to the fallback every time. | `high` (server-side); subagent fallback explicit `xhigh` |
| **Driver** | Opus 5 (`claude-opus-5`, via the `opus` alias) | `xhigh` — Anthropic's own recommendation for "difficult tasks and long-running asynchronous workflows," which is Setup A's target use case, not `high`'s routine-work default |
| **Reviewer** | Codex (GPT-5.6 Sol) xhigh | Still gates every task at the end — unaffected by the driver/advisor change |
| **Escalation** | `max` only as a last resort (marginal gains, doubles cost — not the default escalation path); Opus 4.8 pinned explicitly (`claude-opus-4-8`) as a secondary check when Opus-5-driver + Opus-5-fallback-advisor would otherwise be a same-family self-check | Stuck (2 failed attempts / LOW confidence) or high-stakes |

**Effort mechanics — read this before assuming "set and forget."** The effort *tier* (low/medium/high/xhigh/max) is a static per-session setting — Claude Code never auto-switches tiers based on task difficulty; changing tiers still requires an explicit `/effort`. Setup A starts at `xhigh` already — Anthropic's own launch guidance recommends "extra" (`xhigh`) specifically "for difficult tasks and long-running asynchronous workflows," which is Setup A's target use case, not the `high` tier meant for routine work. What Opus 5 *does* have on top of that is documented **adaptive reasoning within a fixed tier**: at whatever tier you're on, it modulates how much it thinks per step (deeper on hard sub-problems, lighter on easy ones) without any manual intervention. Don't conflate the two — "effort scales with complexity" is only true within a tier, not across tiers.

**Fallback lane (Sonnet 5 medium) — restore if the Opus 5 trial doesn't pan out:**

| Role | Model | Effort |
|------|-------|--------|
| **Advisor** | Fable 5 (via `advisorModel: "fable"`) | `high` (server-side) |
| **Driver** | Sonnet 5 (`claude-sonnet-5`) | `medium` default, escalate `high` → `xhigh` for hard tasks |
| **Reviewer** | Codex (GPT-5.6 Sol) xhigh | — |
| **Escalation** | Opus 4.8 xhigh takes over as driver (or run a Fable 5 review pass) | When stuck (2 failed attempts / LOW confidence) or high-stakes |

Sonnet 5 medium remains a fine default for less complex repos — see Setup B below. It's demoted from Setup A's primary slot here specifically because the maintainer's own workload is dominated by complex, agentic-heavy repos where Opus 5's extra capability is worth the cost; that's a workload-specific call, not a universal verdict that Sonnet 5 medium is inferior.

**Advisor failure has a fallback, not a shrug.** `advisor()` is a server-side tool and can fail (currently: Fable is disabled as an advisor repo-wide via an Anthropic rollout, not an incident). When it errors, spawn a Fable subagent as the fallback reviewer — the same rule the `/sdlc` skill carries ("if down, spawn Fable subagent at `xhigh`"). The advisor check is never skipped; only its transport changes.

**Requires:** Claude Code v2.1.219+ (Opus 5 alias resolution), Fable 5 access for advisor/subagent fallback.

## Setup B — Sonnet 5 Simple/One-Off (Legacy Flagship slot repurposed)

**For one-off tasks, scripts, and less complex repos — not the main workflow.** Where Setup A is the default for genuine autonomous agentic work, Setup B is for lower-stakes, lower-complexity work where Sonnet 5's speed and cost outweigh Opus 5's extra capability.

| Role | Model | Effort |
|------|-------|--------|
| **Advisor** | Fable 5 (via `advisorModel: "fable"`) — same server-side-disabled caveat as Setup A; fall back to a Fable subagent at `xhigh` on failure | `high` (server-side); subagent fallback explicit `xhigh` |
| **Driver** | Sonnet 5 (`claude-sonnet-5`) | `medium` default, escalate `high` → `xhigh` for tasks that turn out harder than expected |
| **Reviewer** | Codex (GPT-5.6 Sol) xhigh | — |

Choose this lane deliberately for scope, not by default — a one-off script, a small doc fix, a low-blast-radius repo. If a Setup B task turns out to need real agentic depth, swap to Setup A rather than cranking Sonnet 5's effort past `xhigh`; that's a model swap, not an effort-tier problem.

**Effort escalation ladder:** Start at `medium` — CodeRabbit's testing found it captures most of Sonnet 5's upside at the lowest cost. Raise to `high` when medium struggles, `xhigh` for hard debugging, multi-file migrations, or long agent runs. `max` is rarely worth it — doubles cost for marginal gains per the same CodeRabbit testing.

**Opus 4.6/4.8 remain reachable as the field-proven stability/escalation backstop** for installer, release, or other high-blast-radius work regardless of which lane you're in — months of field data, Active through at least Feb 2027. Pin `claude-opus-4-8` explicitly rather than relying on the `opus` alias, which now resolves to Opus 5. **Opus 4.6 is the only Opus where `max` effort works without overthinking** — community reports confirm this is the sweet spot specific to 4.6 (no xhigh support on 4.6 — only low/medium/high/max); pin `claude-opus-4-6` explicitly when you want that specific consistency profile over Opus 5 or 4.8.

## Setup C — OpusPlan Hybrid (Saver)

| Role | Model | Effort |
|------|-------|--------|
| **Planner** | Opus 5 (via Plan Mode — Shift+Tab, follows the `opus` alias) | `xhigh` |
| **Advisor** | Fable 5 or Opus 5 (via `advisorModel`) | — |
| **Driver** | Sonnet 5 (auto execute mode) | `medium`, escalate `high` for hard runs |
| **Reviewer** | Codex (GPT-5.6 Sol) xhigh | — |

Cost-efficient hybrid using CC's native `opusplan` alias. `opusplan` follows the `opus` alias for its planning phase — currently Opus 5 — and executes with Sonnet. Max-bundled — no API credit drain. Pin `model: "opusplan"` + `advisorModel: "fable"` in project settings. Sonnet 5 now uses 1M context natively (no `[1m]` suffix needed). GPT-5.6 Sol xhigh is the cross-model reviewer.

**Note:** Opus 4.6 cannot advise Sonnet 5 (rejected in the advisor pairing table). Use Fable 5 or Opus 5 as advisor for this lane. Pin `claude-opus-4-8` explicitly (not the `opus` alias) if you specifically want Opus 4.8's field-proven planning behavior instead of Opus 5's.

## Setup D — Claude Lite

| Role | Model | Effort | Notes |
|------|-------|--------|-------|
| **Planner** | You (the user) | — | Task is pre-planned, no model reasoning needed |
| **Driver** | Sonnet 5 | `medium` | Max-bundled, ≈ Sonnet 4.6 at high quality |
| **Reviewer** | None | — | Blast radius too low for cross-model overhead |

The "just do the thing" lane. No TDD enforcement, no cross-model review, no planning phase. You already know what to do — you just need a fast, cheap pair of hands.

## When to Use Setup A

The default for genuine autonomous/agentic work on complex repos — full discipline (TDD, cross-model review) with Opus 5's extra capability at higher quota cost than Setup B (see Credit-Spend Warning below):

- Architecture or methodology changes
- Complex multi-file features or refactors
- Ambiguous debugging, root-cause investigation
- Installer behavior (`cli/`, `init`, `claude-setup-wizard`)
- CI / release automation
- Security-sensitive behavior
- Anything that could damage a consumer repo
- Any task where you'd otherwise reach for Setup B and find yourself needing more than one or two escalation rounds

## When to Use Setup B

Reach for Setup B for one-off tasks, scripts, and lower-stakes/lower-complexity repos where Sonnet 5's speed and cost outweigh Opus 5's extra capability:

- Feature implementation on well-understood, routine work
- Documentation and examples
- Test writing
- Normal CLI changes
- Mechanical refactors
- Small, low-blast-radius scripts or one-off tasks
- Anything where the task is clearly scoped and doesn't need Opus 5's deeper agentic reasoning

If a Setup B task turns out to need more depth than expected, swap to Setup A rather than cranking Sonnet 5's effort past `xhigh` — that's a model swap, not an effort-tier problem.

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
- Deploy to staging (prod deploys need Setup A's or B's discipline — human gate + rollback plan; Setup A for anything complex/high-stakes, Setup B for simple ones)
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
- No effort escalation (Sonnet 5 medium is plenty)

**The discipline of knowing when NOT to use discipline.** Documenting this lane tells users "here's when to switch off the heavy methodology" rather than silently tempting them to skip it. If the task turns out to be harder than expected, escalate to Setup A or B.

## Final Review Policy

**Setups A, B, and C end at GPT-5.6 Sol xhigh as the cross-model reviewer.** Claude can't grade its own homework — the reviewer always belongs to a different lab with different blind spots. See [CLAUDE_CODE_SDLC_WIZARD.md → "Cross-Model Review (Codex)"](CLAUDE_CODE_SDLC_WIZARD.md) for the handoff protocol.

**Setup D has no reviewer** — the blast radius doesn't justify it. If you're unsure whether a task is truly Lite, it probably isn't. Escalate.

If GPT-5.6 Sol isn't available on your OpenAI account, Codex auto-falls back to Terra — still keep `model_reasoning_effort="xhigh"`. Lower reasoning misses subtle bugs that the reviewer is the last gate to catch.

**Escalation for unusually risky PRs:** `xhigh` is the evidence-based default — OpenAI's own migration guidance is to preserve the prior effort baseline, and no published data shows `max` or Pro mode catching meaningfully more real bugs than `xhigh` on ordinary PR review. For a PR you'd genuinely lose sleep over (security-sensitive, high blast radius, touches the installer or a consumer-facing template), escalate the reviewer to `max` or Pro mode — a once-per-PR gate is exactly the kind of low-frequency, high-stakes call site where the extra cost is easiest to justify. Don't make it the default.

## Version Requirement

Opus 5 (Setup A's driver) requires **Claude Code v2.1.219+**. `advisorModel` in settings.json requires **v2.1.170+**. Check your version with `claude --version`. If below v2.1.219, update from inside a CC session:

```
! claude update
```

The `!` prefix runs shell commands inside your CC session — no need to exit and re-enter. After updating, restart the session to pick up the new alias resolution. **Also check for a stale `ANTHROPIC_DEFAULT_OPUS_MODEL` env var** (e.g. in `~/.zshrc`) — if set to an older Opus version, it silently overrides `/model opus` picker choices and prevents Opus 5 from resolving even after updating.

Fable 5 as advisor also requires Fable 5 access for your organization/plan.

## When the Advisor Is Unavailable

**As of 2026-07-24, Fable-as-advisor is server-side disabled for everyone**, confirmed per `code.claude.com/docs/en/advisor`: "Claude Code doesn't offer Fable 5 as the advisor... A remotely configured rollout controls when Fable 5 returns as an advisor option." This is a deliberate Anthropic gate, not an incident — no session restart, `/clear`, or waiting fixes it. Periodically re-check the docs page for rollout status; don't assume this is permanent or assume it's still true indefinitely without re-checking.

**Step 1 — skip the restart, go straight to the fallback.** Unlike a transient API incident, no session restart, `/clear`, or wait fixes a rollout-gated block — spawn a Fable subagent as the fallback reviewer immediately, explicit `effort: "xhigh"` (per this repo's own `/sdlc` skill: "if down, spawn Fable subagent at `xhigh`"). Batch your plan or open questions into one subagent consult at each point where you'd have called `advisor()`. Runs interactively on your Max subscription like any other agent.

**Step 2 — keep driving with your lane's model.** `/model opus` for Setup A, `/model sonnet` for Setup B. The subagent replaces the advisor's transport; the Codex xhigh PR gate remains the separate final backstop, not a substitute for the advisor check.

**Step 3 (last resort, scripted/CI only):**

- `claude --model fable --effort high -p "$(cat <file>)"` — headless mode bills API credits, not your Max subscription.

Whichever path you use, the cross-model PR review gate still applies.

## Credit-Spend Warning

**Setup A (Opus 5 as driver) burns the 5-hour cap faster than Setup B** — Opus 5 driving implementation at `xhigh` is the more expensive path; Sonnet 5 at `medium`/`high` (Setup B) generally uses less quota for comparable-scope work (the advantage narrows at `xhigh` — more turns per task plus tokenizer overhead). If you're hitting the cap mid-session on Setup A:

- Drop to Setup B (Sonnet 5) for the remainder of the day, or for the rest of a task that turns out simpler than expected
- Or drop to Setup D for grunt work that doesn't need deep reasoning
- Or use Sonnet directly for the final mechanical edits, then run the GPT-5.6 Sol reviewer over the whole diff at the end

**Setup D uses Sonnet** — same model as Setup B's driver, Max-bundled. One less model to manage if you're already reaching for Setup B for lighter work.

The reviewer (GPT-5.6 Sol xhigh) is billed against your OpenAI account, separately. Watch both bills.

## Autocompact Thresholds

For recommended `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` values per context window and task shape, see [CLAUDE_CODE_SDLC_WIZARD.md → Autocompact Tuning](CLAUDE_CODE_SDLC_WIZARD.md#autocompact-tuning). Sonnet 5 (Setup B, D) has its own native ~967K-token proactive-compaction default at 1M context — don't carry over Opus-era 1M threshold guidance unexamined.

## How Billing Works — 1M Context, Max Plan, and the June 15 Split

A common question: **"does the `[1m]` model alias get billed differently? Does it pull from my Max plan or from API credits?"**

The short answer: **all four lanes are fully Max-bundled in interactive sessions** — Setup A (Opus 5), Setup B (Sonnet 5, native 1M), Setup C (opusplan, Opus plan-mode + Sonnet execute), and Setup D (Sonnet). Here's the detail.

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

- **Setup A — Opus 5 + Fable advisor (fallback subagent):** Opus 5 driver on Max, 1M context included at standard rates (see above). Fable 5 advisor server-side disabled currently — Fable subagent fallback also Max-bundled. GPT-5.6 Sol xhigh reviewer, separate. Higher Max quota consumption than Setup B at the `xhigh` default.
- **Setup B — Sonnet 5 Simple/One-Off:** Sonnet 5's native 1M context — interactive session, Max-bundled, no `[1m]` suffix needed. Fable 5 advisor (fallback subagent) — also Max-bundled. GPT-5.6 Sol xhigh reviewer on ChatGPT subscription. Generally lower Max quota consumption than Setup A at the `medium` default (savings shrink at higher effort).
- **Setup C — OpusPlan Hybrid:** **fully Max-bundled.** `opusplan` uses Opus (plan mode, now Opus 5) + Sonnet (execute mode), both at their native context windows — no credit drain.
  - **⚠️ Avoid `sonnet[1m]` as a manual pin outside Setup B/C:** if your provider or gateway doesn't resolve Sonnet 5 to its native 1M automatically, forcing a `[1m]`-suffixed pin on an older Sonnet can draw from your usage credits pool ($3/$15 per Mtok) instead of your Max subscription. The `/model` picker shows this explicitly — watch for "Draws from usage credits."
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
