---
description: Close a task in the local task tracker. Writes a summary, sets status=done, fills in the finished date.
argument-hint: <task_id>
---

Close out a task in `tasks/`. The task id is `$ARGUMENTS` (3-digit, e.g. `001`).

Steps:

1. Find the task file: `tasks/$ARGUMENTS-*.md`. If not found, report and stop.
2. Read the file. Verify `status: active` (or `backlog`). If it is already `done`, report and stop.
3. Get today's date in `YYYY-MM-DD` format (Bash `date +%Y-%m-%d`).
4. Edit the frontmatter:
   - `status: active` → `status: done`
   - `finished:` → `finished: <today>`
5. Append a final entry to `## Work log`: `- <today>: closed.`
6. Replace the `## Summary` section's placeholder body with a 1–3 sentence summary of what actually shipped: the change, the why, and any follow-ups or known gaps. Pull from the conversation context — what was actually built, not what was planned. If there are known follow-ups, note them as `Follow-ups: …` on a new line.
7. Tell the user one short line: `Closed task NNN — <title>.` Do not paste the file back.

Notes:
- Do NOT manually edit `tasks/TASKS.md` or `tasks/tasks.html`. They regenerate via the hook.
- If the work split into a follow-up that warrants its own tracker entry, mention to the user that they may want `/task-start` for it.
