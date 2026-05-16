# Claude Code instructions for this repo

This file is auto-loaded by Claude Code at the start of every session that opens
this directory.  It establishes project-wide rules so all sessions (and all
collaborators using Claude Code) behave consistently.

---

## RULE 1: Keep HANDOFF.md current

`HANDOFF.md` is the canonical "pickup the baton" document.  Every Claude Code
session working in this repo MUST keep it accurate so the next session — whether
by the same user or a different one, in this thread or another — can start cold
without losing context.

### When you MUST update HANDOFF.md

Update at the end of a working session (or at the moment of the finding,
whichever is more natural) if ANY of these happened during the session:

1. **A project phase changed status** — pending → in-progress, in-progress → done,
   or a blocker resolved
2. **A hypothesis was confirmed or disproven** — e.g., "signal X is actually
   protocol Y at baud Z, not what we thought"
3. **A new tool / script / decoder was added** or significantly changed behavior
4. **Hardware findings updated** — pinout, new chip identified, new wire traced
5. **An open question got an answer** (even partial)
6. **Captures landed that changed protocol understanding**
7. **An error in prior content was discovered** — must be marked and corrected
   non-destructively per the process below

You do NOT need to update for: small typo fixes in code, transient experiments
that didn't pan out, or pure formatting tweaks.  The bar is "would the next
session be confused or duplicate work without this update?"

### When you MAY update HANDOFF.md (proactive maintenance)

- The current state genuinely differs from what's documented
- Stale items are still listed as open when actually resolved
- Section dates are far past their "Last verified" mark and worth re-checking

---

## RULE 2: Non-destructive amendment process

The cardinal rule: **never silently delete information from HANDOFF.md**.  Mark
content as superseded and add new content alongside it.  This makes mistakes
trivially recoverable — wrong content stays visible inline and in git, never
quietly vanishes.

### Process — minor addition

When you have new info that extends what's already there:

1. Add the new info to the most-relevant existing section
2. Bump the `Last updated:` line in the HANDOFF.md header
3. Add a one-line entry to the `## Change log` at the bottom of HANDOFF.md
4. Commit the change in git with a descriptive message

### Process — correction (you discovered prior content was wrong)

1. Find the old text.  Wrap it with this marker:
   ```markdown
   > ~~**[CORRECTED YYYY-MM-DD]**~~ — superseded by section below.  Preserved for
   > traceability — the old understanding is shown here:
   >
   > [old text indented in blockquote]
   ```
2. Add the corrected info immediately below as a new dated paragraph or section
3. Add a Change log entry: `YYYY-MM-DD — Corrected [topic]: [what was wrong → what's right]`
4. Bump `Last updated:` in the header
5. Commit

### Process — major new finding (breakthrough)

1. Add a new top-level section near the top of the document with a date-stamped
   title (e.g. `## 🔥 BREAKTHROUGH YYYY-MM-DD — [topic]`)
2. Cross-reference any older sections it supersedes (use the supersede marker
   in those older sections)
3. Update the "Project status by phase" table
4. Update Change log
5. Bump `Last updated:` in the header
6. Commit with a clear message

### Process — superseded section

Add this banner at the top of the section being retired:

```markdown
## [Section title] [SUPERSEDED YYYY-MM-DD — see "[New section title]" above]
> This section is kept for historical context.  The current understanding lives
> in the newer section linked above.
```

Then keep the old content intact below the banner.

---

## RULE 3: Git is the safety net

Every HANDOFF.md update lands in a git commit, which is the ultimate undo button.
If anything ever goes wrong with HANDOFF.md (a botched edit, an accidental
deletion, a wrong correction):

```bash
git log -p HANDOFF.md                       # full edit history
git diff <old-sha> HEAD -- HANDOFF.md       # what changed since some commit
git checkout <old-sha> -- HANDOFF.md        # restore an earlier version safely
                                              # (only affects HANDOFF.md, nothing else)
git show <old-sha>:HANDOFF.md > old_handoff.md   # view old version without overwriting current
```

Commit messages for HANDOFF.md updates should be descriptive enough that
`git log --oneline -- HANDOFF.md` is browsable as a change history.  Good
examples:
- `HANDOFF: mark phase 4a done after panLeft.csv decode`
- `HANDOFF: correct B11 interpretation — direction → press-duration`
- `HANDOFF: add pinout for IR LED MCPCB respin`

---

## RULE 4: When in doubt, ask the user before touching HANDOFF.md

If you're not sure whether to update HANDOFF.md, ask first.  But after a clear
breakthrough or phase completion, just update it — that's the whole point.

---

## RULE 5: Other documents in this repo

- **`MC800S-system-map.md`** — the master technical reference (board pinouts,
  signal traces, protocol findings).  Update freely; it's a living technical
  document.  No special amendment process required (git is the safety net).
- **`README.md`** — project overview and tool inventory.  Update when adding
  major tooling or changing project status.
- **`HANDOFF.md`** — special rules above.  Always follow the non-destructive
  amendment process.
