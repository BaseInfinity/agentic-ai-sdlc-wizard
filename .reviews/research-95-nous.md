# ROADMAP #95 Research: Nous Research vs SDLC Harness

**Verdict: NO-GO. Different layer of the stack.**

**Date:** 2026-05-04
**Source:** [nousresearch.com](https://nousresearch.com), [github.com/NousResearch](https://github.com/NousResearch)

## Original question

> Evaluate `nousresearch.com` — what are they building, how does it compare to SDLC wizard's approach? Are they doing agent enforcement, testing methodology, or something orthogonal? Competitive analysis.

## What Nous Research actually builds

From their own copy: *"We train world-class open source language models and build infrastructure to coordinate distributed, unbiased training."*

Product surface:

| Product | What it is |
|---------|-----------|
| **Hermes** (Hermes 4 et al.) | Open-weights base / instruct LLMs |
| **Hermes Agent** | Generic agent framework (autonomous task execution) |
| **hermes-agent-self-evolution** | DSPy + GEPA pipeline that evolves the agent's own skills / prompts / code |
| **atropos** | RL environments for collecting + evaluating LLM trajectories |
| **Hermes-Function-Calling** | Function-calling tooling for the Hermes models |
| **Psyche** | Distributed-training network infrastructure |
| **Nous Chat / API Portal / Simulators** | End-user + developer access surfaces |

## Layer-comparison

| Layer | Nous Research owns | SDLC Harness owns |
|-------|--------------------|------------------|
| Pre-training / fine-tuning | ✓ (Hermes models, Psyche) | — |
| RL eval environments | ✓ (atropos) | — |
| Agent framework (model executes tasks) | ✓ (Hermes Agent) | — |
| Agent self-evolution (model rewrites its own prompts/skills) | ✓ (hermes-agent-self-evolution) | — |
| **SDLC process enforcement on a human-driven coding agent** | — | ✓ |
| TDD red-before-green hook | — | ✓ |
| Planning gate / confidence stating | — | ✓ |
| Cross-model adversarial review | — | ✓ |
| CI shepherd loop | — | ✓ |

**They build the engines. We enforce the build pipeline that uses an engine.** No surface overlap.

## "But what about Hermes Agent — isn't that an agent like Claude Code?"

Hermes Agent is an autonomous agent framework — the model loop itself, plus function-calling, plus a self-evolution layer. That's the same layer Claude Code, Codex CLI, and OpenCode occupy. The wizard doesn't compete with any of those — the wizard runs **inside** an agent host and enforces SDLC discipline on what the host does.

If anything, Hermes Agent is a *target* for the wizard, not a competitor: the OpenCode port (ROADMAP #9) is exactly the play to make the wizard agent-host-agnostic, which would let it run on any OpenAI-compat backend including Hermes via Nous's API portal. That work is already tracked.

`hermes-agent-self-evolution` is interesting (model-driven self-improvement of skills/prompts/code) but it operates at the agent's *own* layer — the agent rewrites itself. Our self-evolution loop operates at the *process* layer — the harness rewrites the wizard. Conceptually parallel, mechanically separate.

## Pattern repeat — what this looks like next to prior NO-GOs

This is the fourth external-methodology audit to land NO-GO:

| # | Audit | Verdict | Reason |
|---|-------|---------|--------|
| #76 | Promptfoo | NO-GO | Already implements Promptfoo's best patterns; no statistical layer |
| #77 | Constrain-to-Playbook | NO-GO | Already constrained on the prompts where it helps; PR review is open-ended on purpose |
| #235 | Thoughtworks AI Evals | NO-GO | Methodology-only article; every layer already has an analog in our pipeline |
| #95 | Nous Research | NO-GO (this) | Different layer of the stack — model R&D vs process enforcement |

Pattern: external audits keep validating that the wizard is mature in its niche. Revisit only when an external source surfaces a *specific technique* we don't already have, not when it surfaces a different *product*.

## Action

- Mark ROADMAP #95 as DONE pointing at this research doc.
- No code changes.
- Keep an eye on the OpenCode port (#9) — that's the right vehicle if anyone ever asks "can the wizard run against Hermes / a self-hosted Nous endpoint?" The answer becomes "yes, via OpenCode."
