# Research #58: claw-code, OmO, OmX Patterns

## Summary

Studied three open-source AI coding agent projects for patterns to adopt in SDLC Harness.

As of April 4, 2026:

| Project | Stars | Stack | Key Innovation |
|---------|-------|-------|---------------|
| **claw-code** (`ultraworkers/claw-code`) | ~168K | Rust (9 crates) | GreenContract + PolicyEngine + RecoveryRecipes |
| **oh-my-openagent (OmO)** (`code-yeongyu/oh-my-openagent`) | ~48K | TypeScript/Bun | 11-agent orchestration + 52 hooks + hash-anchored edits |
| **oh-my-codex (OmX)** (`Yeachan-Heo/oh-my-codex`) | ~16K | TypeScript + Rust | `$ralph` persistence loop + `$team` worktree isolation |

---

## claw-code (Rust CC Alternative)

### Architecture

Monorepo Rust workspace with 9 crates: `api`, `commands`, `plugins`, `runtime`, `tools` (40 tools), `telemetry`, `mock-anthropic-service`, `compat-harness`, `rusty-claude-cli`.

### Patterns Worth Adopting

#### 1. GreenContract (Graduated Test Verification)

Four ordered levels instead of binary pass/fail:

| Level | Scope |
|-------|-------|
| `TargetedTests` | Only changed-file tests |
| `Package` | Module/package tests |
| `Workspace` | Full workspace tests |
| `MergeReady` | Full CI including integration |

The lifecycle mapping (when each level is required) is **inferred by us**, not explicit in claw-code's source. The enum defines the levels; how/when to require each is up to the adopter.

**Why this matters**: Our wizard currently treats tests as binary (pass/fail). Graduated levels let us enforce appropriate verification at each stage — you don't need full CI green just to commit a WIP.

#### 2. PolicyEngine (Declarative SDLC Rules)

Composable conditions and actions:
- **Conditions**: `GreenAt { level }`, `StaleBranch`, `ReviewPassed`, `ScopedDiff`, `TimedOut` + `And`/`Or` combinators
- **Actions**: `MergeToDev`, `MergeForward`, `RecoverOnce`, `Escalate`, `Block`, `Notify`, `Chain`

This encodes SDLC rules as executable logic rather than prose. Our wizard relies on CLAUDE.md text and hooks — a policy engine would make enforcement more composable and portable across agents.

#### 3. RecoveryRecipes (Structured Self-Healing)

Seven known failure scenarios with pre-built recovery steps:
- Each scenario has defined steps, max attempts (1 auto, then escalate)
- Escalation policies: `AlertHuman`, `LogAndContinue`, `Abort`

More structured than our ci-self-heal.yml. Each failure type has a specific recipe rather than a generic "Claude, fix it."

#### 4. Hook Input Mutation

Hooks can not only allow/deny but **modify tool inputs** via `updatedInput` in the hook response. Opens patterns like:
- Inject `--dry-run` before destructive git commands
- Add missing test flags to build commands
- Rewrite paths to enforce boundaries

CC hooks can't do this — they're allow/deny only.

#### 5. TaskPacket (Structured Task Contract)

Formal contract for autonomous work: `objective`, `scope`, `repo`, `branch_policy`, `acceptance_tests`, `commit_policy`, `reporting_contract`, `escalation_policy`. Validated before execution — no empty acceptance tests allowed.

#### 6. Stale Branch Detection

Three states: `Fresh`, `Stale { commits_behind }`, `Diverged { ahead, behind }`. Four policies: `AutoRebase`, `AutoMergeForward`, `WarnOnly`, `Block`. Runs before tests to avoid wasting time on stale failures.

#### 7. Mock Parity Harness

`mock-anthropic-service` crate: 10 scripted scenarios for deterministic testing without real API calls. Includes behavioral diff runner for parity testing.

### What claw-code Does NOT Have (Where We're Ahead)

- No SDLC enforcement workflow (has building blocks but no enforced TDD/planning/review)
- No cross-model review
- No CI integration
- No distribution mechanism (npm, plugin, etc.)
- Skills/plugin registry still planned, not implemented
- 4 days old — many features are stubs

---

## oh-my-openagent (OmO)

### Architecture

TypeScript/Bun plugin for OpenCode (Claude Code fork). 11 agents, 52 hooks (as of April 4, 2026), 26 tools.

5-stage init pipeline: `Config -> Managers -> Tools -> Hooks -> Plugin Interface`

### Patterns Worth Adopting

#### 1. Category-Based Task Routing (Anti-Lock-In)

Agents declare task **categories** (visual-engineering, deep, quick, ultrabrain), not model names. System maps categories to model fallback chains at runtime:

```
Sisyphus: claude-opus-4-6 -> kimi-k2.5 -> gpt-5.4 -> glm-5
```

**Why this matters**: Our wizard is Claude-specific. Category routing would make the SDLC framework provider-agnostic — you declare "I need a deep reviewer" not "use Codex."

#### 2. Multi-Agent Plan Review Chain

```
Prometheus (planner) -> Metis (gap analyzer, mandatory) -> Momus (validator, optional for high-accuracy)
```

