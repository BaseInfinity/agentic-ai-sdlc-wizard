# ROADMAP #99 Research: AutoGPT vs SDLC Harness

**Verdict: NO-GO. Different layer, different audience, no fitting primitive.**

**Date:** 2026-05-04
**Source:** [github.com/Significant-Gravitas/AutoGPT](https://github.com/Significant-Gravitas/AutoGPT) (184k stars, 102 releases, latest 2026-04-29 — actively maintained)

## Original question

> Evaluate adding SDLC wizard (or ADLC variant) to AutoGPT ecosystem. Can our enforcement patterns translate to AutoGPT's agent framework? Is this an SDLC wizard port or an ADLC wizard use case? Assess: (a) AutoGPT's plugin/extension model, (b) hook equivalents, (c) community size and adoption potential, (d) whether this fits better as SDLC wizard adapter or a separate \*DLC variant.

## What AutoGPT actually is in 2026

Not the same project the original ROADMAP item assumed. AutoGPT pivoted from "autonomous task agent" to **"agent platform/framework"** — *"build, deploy, and manage continuous AI agents that automate complex workflows."* (Quote from project page.) The current shape:

| Surface | What it is |
|---------|-----------|
| **AutoGPT Platform** | Hosted/self-hostable runtime for building + deploying long-running agents |
| **Blocks** | Composable workflow building blocks (their "plugin" equivalent — pre-configured agent steps that compose into a bigger agent) |
| **Marketplace** | Discovery surface for agents + blocks |
| **`agbenchmark`** | Autonomous-performance benchmark harness (testing agent output quality on canned tasks) |

Stack: Python 69% + TypeScript 29%.

## Why this isn't a fit for the wizard's port pattern

### (a) Layer mismatch — same as Nous (#95) for a different reason

AutoGPT is an **agent host** — it runs *the agent itself*. So is Claude Code. So is Codex CLI. So is OpenCode. The wizard ports across agent hosts (`claude-sdlc-wizard`, `codex-sdlc-wizard`, `claude-gdlc-wizard`, the upcoming `opencode-sdlc-wizard`).

In principle AutoGPT could be a fifth port target — an `autogpt-sdlc-wizard` sibling. But:

### (b) No hook primitive that maps

Claude Code, Codex, and OpenCode all expose **pre-tool-execution hooks** as a first-class primitive. The wizard's TDD-enforcement (`tdd-pretool-check.sh`, `precompact-seam-check.sh`) and prompt-time injection (`sdlc-prompt-check.sh`) need that primitive to work — without "fire this script before the agent writes a file," there's no place for the SDLC gate to live.

AutoGPT's **blocks** system is a workflow-composition primitive. A block is a unit of work the agent executes, not a hook around an arbitrary tool call. The closest analog would be wrapping every code-mutating block in a pre-block validator — but that requires authoring a custom AutoGPT runtime patch, not a plugin/extension. There's no published equivalent of Claude Code's `Hooks` config, Codex's `~/.codex/hooks/`, or OpenCode's `tool.execute.before` event.

`agbenchmark` is a *benchmarking* harness — it measures whether the agent's output passes canned tasks. That's the same layer as our `tests/e2e/` scoring pipeline. **Not** the same layer as our pre-tool-call enforcement.

### (c) Audience mismatch

AutoGPT's primary users are **agent builders** — people composing autonomous workflows that run as continuous services. The wizard's primary users are **SWEs in interactive coding sessions** who want their agent to plan/TDD/self-review the SWE work the human is supervising. Different problem.

If an agent builder *wanted* SDLC enforcement on the SWE work an autonomous AutoGPT agent generates, the right layering would be:

- AutoGPT agent runs in headless mode invoking Claude Code / Codex CLI / OpenCode as a sub-tool
- That sub-invocation inherits our wizard's enforcement
- AutoGPT itself stays at the orchestration layer — no port required

That layering already works today via existing siblings. No AutoGPT port adds anything.

### (d) Adapter vs separate \*DLC

A separate ADLC ("Agent Development Life Cycle") variant for AutoGPT-style continuous-agent builds is conceivable, but it would be **a different product** from this wizard:

- ADLC scope = does the agent's continuous workflow have proper observability, recovery from failure, drift detection, tool budget caps, runaway-loop guards
- SDLC scope (this wizard) = does the agent plan/TDD/self-review while writing code

These don't compose; they're orthogonal. ADLC for AutoGPT would be a fresh project, not a port.

## Pattern repeat

This is the fifth external-product audit to land NO-GO:

| # | Audit | Verdict | Reason |
|---|-------|---------|--------|
| #76 | Promptfoo | NO-GO | Already implements its best patterns; missing only the part we don't need |
| #77 | Constrain-to-Playbook | NO-GO | Already constrained where it helps |
| #235 | Thoughtworks AI Evals | NO-GO | Methodology-only article; every layer already implemented |
| #95 | Nous Research | NO-GO | Different layer (model R&D, not process enforcement) |
| #99 | AutoGPT | NO-GO (this) | Different layer + audience + no hook primitive |

## Action

- Mark ROADMAP #99 as DONE pointing at this research doc.
- No code changes.
- If a real demand signal ever surfaces ("I run AutoGPT in continuous mode and want SDLC discipline on the code it writes"), the right answer is "have your AutoGPT agent invoke Claude Code as a sub-tool" — that gets our wizard for free without an AutoGPT port.
