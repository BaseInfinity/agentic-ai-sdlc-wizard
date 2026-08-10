---
name: Bug report
about: Report a bug in the SDLC Harness (CLI, hooks, skills, workflows, tests)
title: "bug: "
labels: bug
assignees: ''
---

## What happened

<!-- What broke? Include any error messages or unexpected behavior. -->

## What you expected

<!-- What should have happened? -->

## Reproduction

<!-- Minimal steps to reproduce. A small repro is much more useful than a long description. -->

1.
2.
3.

## Scope card

<!-- Fill this in before work starts. It is what scope growth gets compared against -- CLOSED ALLOWLIST has nothing to check without it. -->

- **Acceptance criteria:** <!-- what must be observably true to close this -->
- **Allowed paths:** <!-- the only files this may touch -->
- **Exclusions:** <!-- what is explicitly NOT in this issue -->
- **Risk tier:** <!-- low / medium / high -->
- **Estimated diff:** <!-- roughly how many lines, deliverable and test -->

The breaker trips on a new subsystem/path/criterion, a diff past 2x the estimate, or two corrective rounds. When it trips, stop and record the decision on this issue rather than continuing.

## Environment

- **SDLC Harness version:** <!-- run `grep 'Wizard Version' SDLC.md` in your project, or check package.json -->
- **Claude Code version:** <!-- run `claude --version` -->
- **OS:** <!-- macOS / Linux / Windows -->
- **Install channel:** <!-- npx / Homebrew / curl script / plugin / GitHub Releases -->

## Logs / output

<!-- Paste any relevant CLI output, hook logs, or CI run URLs. -->

```
```

## In-session alternative

If this is a usability or workflow question rather than a bug, consider running `/feedback` inside a Claude Code session — it files a redacted feedback issue automatically with more context pre-filled.
