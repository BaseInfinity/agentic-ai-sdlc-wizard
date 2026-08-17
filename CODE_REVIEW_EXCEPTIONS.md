# Code Review Exceptions

Known trade-offs evaluated and explicitly accepted. The CI reviewer should
skip suggestions that match entries below — they have already been considered.

**An exception is a dated decision, not a standing permission.** Every entry
carries a `Revisit if:` clause. When that clause fires, the entry stops being an
exception and becomes an open question — whether or not anyone notices. Write
conditions you will actually observe.

## Third-party actions pinned to major tags, not SHAs

**Files:** All `.github/workflows/*.yml`
**Flagged:** Codex main-branch audit (2026-03-27)
**Re-decided:** 2026-08-16 (#499)

**Decision: SPLIT by privilege. Tag pinning is NOT accepted on a workflow
holding `contents`, `id-token`, or `actions` write. It is accepted everywhere
else, including on workflows holding `issues` or `pull-requests` write.**

"Privileged" here means *can alter code or publish it*, not *can write
anything*. A workflow that can only post a comment or open an issue is not in
scope for this entry, and calling it privileged would put every workflow in the
repo on the not-accepted side — which is the blanket pinning this split exists
to avoid.

The 2026-03-27 decision rested on "this is a meta-documentation repo, not a
deployed service." **That premise died on 2026-03-28**, one day later, when the
repo began publishing to npm. The entry's own `Revisit if:` named "the repo
starts publishing artifacts" — so this exception has been expired for nearly
five months and kept suppressing the finding anyway. That is the failure this
re-decision exists to correct, and it is the reason the clause below is written
against something observable.

The privilege map as of 2026-08-16:

| workflow | write scopes | actions | tag pinning |
|---|---|---|---|
| `release.yml` | `contents`, **`id-token`** | `actions/checkout@v5`, `actions/setup-node@v5` | **not accepted** |
| `weekly-update.yml` | `contents`, `pull-requests`, **`actions`** | `actions/checkout@v5`, `peter-evans/create-pull-request@v8` | **not accepted** |
| `weekly-api-update.yml` | `contents`, `issues` | `actions/checkout@v5` | **not accepted** |
| `cc-version-drift.yml` | `issues` | `actions/checkout@v5` | accepted |
| `release-drift.yml` | `issues` | `actions/checkout@v5` | accepted |
| `pr-review.yml` | `pull-requests` | `actions/checkout@v5`, `anthropics/claude-code-action@v1`, `marocchino/sticky-pull-request-comment@v3` | accepted |
| `ci.yml` | `pull-requests` | `actions/checkout@v5` | accepted |
| `release-dry-run.yml` | none | `actions/checkout@v5`, `actions/setup-node@v5` | accepted |

All eight workflows are listed and every tag-pinned action in each is named. A
privilege map that omits a workflow is not a map; the reviewer cannot tell
whether a missing row was judged accepted or simply never looked at.

**Why the split rather than pinning all ~20 references.** The churn objection
from 2026-03-27 was real and is still real; SHA-pinning every reference across
every workflow buys little on paths that can only post a comment or open an
issue. It buys a great deal on the three that can write. Blanket acceptance and
blanket pinning are both wrong, in opposite directions.

**Two distinct exposures, and neither is ranked above the other — nobody has
measured them.**

- `release.yml` runs `actions/checkout@v5` **inside the `publish-and-release`
  job that holds `id-token: write`**. Tag-selected action code therefore
  executes in the job authorized to mint npm provenance. That the action is
  GitHub-official narrows who could move the tag; it does not change what runs
  where.
- `weekly-update.yml` runs a genuinely third-party action
  (`peter-evans/create-pull-request@v8`) while holding `contents: write` **and
  `actions: write`** — enough to modify workflow files. What it lands on `main`
  is published by `release.yml` at the next tag. Against that: its cron is
  disabled and it is `workflow_dispatch`-only, so it does not fire unattended.

An earlier draft of this entry called `weekly-update.yml` the sharper of the
two. That was an unmeasured ranking and has been removed. Both are on the
not-accepted side; deciding which is worse is not needed to act.

**Revisit if:** any action other than `actions/checkout` or
`actions/setup-node` is added to `release.yml` or `weekly-api-update.yml`; or
any workflow beyond those three gains `contents`, `id-token`, or `actions`
write; or `weekly-update.yml`'s cron is re-enabled.

*Each of those is checkable and none of them is true today — deliberately, and
at the second attempt. The 2026-03-27 clause fired the day after it was written
and suppressed findings for five months regardless. The first draft of this
replacement repeated the defect exactly: it said "a fourth workflow gains any
write scope," and a fourth already had one. **A `Revisit if:` whose condition is
already true is not a tripwire, it is a comment** — check it against today's
repo before you write it down.*

**Not yet implemented.** This entry records the decision; the workflow edits are
tracked in **#660**. Until they land, **any** tag-pinned action — third-party or
GitHub-official — on `release.yml`, `weekly-update.yml`, or
`weekly-api-update.yml` is a **valid review finding** and must not be suppressed
by this file. The carve-out is deliberately not limited to third-party actions:
the table marks those three workflows not-accepted, and `actions/checkout@v5` on
the npm-publishing job is precisely the case a third-party-only carve-out would
have let through.