Metis gap analysis is mandatory on all plans. Momus validation is conditional — triggered when high accuracy is requested, not universal baseline. Still relevant to our N-reviewer pipeline as a graduated review depth pattern.

#### 3. Hash-Anchored Edits (Hashline)

Every line gets a content-hash tag (e.g., `11#VK|`). Edits reference hashes — mismatches reject before corruption. OmO's README self-reports a 6.7% -> 68.3% edit success rate for Grok Code Fast, though no reproducible benchmark methodology is published in the repo.

#### 4. Boulder Mechanism (todoContinuationEnforcer)

Hook that refuses to let agents idle when tasks remain incomplete. This IS our shepherd pattern — never let the loop stop until verified clean.

#### 5. 52 Hooks with Opt-Out Pattern

Everything enabled by default. Users disable via `disabled_hooks` array with set-union merging. Elegant: "full enforcement unless you explicitly opt out."

- Session hooks (~25): todo enforcer, model fallback, context window monitor, compaction context injector
- Tool guard hooks (~14): write-existing-file guard, hash-line read enhancer, comment checker, **planner-only-write enforcement** (Prometheus blocked from writing outside plan files — `prometheus-md-only/hook.ts:49`)
- Transform hooks (~5): thinking block validator
- Continuation hooks (~8): background notification, stop-continuation guard

#### 6. Planner/Executor Separation (SDLC-Critical)

OmO enforces that Prometheus (planner) can ONLY write to plan/markdown files, not source code. This is a hard enforcement of separation of concerns — the planner plans, workers execute. Prevents the orchestrator from short-circuiting process by making code changes directly.

#### 7. Wisdom Accumulation

After each task, Atlas extracts learnings into `.sisyphus/notepads/{plan-name}/`:
- `learnings.md`, `decisions.md`, `issues.md`, `verification.md`, `problems.md`

Propagated to all subsequent workers. Prevents repeated mistakes across a session.

#### 8. Compaction Context Preservation

`compactionContextInjector` and `compactionTodoPreserver` hooks ensure critical state survives context compaction. Our wizard doesn't actively manage what survives compaction.

---

## oh-my-codex (OmX)

### Architecture

TypeScript + Rust orchestration layer above Codex CLI. Injects via AGENTS.md + config.toml. State managed in `.omx/` directories.

### Patterns Worth Adopting

#### 1. `$ralph` Mode (Persistent Execution Loop)

"The boulder never stops." After plan approval via `$ralplan`:
1. Ralph takes ownership of the execution
2. Persistent execution cycle with configurable max iterations (default: 10, set via `maxRalphIterations`)
3. **Architect verification gate**: Must explicitly validate ALL objectives before exit
4. On failure within iteration budget, continues iterating — does NOT terminate on partial solutions
5. State persisted in `.omx/state/` for safe resume after interruption

**Relevance**: This is our CI shepherd loop formalized. The architect verification gate and bounded iteration count are the key primitives — no one can accidentally accept a partial fix, but it also won't loop forever.

#### 2. `$team` Mode (Worktree Isolation)

| Feature | Detail |
|---------|--------|
| Isolation | Dedicated git worktrees per worker |
| Merge strategy | Auto-selected: fast-forward, cherry-pick, or cross-worker rebase |
| Worker types | Mixed CLI: `OMX_TEAM_WORKER_CLI_MAP=codex,claude,gemini` |
| Lifecycle | `plan -> prd -> exec -> verify -> fix` with strict transition gates |
| Coordination | Leader integrates worker commits continuously |

**Key difference from OmO**: OmX uses real git worktrees for true isolation. OmO uses shared workspace with background tasks. Worktree isolation is cleaner.

#### 3. Staged Pipeline with Transition Gates

```
plan -> prd -> exec -> verify -> fix -> complete
```

Each stage has explicit completion criteria. No skipping. This is a formalized version of our SDLC phases.

#### 4. Notepad with Tiered Pruning

`.omx/notepad.md` has three tiers:
- **Priority**: Always injected into context (never pruned)
- **Working**: Auto-pruned after 7 days
- **Manual**: Never pruned

Sophisticated memory management for persistent state.

#### 5. Delegation Golden Rule

"NEVER make code changes directly. ALWAYS delegate to specialized agents." The leader orchestrates; workers execute. Prevents the orchestrator from short-circuiting process.

#### 6. Pre-Execution Planning Gate (SDLC-Critical)

OmX's `$ralplan` skill redirects vague execution requests (`$ralph`, `$team`, `$autopilot`, `$ultrawork`) back through planning first. If a user tries to jump straight to execution without a plan, the system forces them through the planning gate. This is directly analogous to our wizard's plan-before-code requirement — but enforced at the tool level rather than via CLAUDE.md guidance.

#### 7. `$ralplan` Consensus

Planning requires three-party consensus:
- **Planner** creates initial plan
- **Architect** reviews structural soundness
- **Critic** challenges assumptions

Produces RALPLAN-DR summary before execution begins.

#### 8. `omx doctor` Diagnostics

