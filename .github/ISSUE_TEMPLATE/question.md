---
name: Question
about: Ask how something works, or whether the wizard supports a use case
title: "question: "
labels: question
assignees: ''
---

## Your question

<!-- What are you trying to do? What have you tried? -->

## Context

<!-- Version, setup, what you've already read (SDLC.md, CLAUDE_CODE_SDLC_WIZARD.md, CONTRIBUTING.md). -->

## Scope card

<!-- A question needs no card to be asked. Fill this in only if the answer turns
     out to be "that's a bug" or "we should build that" -- at that point this
     issue produces work, and the card is what scope growth gets compared
     against. Until then, leave it or write N/A. -->

- **Acceptance criteria:** <!-- what must be observably true to close this -->
- **Allowed paths:** <!-- the only files this may touch; N/A while it stays a question -->
- **Exclusions:** <!-- what is explicitly NOT in this issue -->
- **Risk tier:** <!-- low / medium / high; N/A while it stays a question -->
- **Estimated diff:** <!-- roughly how many lines, deliverable and test; N/A while it stays a question -->

The breaker trips on a new subsystem/path/criterion, a diff past 2x the estimate, or two corrective rounds. When it trips, stop and record the decision on this issue rather than continuing.

## In-session alternative

If you're inside a Claude Code session, `/feedback` can also surface questions to the maintainer.
