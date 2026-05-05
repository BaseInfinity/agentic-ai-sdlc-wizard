# Autocompact Benchmarking Methodology

A rigorous, reproducible methodology for measuring how different `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` thresholds affect Claude Code session quality, context preservation, and cost.

> **Status:** Methodology designed, infrastructure ready for validation. CLI interface verification and benchmark data collection pending — see [Limitations](#limitations).

## Background

The SDLC Wizard recommends autocompact thresholds (75% for 200K, 30% for 1M) based on **unverified community consensus** from GitHub issues ([#34332](https://github.com/anthropics/claude-code/issues/34332), [#42375](https://github.com/anthropics/claude-code/issues/42375)) and forum reports. No controlled experiments have been published. This methodology enables the first rigorous benchmarks.

### What Is Autocompact?

Claude Code automatically compresses conversation history when context usage approaches capacity. The `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` environment variable controls when this triggers (1-100, percentage of context window). Lower values = earlier compaction = more headroom but potentially more context loss.

### Current Claims (Unverified)

These recommendations are community consensus, not empirically validated:

| Claim | Source | Status |
|-------|--------|--------|
| 75% optimal for 200K general dev | GitHub forums, community reports | **Unverified** |
| 30% or COMPACT_WINDOW=400000 for 1M | GitHub issue #34332 | **Unverified** |
| Default fires at ~76K on 1M models | Issue #34332, anecdotal | **Unverified** |
| Quality degrades at 147-152K tokens on 200K | Community reports | **Unverified** |
| Post-compaction loses 60-70% of context | Subjective reports | **Unverified** |
| Noise is 50-70% of session tokens | Not measured | **Unverified** |
| Math.min() cap at ~83% | Widely reported | **Unverified** |

## Experimental Design

### Independent Variables

Variables the experimenter controls:

| Variable | Values | Rationale |
|----------|--------|-----------|
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | 50, 60, 70, 75, 80, 83, 95 (default) | Covers the full recommended range plus extremes |
| Context window | 200K, 1M | The two available model configurations |
| Task complexity | Short (~10K tokens), Medium (~50K), Long (~120-150K) | Controls whether compaction actually triggers |

### Dependent Variables

What we measure at each condition:

| Metric | How Measured | Unit |
|--------|-------------|------|
| **Task completion score** | SDLC evaluation rubric (10-point scale via evaluate.sh) | 0-10 |
| **Context preservation rate** | Canary fact recall: (facts_recalled / 5) * 100% | 0-100% |
| **Token cost** | Total input + output tokens from session metadata | Tokens |
| **Compaction event count** | Count compaction markers in session output | Integer |
| **Time-to-completion** | Wall clock from session start to final output | Seconds |

### Controls

To isolate the effect of the threshold variable:

- **Isolated sessions:** Each trial runs in a fresh session (no state carryover)
- **Same task prompt:** Identical task text across all threshold conditions
- **Same model:** All trials within a condition use the same model (Opus 4.6)
- **Temperature 0:** Reduce randomness (note: Claude Code's temperature may not be user-configurable — document actual setting)
- **Same max-turns:** Consistent `--max-turns` across conditions
- **Same wizard version:** Pin to a specific wizard release
- **Same fixture:** Tasks run against the same test repo fixture

### Statistical Analysis

- **Minimum 5 trials per condition** (threshold × task complexity)
- **95% confidence intervals** using t-distribution (matches existing `stats.sh` library)
- **Effect size:** Cohen's d between adjacent thresholds
- **Comparison:** CI overlap method from `compare_ci()` in `stats.sh`
- Results reported as: `mean ± margin (95% CI: [lower, upper])`

## Canary Fact Mechanism

The novel contribution enabling rigorous context preservation measurement. Uses a 3-phase protocol: injection of known facts, task execution to fill context, and recall testing post-compaction.

### Concept

Standard benchmarks only measure "can the model still code after compaction?" — they don't measure "does the model remember what I told it?" These are orthogonal quality dimensions. The canary fact mechanism tests both.

### Protocol

1. **Injection phase (Turn 1):** The task prompt begins with 5 canary facts — arbitrary, specific statements unrelated to the coding task. These are injected via the `canary-facts.json` file.

2. **Coding phase (Turns 2-N):** Normal SDLC task execution. The model plans, writes tests, implements, reviews. This fills context toward the autocompact threshold.

3. **Recall phase (Turn N+1):** After the coding task completes (and compaction may have fired), a follow-up prompt in the SAME session asks about each canary fact. Session continuity via `--resume <session_id>` (CLI) or `session_id` output (claude-code-action).

4. **Scoring:**
   ```
   preservation_rate = (facts_correctly_recalled / 5) * 100%
   ```

### Why Canary Facts?

- **Domain-independent:** Facts are not about coding, so recall isn't conflated with task knowledge
- **Binary scoring:** Each fact is either recalled or not — no subjective evaluation
- **Measurable degradation curve:** Plot preservation_rate vs. threshold to find the cliff
- **Orthogonal to task score:** A model can score 10/10 on the coding task but 0% on recall — this reveals silent context loss

## Harness Architecture

### Local Execution

```bash
# Set threshold for this session
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75

# Phase 1+2: Run task with canary facts (multi-turn)
claude -p "$TASK_WITH_CANARY_FACTS" --max-turns 55 > output.json 2>&1
SESSION_ID=$(jq -r '.session_id // empty' output.json)

# Phase 3: Resume session for canary recall
claude --resume "$SESSION_ID" -p "$RECALL_PROMPT" > recall.json 2>&1

# Score
evaluate.sh --json output.json > score.json
score_canary_recall recall.json canary-facts.json > recall_score.json
```

### CI Execution (GitHub Actions)

```yaml
# Threshold passed via settings.env (NOT workflow env:)
- uses: anthropics/claude-code-action@v1
  with:
    prompt: ${{ steps.task.outputs.prompt }}
    claude_args: "--max-turns 55"
    # Env vars forwarded to Claude process
    claude_env: |
      CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=${{ matrix.threshold }}
```

Note: `claude-code-action` env var forwarding mechanism should be verified against current action.yml — the `claude_env` input name may differ. See [action.yml](https://github.com/anthropics/claude-code-action/blob/main/action.yml) for current interface.

### Results Format

Each trial produces a JSONL entry:

```json
{
  "timestamp": "2026-04-05T12:00:00Z",
  "threshold": 75,
  "context_window": "200K",
  "task": "medium-task",
  "trial": 1,
  "task_score": 8,
  "max_score": 10,
  "canary_recall": 3,
  "canary_total": 5,
  "preservation_rate": 60,
  "token_count": 142000,
  "compaction_events": 2,
  "duration_seconds": 185,
  "session_id": "abc123"
}
```

## Cost Estimation

Estimated costs per session and per threshold configuration, based on current Opus 4.6 pricing.

### Per-Trial Cost

Based on Claude Opus 4.6 pricing (as of April 2026):
- Input: $15/M tokens, Output: $75/M tokens
- Estimated per session: ~150K input + ~30K output = $2.25 + $2.25 = ~$4.50/trial

### Full Matrix Cost

| Configuration | Trials | Estimated Cost |
|---------------|--------|---------------|
| 7 thresholds × 3 tasks × 5 trials (200K) | 105 | ~$470 |
| 7 thresholds × 3 tasks × 5 trials (1M) | 105 | ~$470 |
| **Full matrix** | **210** | **~$940** |
| Minimal: 3 thresholds × 1 task × 3 trials | 9 | ~$40 |
| Validation: 1 threshold × 1 task × 1 trial | 1 | ~$5 |

### Budget-Aware Execution

The harness supports incremental execution:
1. **Validation run** (1 trial, ~$5): Proves the harness works end-to-end
2. **Pilot study** (9 trials, ~$40): 3 key thresholds (60%, 75%, 95%) on 1 task
3. **Full study** (210 trials, ~$940): Complete matrix, publishable results

## Running Benchmarks

### Prerequisites

- `claude` CLI installed (v2.1.85+)
- `ANTHROPIC_API_KEY` set
- `jq` installed
- This repository cloned

### Quick Start

```bash
# Validate setup (no API calls)
./tests/benchmarks/run-benchmark.sh --dry-run

# Single validation run
./tests/benchmarks/run-benchmark.sh --threshold 75 --task medium --trials 1

# Pilot study
./tests/benchmarks/run-benchmark.sh --threshold 60,75,95 --task medium --trials 3

# Analyze results
./tests/benchmarks/analyze-results.sh tests/benchmarks/results/
```

### CI Execution

The companion `benchmark-autocompact.yml` workflow was deleted 2026-05-05 in the GC pass — it never ran and burned API on dispatch. Run the methodology locally on a Max subscription instead:

```bash
./tests/benchmarks/run-benchmark.sh --threshold 60,75,95 --task medium --trials 3
./tests/benchmarks/analyze-results.sh tests/benchmarks/results/
```

This mirrors the [#231 workflow-port pattern](ROADMAP.md): cheap detection + maintainer-on-Max execution beats Action-layer LLM calls.

## Limitations

This release ships the benchmarking **infrastructure before benchmark data**. The methodology, harness, task suite, and analysis tools are complete and validated via dry-run. Actual benchmark results require API budget ($5-940 depending on scope) and will be collected incrementally.

### Known Limitations

1. **No data yet.** The methodology is validated but results are pending. Community consensus thresholds remain the best available guidance until benchmarks run.
2. **Single-model scope.** Designed for Opus 4.6. Other models (Sonnet 4.6, Haiku) may behave differently under compaction.
3. **Canary recall requires session resumption.** The `--resume` / `session_id` mechanism must be verified against the current Claude CLI version.
4. **Token measurement uncertainty.** Exact token counts may not be available from session output — may need to estimate from character count.
5. **Cost scales linearly.** Full matrix is expensive ($940). Incremental approach recommended.
6. **200K vs 1M model selection.** The harness assumes the user has access to the desired context window configuration.

### What This Does NOT Measure

- Effect of different compaction prompts (only default Claude compaction)
- Interaction between autocompact and manual `/compact`
- Effect of `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (separate variable)
- Multi-session learning (each trial is isolated)

## References

- [Claude Code Issue #34332](https://github.com/anthropics/claude-code/issues/34332) — 1M autocompact firing at ~76K
- [Claude Code Issue #42375](https://github.com/anthropics/claude-code/issues/42375) — Autocompact env var discussion
- [SDLC Wizard Autocompact Tuning](CLAUDE_CODE_SDLC_WIZARD.md#autocompact-tuning) — Current recommendations
- [stats.sh](tests/e2e/lib/stats.sh) — Statistical library (CI calculation, comparison)
- [run-tier2-evaluation.sh](tests/e2e/run-tier2-evaluation.sh) — Multi-trial evaluation pattern
