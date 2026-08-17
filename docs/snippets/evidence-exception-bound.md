<!-- Canonical statement. Single source of truth for the evidence-exception bound (issue #608). -->

# Evidence-only pass: the bound

The review-loop stop condition has exactly ONE evidence-only exception: after a verification-evidence invalidation, at most one evidence-only re-verification pass may run, and ONLY for the FIRST such invalidation in this root task (FIRST-in-this-root-task). The second or later invalidation in the same root task authorizes no further pass — the loop stops and the result is handed off for human review.

State this rule here ONLY. Every other document must either use this line verbatim or reference it (`see docs/snippets/evidence-exception-bound.md`). If the wording changes, update the reference in `tests/test-evidence-exception-bound.sh` to match — the drift check is the guard, stated once, not a regex over prose.
