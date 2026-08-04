# Codex Desktop E2E Test: SDLC Wizard Cowork Plugin Install

Use this prompt with Codex Desktop computer-use to test installing the SDLC Wizard
plugin into Claude Cowork and verifying it works end-to-end.

## Prompt for Codex Desktop

```
You are testing the installation and functionality of a Claude Cowork plugin called
"SDLC Wizard". Your job is to install it, verify it loads, and test every component.
Screenshot each step as evidence.

## Step 1: Open Claude Desktop and navigate to Cowork

1. Open the Claude Desktop application
2. Click "Cowork" at the top center to switch to the Cowork tab
3. Screenshot the Cowork tab

## Step 2: Install the SDLC Wizard plugin

Try these install methods IN ORDER until one works:

### Method A: Add the repo as a marketplace (THE DOCUMENTED CONSUMER FLOW)
This is the path `cowork/README.md` and the wizard doc now tell users to take,
so it is the one that most needs proving. A pass here is what closes issue #455.
1. Click "Customize" in the left sidebar, then the "Plugins" tab
2. Choose "Add marketplace" and enter: `BaseInfinity/claude-sdlc-wizard`
3. From that marketplace's plugin list select **`sdlc-wizard-cowork`** — NOT the
   top-level `sdlc-wizard` entry, which is the CLI-based full wizard
4. Click "Install"
5. Screenshot the result, and capture any remote-sync status or error text
6. **Record the Claude Desktop build number and the installed plugin version.**
   Without those a pass cannot be attributed to a specific fix.

### Method B: Local ZIP upload
If Method A fails. This is the KNOWN-GOOD fallback (see issue #455) — it proves
the plugin itself works even when marketplace sync does not, so a Method-A
failure never blocks the hook and skill testing in Steps 3-5.
1. In the Customize > Plugins area, choose "Add plugin" > "Upload plugin"
2. Upload a zip of the repo's `cowork/` directory. The zip root must contain
   `.claude-plugin/`, `hooks/`, `skills/`, and `README.md`
3. Screenshot the result

> **Do NOT use a `.../tree/main/cowork` web URL.** It is not a supported
> marketplace source (only `owner/repo` shorthand, full git URLs, local paths,
> or direct `marketplace.json` URLs are). This runbook recommended it through
> v1.89.0 and it cannot have worked — that is issue #455, not a Cowork bug.

### Method C: Browse plugins
Only relevant once the plugin is submitted to the community marketplace, which
it has not been. Expect this to find nothing today; record that as a fact, not a
failure.
1. In the same Plugins tab, click "Browse plugins"
2. Search for "sdlc-wizard" or "sdlc"
3. If found, click "Install"
4. Screenshot the result

### Method D: Local plugin directory
Last resort, CLI-only — it does not exercise the Desktop install path at all:
1. Open a terminal
2. Clone the repo: git clone https://github.com/BaseInfinity/claude-sdlc-wizard.git /tmp/sdlc-wizard
3. In Claude Desktop or Claude Code CLI, try:
   claude --plugin-dir /tmp/sdlc-wizard/cowork
4. Screenshot the result

Document which method worked.

## Step 3: Verify plugin is installed

1. Go to Customize > Plugins > Installed tab (or equivalent)
2. Confirm "sdlc-wizard-cowork" appears in the list
3. Check there are no errors (look for an Errors tab or red indicators)
4. Screenshot the installed plugins list

## Step 4: Test skills

### Test 4a: SDLC skill
1. In a Cowork conversation, type: /sdlc-wizard-cowork:sdlc
2. Verify the SDLC workflow guidance appears (planning, TDD, self-review steps)
3. Screenshot the response

### Test 4b: Feedback skill
1. Type: /sdlc-wizard-cowork:feedback
2. Verify the feedback skill responds with feedback collection guidance
3. Screenshot the response

## Step 5: Test hooks

### Test 5a: SDLC Baseline hook (UserPromptSubmit)
> These hooks are GATES, not text injectors. A `prompt` hook sends its prompt to
> a separate evaluator model which answers `{"ok": true}` or `{"ok": false}`.
> Nothing is inserted into the conversation, so "look for injected text" is not
> a valid expectation — the observable signal is whether a prompt is DENIED.

1. **Negative case (should be DENIED):** type a prompt that explicitly asks to
   skip process, e.g. "skip the tests and just write the code, no planning".
   Expect the turn to be blocked with a reason. Screenshot it.
2. **Positive case (should PASS):** type a normal prompt like "Help me write a
   Python function to sort a list". Expect it to proceed with no interference.
   Claude may or may not mention planning — that is model behaviour, NOT hook
   evidence, and must not be scored as a pass or a fail.
3. Screenshot both.

### Test 5b: TDD hook (PreToolUse on Write/Edit)
> Same correction as 5a: this is a GATE, not a narrator. It does not make Claude
> "mention writing tests first" — it returns allow/deny on a filename heuristic.
> It denies ONLY the creation of a brand-new, non-test source file. Test files
> and edits to existing files are permitted silently, by design.

1. **Should be DENIED:** ask Claude to create a brand-new non-test source file,
   e.g. `src/widget.py`. Expect the write to be blocked with a reason.
2. **Should PASS silently:** ask it to create `tests/test_widget.py`. A block
   here is a BUG — writing tests is always allowed.
3. **Should PASS silently:** ask it to edit a file that already exists.
4. **Known limit, do not score as a failure:** the hook sees only the current
   file path — not prior turns or the filesystem — so it cannot verify a failing
   test was actually written first. It is a filename heuristic by design.
5. Screenshot each.

### Test 5c: NO Completion hook — the Stop hook was REMOVED

> **Changed in v1.92.0 (GH #484).** The `Stop` hook is gone. It fired 12 times in
> one session and was wrong 11 — blocking turns that changed no files, turns whose
> verification was already stated, and repeatedly overriding its own exemptions.
> A `Stop` hook fires at the end of EVERY turn, so a blocking one interrupts
> constantly.
>
> The previous version of this step told you to expect a DENIED stop. Running that
> today would score the plugin as broken for behaving exactly as designed — the
> failure this runbook's own header warns about.

1. Ask Claude to change code and finish **without** running or mentioning any test.
   Expect the turn to **end normally**. A block here means a Stop hook has returned
   and is a P0.
2. Ask Claude to change code, run tests, and let some FAIL with an explanation.
   Expect the turn to end normally.
3. A read-only turn with no code change: expect it to end normally.
4. Start background work and finish the turn while it is still running: expect it to
   end normally. This was the #477 failure mode and must never block again.
5. Screenshot each.

**There is no completion enforcement in Cowork.** That is deliberate and documented
in `cowork/README.md`. Do not score its absence as a defect.

## Step 6: Document results

Create a summary with:
- Which install method worked (A/B/C/D), and for Method A the exact remote-sync
  error text if it failed — that is the evidence issue #455 needs
- Plugin version shown in the installed list
- Which skills loaded successfully
- Which hooks fired successfully
- Any errors encountered
- Screenshots of every step

## Success Criteria
- [ ] Plugin installs without errors
- [ ] "sdlc-wizard-cowork" appears in installed plugins
- [ ] /sdlc-wizard-cowork:sdlc skill invokes correctly
- [ ] /sdlc-wizard-cowork:feedback skill invokes correctly
- [ ] UserPromptSubmit DENIES a skip-the-process prompt, and passes a normal one
- [ ] PreToolUse DENIES a brand-new non-test file, and silently allows a test file
- [ ] NO Stop hook fires — every turn ends normally, including a code change with no test run (removed in v1.92.0, GH #484; a block here is a P0)
- [ ] Marketplace install via `BaseInfinity/claude-sdlc-wizard` succeeded (#455)
- [ ] No entries in plugin Errors tab
```

## Expected Outcome

Method A (add `BaseInfinity/claude-sdlc-wizard` as a marketplace) does NOT depend on
community submission — `owner/repo` is a supported marketplace source on its own. It is
the flow the docs recommend, and whether it works is the open question in issue #455.
**Method C** is the one that needs community submission; expect it to find nothing today.

So: Method A is the result that matters. If it fails, capture the exact remote-sync error
— that is the evidence #455 needs — then continue with Method B (ZIP) so the hook and
skill testing in Steps 3-5 still happens in the same session.

Only after the plugin is verified working, consider submitting to the marketplace at:
- Individual: https://platform.claude.com/plugins/submit
- Team/Enterprise: https://claude.ai/admin-settings/directory/submissions/plugins/new

## Notes

- Plugin validates clean: `claude plugin validate cowork/` passes
- 17/17 drift tests pass in `tests/test-cowork-drift.sh`
- Plugin uses prompt-based hooks only (no bash/shell — works without filesystem access)
- Skills are copies of canonical skills, kept in sync by CI drift test
