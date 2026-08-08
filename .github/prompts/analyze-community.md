# Claude Code Community Scan Prompt

> **Usage (post-#231 Phase 3c, v1.53.0):** the CI `scan-community` cron was deleted. Run this prompt manually on Max when you want a community scan:
>
> ```bash
> claude --print --allowedTools "WebFetch,Read,Bash" \
>   "$(cat .github/prompts/analyze-community.md)" > /tmp/scan_result.json
> ```
>
> The maintainer reads `/tmp/scan_result.json` and decides what (if anything) to incorporate.

You are scanning community discussions about Claude Code to find actionable insights for the SDLC Harness.

## Wizard Context

The SDLC Harness enforces:
- **TDD** - Failing tests first, then implementation
- **Planning** - Plan mode before coding
- **Confidence levels** - HIGH/MEDIUM/LOW stated before implementing
- **Tasks** - TodoWrite/TaskCreate for tracking work
- **Self-review** - Review before presenting to user

## What You're Scanning

- Reddit: r/ClaudeAI, r/programming (Claude Code mentions)
- Hacker News: Claude Code discussions
- Dev blogs: Popular posts about Claude Code tips/tricks
- Official community channels (Discord, forums)

### Competitive Watchlist

Check these repos for new features, releases, or approaches we should know about:

| Repo | Focus | Why We Watch |
|------|-------|-------------|
| [everything-claude-code](https://github.com/affaan-m/everything-claude-code) | Full agent framework (28 agents, 80+ skills) | Breadth leader — new hooks, skills, or patterns to consider |
| [claude-sdlc](https://github.com/danielscholl/claude-sdlc) | SDLC plugin marketplace | Closest to our approach — slash commands, webhook automation |
| [claude-code-sdlc](https://github.com/Koroqe/claude-code-sdlc) | 12-agent documentation-first pipeline | Documentation-first philosophy overlap |
| [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) | Curated resource directory | Community pulse — what's getting stars/attention |
| [aistupidlevel.info](https://github.com/StudioPlatforms/aistupidmeter-web) | Model benchmarking (CUSUM, CI) | Methodology ally — our stats.sh is inspired by their approach |

For each: note new releases, significant changes, or ideas worth incorporating. Don't report if nothing changed.

## What To Look For

### Actionable Insights
- Patterns that improve SDLC enforcement
- Tips that align with wizard philosophy (KISS, TDD, planning)
- Problems users are having that the wizard could prevent
- Clever uses of hooks, skills, or CLAUDE.md

### Red Flags to Filter Out
- Hype without substance
- Features that would add bloat
- Complexity for complexity's sake
- Things already covered by the wizard

## Expectations

**Most content will be noise - that's expected and OK.**

The goal is to surface the occasional gem, not to act on everything. If nothing is worth reporting, say so.

## Response Format

Respond with valid JSON:

```json
{
  "scan_date": "YYYY-MM-DD",
  "sources_checked": ["reddit", "hackernews", "devblogs", "official"],
  "findings": [
    {
      "origin": "external" | "internal-friction",
      "source": "reddit/hackernews/devblog/official/friction-signal",
      "url": "link to discussion or GitHub issue URL",
      "title": "Thread/article title",
      "summary": "2-3 sentence summary of what was discussed",
      "relevance": "HIGH" | "MEDIUM" | "LOW",
      "potential_improvement": "How this could improve the wizard (or null if just informational)",
      "category": "tdd" | "planning" | "confidence" | "hooks" | "skills" | "workflow" | "other"
    }
  ],
  "digest_summary": "1-2 paragraph summary of what the community is discussing this week",
  "recommended_actions": [
    {
      "action": "What to do",
      "reasoning": "Why this is worth doing",
      "priority": "HIGH" | "MEDIUM" | "LOW"
    }
  ],
  "nothing_notable": true | false
}
```

## Important Notes

- Quality over quantity - only include genuinely useful findings
- It's OK (even expected) to return `nothing_notable: true` most weeks
- Include source links so humans can verify
- Don't recommend adding features just because they're popular
- Focus on what aligns with wizard philosophy
- Human decides what (if anything) to incorporate
- **Origin field:** Use `"external"` for community discussions (Reddit, HN, blogs). Use `"internal-friction"` for friction-signal issues from CI. The origin field used to gate CI E2E testing (deleted in v1.52.0, ROADMAP #231 Phase 3b). It still controls digest categorization so the maintainer can review external findings on-Max via `tests/e2e/local-shepherd.sh <PR> --compare-baseline` and treat friction findings as visibility-only signals.
