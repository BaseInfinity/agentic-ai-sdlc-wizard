---
name: Feature request
about: Propose a new SDLC enforcement rule, hook, skill, or workflow
title: "feat: "
labels: enhancement
assignees: ''
---

## What's the gap

<!-- What real development problem does this solve? Prefer concrete evidence (incident, PR, transcript excerpt) over theoretical gaps. -->

## Proposed solution

<!-- What should the wizard do? Which layer — hook, skill, workflow, CLI flag? -->

## Scope card

<!-- Fill this in before work starts. It is what scope growth gets compared against -- CLOSED ALLOWLIST has nothing to check without it. -->

- **Acceptance criteria:** <!-- what must be observably true to close this -->
- **Allowed paths:** <!-- the only files this may touch -->
- **Exclusions:** <!-- what is explicitly NOT in this issue -->
- **Risk tier:** <!-- low / medium / high -->
- **Estimated diff:** <!-- roughly how many lines, deliverable and test -->

The breaker trips on a new subsystem/path/criterion, a diff past 2x the estimate, or two corrective rounds. When it trips, stop and record the decision on this issue rather than continuing.

## Prove-It Gate

The wizard is deliberately lean. New additions must show their value before landing:

- [ ] Is there a real, observed gap (not theoretical)?
- [ ] Does something equivalent already exist (native CC feature, existing skill, third-party)?
- [ ] If equivalent exists: what makes this better? (A/B evidence, quality comparison)
- [ ] Can you write a test that proves quality, not just existence?

Answering these up front dramatically speeds up triage.

## Alternatives considered

<!-- What else could solve this? Why is your proposal better? -->

## In-session alternative

`/feedback` inside a Claude Code session files a suggestion with richer context pre-filled.
