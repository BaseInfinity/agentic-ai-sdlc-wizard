# Claude Code SDLC Wizard

A **self-evolving Software Development Life Cycle (SDLC) enforcement system for AI coding agents**. Makes Claude plan before coding, test before shipping, and ask when uncertain. Measures itself getting better over time.

**Built on 15+ years of software engineering and founding engineering experience** — battle-tested patterns from real production systems, baked into an AI agent that follows tried-and-true software quality practices so you don't have to enforce them manually.

> **Built for Claude Code.** Using OpenAI's Codex CLI instead? Check out [`codex-sdlc-wizard`](https://github.com/BaseInfinity/codex-sdlc-wizard). Need privacy-first / any-backend (local Ollama, Azure OpenAI, hosted OSS)? See [`opencode-sdlc-wizard`](https://github.com/BaseInfinity/opencode-sdlc-wizard). ([Full ecosystem](#xdlc-ecosystem-sibling-projects).)

## Install

**Requires [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)** (Anthropic's CLI for Claude).

Run from your terminal or from inside Claude Code (`!` prefix):
```bash
npx -y agentic-sdlc-wizard@latest init
```
The `@latest` pin forces npm to fetch the newest version. Without it, `npx` may serve a stale CLI from your local cache (#358); `init` also nudges if it detects a gap.
Then start (or restart) Claude Code — type `/exit` then `claude` to reload hooks. Setup auto-invokes on first prompt — Claude reads the wizard doc, scans your project, and generates bespoke CLAUDE.md, SDLC.md, TESTING.md, and ARCHITECTURE.md. No manual commands needed.

<details>
<summary>Alternative install methods</summary>

**curl (no npm install needed):**
```bash
curl -fsSL https://raw.githubusercontent.com/BaseInfinity/claude-sdlc-wizard/main/install.sh | bash
```

**Homebrew:**
```bash
brew install BaseInfinity/sdlc-wizard/sdlc-wizard
sdlc-wizard init
```

**GitHub CLI extension:**
```bash
gh extension install BaseInfinity/gh-sdlc-wizard
gh sdlc-wizard init
```

**From GitHub (no npm registry needed):**
```bash
npx github:BaseInfinity/claude-sdlc-wizard init
```

**Install CLI globally:**
```bash
npm install -g agentic-sdlc-wizard
sdlc-wizard init
```

**Manual (advanced — escape hatch only):** Download `CLAUDE_CODE_SDLC_WIZARD.md` to your project and tell Claude `Run the SDLC wizard setup`. This skips the live-session auto-invoke and is only intended for environments where `npx`, `curl`, `brew`, and `gh` are all unavailable. The default human path is `npx init` → restart CC → first-prompt auto-setup, not this manual flow.
</details>

<details>
<summary>Health check & updates</summary>

```bash
npx agentic-sdlc-wizard check        # Human-readable
npx agentic-sdlc-wizard check --json  # Machine-readable (CI-friendly)
```

Reports MATCH / CUSTOMIZED / MISSING / DRIFT for every installed file. Exits non-zero on MISSING or DRIFT — use in CI to catch setup regressions.

**Check for content updates:** Tell Claude `Check if the SDLC wizard has updates` — it reads [CHANGELOG.md](CHANGELOG.md), shows what's new, and offers to apply changes.
</details>

## Why Use This

You want Claude Code to follow engineering discipline automatically:
- **Plan before coding** (not guess-and-check)
- **Write tests first** (TDD enforced via hooks)
- **State confidence** (LOW = ask user, don't guess)
- **Track work visibly** (TaskCreate)
- **Self-review before presenting**
- **Prove it's better** (use native features unless you prove custom wins)

The wizard auto-detects your stack (package.json, test framework, deployment targets) and generates bespoke hooks + skills + docs. CI validates the generated assets; cross-stack setup-path E2E is on the [roadmap](ROADMAP.md).

## What This Actually Is

Five layers working together:

```
Layer 5: SELF-IMPROVEMENT
  Weekly/monthly workflows detect changes, test them
  statistically, create PRs. Baselines evolve organically.

Layer 4: STATISTICAL VALIDATION
  E2E scoring with 95% CI (5 trials, t-distribution).
  SDP normalizes for model quality. CUSUM catches drift.

Layer 3: SCORING ENGINE
  Multi-criteria scoring, 10/11 points. Claude evaluates Claude.
  Before/after wizard A/B comparison in CI.

Layer 2: ENFORCEMENT
  Hooks fire every interaction (~100 tokens).
  PreToolUse reminds Claude to write tests first.

Layer 1: PHILOSOPHY
  The wizard document. KISS. TDD. Confidence levels.
  Copy it, run setup, get a bespoke SDLC.
```

## What Makes This Different

| Capability | What It Does |
|---|---|
| **E2E scoring in CI** | Every PR gets an automated SDLC compliance score (0-10) — measures whether Claude actually planned, tested, and reviewed |
| **Before/after A/B testing** | Compares wizard changes against a baseline with 95% confidence intervals to prove improvements aren't noise |
| **SDP normalization** | Separates "the model had a bad day" from "our SDLC broke" by cross-referencing external benchmarks |
| **CUSUM drift detection** | Catches gradual quality decay over time — borrowed from manufacturing quality control |
| **Pre-tool TDD hooks** | Before source edits, a hook reminds Claude to write tests first. CI scoring checks whether it actually followed TDD |
| **Self-evolving loop** | Weekly/monthly external research + local CI shepherd loop — you approve, the system gets better |

## Optional: Cross-Model Review (Codex)

Claude can't grade its own homework. Have a **different AI from a different company** review Claude's work — different training, different blind spots, different biases. We use OpenAI's Codex CLI, and it's **three commands to set up**:

```bash
npm i -g @openai/codex
export OPENAI_API_KEY=sk-...
codex --version   # confirm ready
```

That's it. Codex picks up your OpenAI account's best available model automatically — **if you have GPT-5.5, it uses GPT-5.5; otherwise GPT-5.4**. No model config needed.

**How to use it:** after Claude's self-review passes, write a one-file mission brief and run:

```bash
codex exec -c 'model_reasoning_effort="xhigh"' -s danger-full-access \
  -o .reviews/latest-review.md \
  "Read .reviews/handoff.json and review per the checklist. Output findings + CERTIFIED or NOT CERTIFIED." \
  < /dev/null
```

**Always append `< /dev/null`** when running `codex exec` from a non-interactive parent (background, hooks, CI, Claude Code Bash tool). Without it, codex blocks on stdin reads even when the prompt is an argument — the process sits at S/0% CPU indefinitely with a 0-byte `-o` output file. Validated on codex-cli 0.130.0 / macOS 14, 2026-05-15.

`xhigh` reasoning is **non-negotiable** — lower settings miss subtle bugs. See [CLAUDE_CODE_SDLC_WIZARD.md](CLAUDE_CODE_SDLC_WIZARD.md#cross-model-review-loop-optional) for the full protocol (handoff format, round-2 dialogue loop, preflight docs). Real-world: this catches P0/P1 issues in 2-3 out of 10 reviews that Claude's self-review rated as clean.

## Choosing Your Model

The wizard ships a **default recommendation**, not a mandate. You can swap to any Claude model — newer, older, or sibling tier — at any time. `/model` per session, or pin in `.claude/settings.json`.

**Default: Opus 4.8 at max effort** (`[f] Flagship` in the setup wizard). Matches Anthropic's current flagship; unlocks 4.8's SWE-Bench Pro / Terminal-Bench 2.1 / dynamic-workflow gains. If you're starting fresh, this is the right pick.

**Alternative tier: Opus 4.6 at max effort** (`[s] Stability`, added v1.79.0). Some maintainers — including the wizard author — hit 4.7/4.8 regressions in production that 4.6 simply doesn't have: false-greens ([anthropics/claude-code#63861](https://github.com/anthropics/claude-code/issues/63861)), 2-3× token burn ([#64961](https://github.com/anthropics/claude-code/issues/64961)), dropped constraints during execution ([#65932](https://github.com/anthropics/claude-code/issues/65932)), fabricated identifiers under parallel tool batches. Field signal converges on **4.6 being the only Opus where `max` effort doesn't overthink** — Andon Labs Vending-Bench arena (4.8 finished last), [Paweł Huryn's 4.7 guide](https://www.productcompass.pm/p/claude-opus-4-7-guide) ("most complaints about 4.7 feeling slow stem from people reflexively using max"), r/Claudeopus field reports (one maintainer: "12 hours with 4.8 zero deliverables; plugged in 4.6, 133 tests green in one session"). 4.6 is Anthropic-supported until ≥ Feb 5, 2027 per the [official deprecation page](https://platform.claude.com/docs/en/about-claude/model-deprecations) — 8 months minimum runway.

**The wizard's stance: aim for stability.** Default to what works reliably in your hands, not what's newest. If 4.8 ships well for your workflow, stay on flagship. If you've hit the regressions, the Stability tier is one setup-wizard choice (`[s]`) and reversion is two lines in `~/.claude/settings.json`. See [CLAUDE_CODE_SDLC_WIZARD.md → "Stability tier — Opus 4.6 at max effort"](CLAUDE_CODE_SDLC_WIZARD.md) for the full pick-list and tradeoffs.

**Switch any time:**

```bash
/model claude-opus-4-8[1m]   # flagship default
/model claude-opus-4-6[1m]   # stability tier
/model opus[1m]              # whatever the wizard's recommendation resolves to
```

Or pin in `.claude/settings.json`:

```json
{ "model": "claude-opus-4-6[1m]" }
```

Or sweep all your projects from one place by setting `ANTHROPIC_DEFAULT_OPUS_MODEL` in `~/.claude/settings.json` — the `opus[1m]` alias resolves through it, so flipping one env var switches every repo at once.

Effort tuning is independent of model choice. `max` is the wizard's default; `xhigh` is the floor. Adjust per session with `/effort max`. The Stability tier is specifically a **`max`-effort tier** because that's the field-validated sweet spot for 4.6 — at the cost of giving up 4.8's newer benchmark wins.

## How It Works

**Think Iron Man:** Jarvis is nothing without Tony Stark. Tony Stark is still Tony Stark. But together? They make Iron Man. This SDLC is your suit - you build it over time, improve it for your needs, and it makes you both better.

**The dream:** Mold an ever-evolving SDLC to your needs. Replace my components with native Claude Code features as they ship — and one day, delete this repo entirely because Claude Code has them all built in. That's the goal.

```
WIZARD FILE (CLAUDE_CODE_SDLC_WIZARD.md)
  - Setup guide, used once
  - Lives on GitHub, fetched when needed
        |
        | generates
        v
GENERATED FILES (in your repo)
  - .claude/hooks/*.sh
  - .claude/skills/*/SKILL.md
  - .claude/settings.json
  - CLAUDE.md, SDLC.md, TESTING.md, ARCHITECTURE.md
        |
        | validated by
        v
CI/CD PIPELINE
  - E2E: simulate SDLC task -> score 0-10
  - Before/after: main vs PR wizard
  - Statistical: 5x trials, 95% CI
  - Model-aware: SDP adjusts for external conditions
```

## Self-Evolving System

| Cadence | Source | Action |
|---------|--------|--------|
| Weekly | Claude Code releases | PR with analysis + E2E test |
| Weekly | Community (Reddit, HN) | Issue digest |
| Monthly | Deep research, papers | Trend report |

Every update: regression tested -> AI reviewed -> human approved.

## E2E Scoring

Like evaluating scientific method adherence - we measure **process compliance**:

| Criterion | Points | Type |
|-----------|--------|------|
| TodoWrite/TaskCreate | 1 | Deterministic |
| Confidence stated | 1 | Deterministic |
| Plan mode | 2 | AI-judge |
| TDD RED | 2 | Deterministic |
| TDD GREEN | 2 | AI-judge |
| Self-review | 1 | AI-judge |
| Clean code | 1 | AI-judge |

40% deterministic + 60% AI-judged. 5 trials handle variance.

## Model-Adjusted Scoring (SDP)

| Metric | Meaning |
|--------|---------|
| **Raw** | Actual score (Layer 2: SDLC compliance) |
| **SDP** | Adjusted for model conditions |
| **Robustness** | How well SDLC holds up vs model changes |

- **Robustness < 1.0** = SDLC is resilient (good!)
- **Robustness > 1.0** = SDLC is sensitive (investigate)

## Tests Are The Building Blocks

Tests aren't just validation - they're the foundation everything else builds on.

- **Tests >= App Code** - Critique tests as hard (or harder) than implementation
- **Tests prove correctness** - Without them, you're just hoping
- **Tests enable fearless change** - Refactor confidently

## Official Plugin Integration

| Plugin | Purpose | Scope |
|--------|---------|-------|
| `claude-md-management` | **Required** - CLAUDE.md maintenance | CLAUDE.md only |
| `claude-code-setup` | Recommends automations | Recommendations |
| `code-review` | Local self-review and PR review (optional) | Local + PRs |

## Prove It's Better

Don't reinvent the wheel. Use native/built-in features UNLESS you prove your custom version is better. If you can't prove it, delete yours.

1. Test the native solution — measure quality, speed, reliability
2. Test your custom solution — same scenario, same metrics
3. Compare side-by-side
4. Native >= custom? **Use native. Delete yours.**
5. Custom > native? **Keep yours. Document WHY.** Re-evaluate when native improves.

This applies to everything: native commands vs custom skills, framework utilities vs hand-rolled code, library functions vs custom implementations.

## How This Compares

This isn't the only Claude Code SDLC tool. Here's an honest comparison:

| Aspect | SDLC Wizard | everything-claude-code | claude-sdlc |
|--------|------------|----------------------|-------------|
| **Focus** | SDLC enforcement + measurement | Agent performance optimization | Plugin marketplace |
| **Hooks** | 3 (SDLC, TDD, instructions) | 12+ (dev blocker, prettier, etc.) | Webhook watcher |
| **Skills** | 4 (/sdlc, /setup, /update, /feedback) | 80+ domain-specific | 13 slash commands |
| **Evaluation** | 95% CI, CUSUM, SDP, Tier 1/2 | Configuration testing | skilltest framework |
| **CI Shepherd** | Local CI fix loop | No | No |
| **Auto-updates** | Weekly CC + community scan | No | No |
| **Install** | `npx -y agentic-sdlc-wizard@latest init` | npm install | npm install |
| **Philosophy** | Lightweight, prove-it-or-delete | Scale and optimization | Documentation-first |

**Our unique strengths:** Statistical rigor (CUSUM + 95% CI), SDP scoring (model quality vs SDLC compliance), CI shepherd loop, Prove-It A/B pipeline, comprehensive automated test suite, dogfooding enforcement.

**Where others are stronger:** everything-claude-code has broader language/framework coverage. claude-sdlc has webhook-driven automation. Both have npm distribution.

**The spirit:** Open source — we learn from each other. See [COMPETITIVE_AUDIT.md](COMPETITIVE_AUDIT.md) for details.

## Documentation

| Document | What It Covers |
|----------|---------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design, 5-layer diagram, data flows, file structure |
| [CI_CD.md](CI_CD.md) | All workflows, E2E scoring, tier system, SDP, integrity checks |
| [SDLC.md](SDLC.md) | Version tracking, enforcement rules, SDLC configuration |
| [TESTING.md](TESTING.md) | Testing philosophy, test diamond, TDD approach |
| [CHANGELOG.md](CHANGELOG.md) | Version history, what changed and when |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute, evaluation methodology |

## XDLC Ecosystem (Sibling Projects)

This wizard is one of three published siblings. Same enforcement philosophy, different agent / domain:

| Package | Agent / Domain | What It Does |
|---------|----------------|--------------|
| [`agentic-sdlc-wizard`](https://www.npmjs.com/package/agentic-sdlc-wizard) ([repo](https://github.com/BaseInfinity/claude-sdlc-wizard)) | Claude Code / SDLC | This repo. Plan → TDD → self-review for code, with hooks + skills + CI scoring |
| [`codex-sdlc-wizard`](https://www.npmjs.com/package/codex-sdlc-wizard) ([repo](https://github.com/BaseInfinity/codex-sdlc-wizard)) | OpenAI Codex / SDLC | Same SDLC enforcement, ported to Codex CLI (writes `.codex/` + `AGENTS.md`) |
| [`opencode-sdlc-wizard`](https://www.npmjs.com/package/opencode-sdlc-wizard) ([repo](https://github.com/BaseInfinity/opencode-sdlc-wizard)) | OpenCode / privacy-first | Same SDLC enforcement against ANY backend OpenCode supports — local Ollama, Azure OpenAI, Together, Groq, OpenRouter. Writes `.opencode/` + `AGENTS.md`. |
| [`claude-gdlc-wizard`](https://www.npmjs.com/package/claude-gdlc-wizard) ([repo](https://github.com/BaseInfinity/claude-gdlc-wizard)) | Claude Code / GDLC | Game Development Life Cycle — persona-driven playtest cycles, triangulated findings, ratchet-only-tightens |

All four are part of the broader [XDLC ecosystem](https://github.com/BaseInfinity/xdlc) — generalized lifecycle enforcement across agents and domains.

## Community

<div align="center">

[![Discord](https://img.shields.io/badge/Discord-Automation%20Station-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.com/invite/fGPEF7GHrF)

**[Automation Station](https://discord.com/invite/fGPEF7GHrF)** — a community Discord packed with software engineers bringing 40+ years of combined experience across every area of the stack.

_Frontend · Backend · Infra · Embedded · Data · QA · DevOps_

Share patterns, ask questions, compare notes on AI agents, automation, and SDLC tooling.

</div>

## Contributing

PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for evaluation methodology and testing.

## Feedback

Three ways to report bugs, request features, or ask questions:

- **In-session:** run `/feedback` inside any Claude Code session using this wizard — auto-fills context and redacts secrets before filing
- **Issue templates:** [bug report](https://github.com/BaseInfinity/claude-sdlc-wizard/issues/new?template=bug_report.md), [feature request](https://github.com/BaseInfinity/claude-sdlc-wizard/issues/new?template=feature_request.md), [question](https://github.com/BaseInfinity/claude-sdlc-wizard/issues/new?template=question.md)
- **Discussions:** open-ended conversations at [github.com/BaseInfinity/claude-sdlc-wizard/discussions](https://github.com/BaseInfinity/claude-sdlc-wizard/discussions)
