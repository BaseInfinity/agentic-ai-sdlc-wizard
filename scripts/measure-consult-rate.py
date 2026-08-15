#!/usr/bin/env python3
"""Count how often the driver consults Fable BEFORE acting (GH #504).

The number #504 asks for: "How often does an Opus driver proceed on a
judgement call without consulting Fable?"

CAVEAT, and it is the whole reason this file carries a docstring: the
denominator here is TURNS, not decision episodes. One Fable ruling followed by
twenty implementation turns scores as nineteen misses, and the policy this
measures ("Fable rules on design, priority and sequencing before an approach is
committed") does not ask for a consult before every edit. Cross-model review of
the first numbers this produced ruled the metric directional, not load-bearing.
Read it as an alarm about the current topology, never as a verdict on a model.

Usage: scripts/measure-consult-rate.py [transcript-dir]
"""
import json, glob, os, re, sys, collections

DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/.claude/projects/-Users-stefanayala-claude-sdlc-wizard")
SUBSTANTIVE = {"Edit", "Write", "NotebookEdit"}
SUB_BASH = re.compile(r"\bgit\s+commit\b|\bgh\s+(pr|issue)\s+(create|merge|comment|edit)\b")


def user_text(ev):
    """The visible text of a real user message, or None if this is not one."""
    m = ev.get("message") or {}
    c = m.get("content")
    if isinstance(c, list):
        if any(p.get("type") == "tool_result" for p in c):
            return None            # a tool result is not a user turn
        c = " ".join(p.get("text", "") for p in c if p.get("type") == "text")
    if not isinstance(c, str) or not c.strip():
        return None
    if c.startswith("[SYSTEM NOTIFICATION"):
        return None
    stripped = re.sub(r"<system-reminder>.*?</system-reminder>", "", c, flags=re.S).strip()
    return stripped or None


def turns():
    for f in sorted(glob.glob(os.path.join(DIR, "*.jsonl")), key=os.path.getmtime):
        cur = None
        for line in open(f, errors="replace"):
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if ev.get("type") == "user":
                t = user_text(ev)
                if t is None:
                    continue
                if cur:
                    yield cur
                # ask length is retained so the reported slices are reproducible
                cur = {"ask": len(t), "order": [], "file": os.path.basename(f), "model": None}
                continue
            if cur is None or ev.get("type") != "assistant":
                continue
            msg = ev.get("message") or {}
            # attribute the turn to the model that ACTED in it, so a mixed
            # corpus cannot be read as one model's behaviour
            if msg.get("model") and cur["model"] is None:
                cur["model"] = msg["model"]
            for p in msg.get("content", []) or []:
                if p.get("type") != "tool_use":
                    continue
                name = p.get("name")
                if name == "advisor":
                    cur["order"].append("C")
                elif name == "Agent" and "fable" in json.dumps(p.get("input") or {}).lower():
                    cur["order"].append("C")
                elif name in SUBSTANTIVE:
                    cur["order"].append("S")
                elif name == "Bash" and SUB_BASH.search((p.get("input") or {}).get("command", "")):
                    cur["order"].append("S")
        if cur:
            yield cur


def report(label, rows):
    acted = [r for r in rows if "S" in r["order"]]
    if not acted:
        return
    pre = sum(1 for r in acted if "C" in r["order"][:r["order"].index("S")])
    after = sum(1 for r in acted
                if "C" in r["order"] and r["order"].index("C") > r["order"].index("S"))
    never = sum(1 for r in acted if "C" not in r["order"])
    print("%-30s turns=%4d  pre=%3d (%4.1f%%)  after=%3d  never=%4d (%4.1f%%)"
          % (label, len(acted), pre, 100 * pre / len(acted), after,
             never, 100 * never / len(acted)))


ROWS = list(turns())
print("corpus: %s\ntotal real user turns: %d\n" % (DIR, len(ROWS)))
report("ALL", ROWS)
report("ask >= 200 chars", [r for r in ROWS if r["ask"] >= 200])
report("ask >= 80 chars", [r for r in ROWS if r["ask"] >= 80])
report("ask < 80 chars", [r for r in ROWS if r["ask"] < 80])
print("\n-- by acting model (a near-identical rate across models means this is a\n"
      "   harness property, not one model's defect) --")
for m in sorted({r["model"] for r in ROWS if r["model"]}):
    report(m, [r for r in ROWS if r["model"] == m])
print("\n-- by session (clustering check: one dominant transcript is not a corpus) --")
for f in sorted({r["file"] for r in ROWS}):
    report(f[:8], [r for r in ROWS if r["file"] == f])