Runtime self-check that validates installation, team health, hooks, and configuration. A `/doctor` skill for our wizard would catch configuration issues early.

---

## Comparative Analysis

| Pattern | claw-code | OmO | OmX | SDLC Harness Today | Adopt? |
|---------|-----------|-----|-----|-------------------|--------|
| Graduated test levels | GreenContract | - | - | Binary pass/fail | YES |
| Declarative policy engine | PolicyEngine | - | - | CLAUDE.md + hooks | EVALUATE |
| Recovery recipes | 7 scenarios | - | - | Generic ci-self-heal | YES |
| Hook input mutation | updatedInput | - | - | Allow/deny only | BLOCKED (CC limitation) |
| Multi-agent plan review | - | 2-3 agent chain (Momus optional) | $ralplan consensus | Cross-model review (2 models) | EVALUATE |
| Planning gate enforcement | - | - | $ralplan redirect (hard) | CLAUDE.md guidance (soft) | YES |
| Planner/executor separation | - | Hard (prometheus-md-only hook) | Delegation golden rule (soft) | Soft (guidance) | YES |
| Verification ownership | - | - | First-class team role | Implicit | YES |
| Persistence loop | - | Boulder | $ralph (bounded, default 10) | CI shepherd | YES (formalize) |
| Category-based routing | - | Agent categories | Mixed CLI map | Claude-specific | FUTURE (agent-agnostic) |
| Hash-anchored edits | - | Hashline | - | None | MONITOR |
| Wisdom accumulation | - | Notepad files | Tiered notepad | Memory system | COMPARE |
| Worktree isolation | - | - | Per-worker worktrees | Single workspace | YES (for parallel review) |
| Stale branch detection | 3 states + 4 policies | - | - | None | YES |
| Task contracts | TaskPacket | - | - | Plan docs (informal) | YES |
| Diagnostics command | - | - | omx doctor | sdlc-wizard check | EXTEND |
| Opt-out enforcement | - | disabled_hooks array | - | Hooks always on | EVALUATE |

---

## Candidate Patterns for SDLC Harness

**WARNING: These are CANDIDATES, not commitments.** Each pattern must pass the Prove It Gate before adoption:

1. **Write a quality test** that proves the pattern improves enforcement (not just exists)
2. **95%+ confidence** that the pattern adds value before merging
3. If we can't prove it → stays in research, doesn't ship
4. Speculative patterns that "sound good" but can't be tested = NO

This section is a candidates list, not a TODO list.

### High Priority (clear value, achievable)

1. **Adopt GreenContract levels** — Track graduated test verification (targeted/package/workspace/merge-ready) instead of binary pass/fail. Different SDLC checkpoints require different green levels
2. **Formalize CI shepherd as $ralph pattern** — Explicit architect verification gate before exit, bounded iteration count (default 10), state persistence for safe resume, no termination on partial solutions
3. **Pre-execution planning gate** — Enforce plan-before-execution at the tool level (OmX pattern). Redirect vague execution requests through planning first. Our wizard does this via CLAUDE.md guidance; make it a hard gate
4. **Planner/executor separation** — Hard enforcement that the planning agent can only write plan files, not source code (OmO pattern). Prevents orchestrator from short-circuiting TDD by making changes directly
5. **Explicit verification ownership** — Make verification a first-class team responsibility with designated verification owner (OmX `$team` pattern), not just "run tests"
6. **Add stale branch detection** — Check branch freshness before running expensive tests
7. **Structured recovery recipes** — Named failure scenarios with specific fix steps and max attempts, replacing generic "Claude fix it"
8. **Task contracts** — Formalized acceptance criteria, scope, and escalation policy before starting work

### Medium Priority (needs evaluation)

9. **Multi-agent plan review** — Prometheus/Metis/Momus chain or Planner/Architect/Critic consensus. Currently we do 2-model review. Metis gap analysis is mandatory; Momus validation is conditional for high-accuracy requests
10. **Compaction context preservation** — Active hooks ensuring critical state survives auto-compact
11. **`/doctor` skill** — Runtime diagnostics checking hooks, settings, version, config health
12. **Opt-out hook pattern** — Everything on by default, `disabled_hooks` array for users who want to reduce enforcement

### Future / Monitor

13. **Category-based agent routing** — Anti-lock-in for when wizard supports multiple AI agents
14. **Hash-anchored edits** — Interesting but CC controls its own edit mechanism
15. **Declarative policy engine** — Powerful but heavy. Our hook + CLAUDE.md approach works for current scale
16. **Mixed-provider team workers** — Relevant when #91 multi-agent adapter layer is done

---

## Continuously Monitor?

**Yes.** All three projects are evolving rapidly (claw-code is 4 days old with 167K stars, OmO releases multiple times per week, OmX had 8 releases in 2 weeks). Recommend:

- Add a quarterly research check (not weekly — too frequent for research items)
- Track major version releases for breaking pattern changes
- Focus on: hook system evolution (claw-code), orchestration patterns (OmO), persistence/team patterns (OmX)
- NOT an automated workflow — manual review each quarter is sufficient for research items
