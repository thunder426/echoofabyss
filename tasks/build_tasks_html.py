#!/usr/bin/env python3
"""Regenerate tasks/tasks.html from tasks/*.md frontmatter + body.

Idempotent and fast. Triggered by a PostToolUse hook on Edit/Write.
Run manually with: python3 tasks/build_tasks_html.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

TASKS_DIR = Path(__file__).resolve().parent
HTML_OUT = TASKS_DIR / "tasks.html"
INDEX_MD = TASKS_DIR / "TASKS.md"

FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", re.DOTALL)


def parse_frontmatter(text: str) -> tuple[dict, str]:
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}, text
    fm_block, body = m.group(1), m.group(2)
    fm: dict = {}
    for line in fm_block.splitlines():
        if not line.strip() or line.strip().startswith("#"):
            continue
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        fm[k.strip()] = v.strip()
    return fm, body


def load_tasks() -> list[dict]:
    tasks = []
    for p in sorted(TASKS_DIR.glob("*.md")):
        if p.name == "TASKS.md" or p.name.startswith("_"):
            continue
        fm, body = parse_frontmatter(p.read_text(encoding="utf-8"))
        if not fm:
            continue
        tasks.append({
            "id": fm.get("id", p.stem.split("-", 1)[0]),
            "title": fm.get("title", p.stem),
            "status": fm.get("status", "backlog"),
            "area": fm.get("area", ""),
            "priority": fm.get("priority", ""),
            "started": fm.get("started", ""),
            "finished": fm.get("finished", ""),
            "file": p.name,
            "body": body.strip(),
        })
    return tasks


def render_index_md(tasks: list[dict]) -> str:
    by_status = {"active": [], "backlog": [], "done": []}
    for t in tasks:
        by_status.setdefault(t["status"], []).append(t)

    def line(t: dict) -> str:
        bits = []
        if t["area"]:
            bits.append(t["area"])
        if t["status"] == "done" and t["finished"]:
            bits.append(f"{t['started']} → {t['finished']}")
        elif t["started"]:
            bits.append(f"started {t['started']}")
        meta = f" ({', '.join(bits)})" if bits else ""
        return f"- [{t['id']}]({t['file']}) — {t['title']}{meta}"

    out = ["# Tasks", "",
           "Index of project tasks. View with `tasks/tasks.html` (open in browser).", ""]
    for status, header in [("active", "Active"), ("backlog", "Backlog"), ("done", "Done")]:
        out.append(f"## {header}")
        items = by_status.get(status, [])
        if status == "done":
            items = sorted(items, key=lambda x: x["finished"], reverse=True)
        else:
            items = sorted(items, key=lambda x: x["started"] or "9999", reverse=True)
        if not items:
            out.append("_(none)_")
        else:
            out.extend(line(t) for t in items)
        out.append("")
    return "\n".join(out).rstrip() + "\n"


HTML_TEMPLATE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Echo of Abyss — Task Tracker</title>
<style>
  :root {
    --bg: #1a1a1f; --panel: #23232a; --border: #33333d; --text: #e6e6ea;
    --muted: #8a8a96; --accent: #b48cff; --active: #6cd49a; --done: #6a6a76;
    --backlog: #d4a76c;
  }
  * { box-sizing: border-box; }
  body { margin: 0; font: 14px/1.5 -apple-system, system-ui, sans-serif;
         background: var(--bg); color: var(--text); }
  header { padding: 16px 24px; border-bottom: 1px solid var(--border);
           display: flex; align-items: center; gap: 16px; }
  header h1 { margin: 0; font-size: 18px; font-weight: 600; }
  header .count { color: var(--muted); font-size: 13px; }
  .controls { padding: 12px 24px; border-bottom: 1px solid var(--border);
              display: flex; gap: 12px; align-items: center; flex-wrap: wrap; }
  .controls input, .controls select {
    background: var(--panel); color: var(--text); border: 1px solid var(--border);
    border-radius: 4px; padding: 6px 10px; font: inherit;
  }
  .controls input { min-width: 240px; }
  .tabs { display: flex; gap: 4px; }
  .tab { background: transparent; color: var(--muted); border: 1px solid var(--border);
         border-radius: 4px; padding: 6px 12px; cursor: pointer; font: inherit; }
  .tab.on { background: var(--panel); color: var(--text); border-color: var(--accent); }
  main { padding: 16px 24px; max-width: 1100px; }
  .task { background: var(--panel); border: 1px solid var(--border);
          border-radius: 6px; margin-bottom: 8px; overflow: hidden; }
  .task-head { padding: 10px 14px; cursor: pointer; display: flex;
               align-items: center; gap: 10px; }
  .task-head:hover { background: #2a2a32; }
  .id { color: var(--muted); font-family: ui-monospace, monospace; font-size: 12px;
        min-width: 38px; }
  .title { flex: 1; font-weight: 500; }
  .pill { font-size: 11px; padding: 2px 8px; border-radius: 10px;
          border: 1px solid var(--border); color: var(--muted); }
  .pill.status-active { color: var(--active); border-color: var(--active); }
  .pill.status-backlog { color: var(--backlog); border-color: var(--backlog); }
  .pill.status-done { color: var(--done); }
  .dates { color: var(--muted); font-size: 12px; min-width: 90px; text-align: right; }
  .body { padding: 0 14px 14px 60px; border-top: 1px solid var(--border);
          display: none; color: #cfcfd6; }
  .body.on { display: block; }
  .body h1, .body h2, .body h3 { color: var(--text); margin: 14px 0 6px; }
  .body h1 { font-size: 16px; } .body h2 { font-size: 14px; }
  .body h3 { font-size: 13px; color: var(--accent); }
  .body code { background: #2c2c34; padding: 1px 5px; border-radius: 3px;
               font-family: ui-monospace, monospace; font-size: 12px; }
  .body pre { background: #15151a; padding: 10px; border-radius: 4px; overflow-x: auto; }
  .body pre code { background: none; padding: 0; }
  .body ul, .body ol { padding-left: 22px; }
  .body a { color: var(--accent); }
  .empty { color: var(--muted); padding: 32px; text-align: center; }
</style>
</head>
<body>
<header>
  <h1>Echo of Abyss — Task Tracker</h1>
  <span class="count" id="count"></span>
</header>
<div class="controls">
  <input id="q" type="text" placeholder="search title or body…" autofocus>
  <select id="area"><option value="">all areas</option></select>
  <div class="tabs">
    <button class="tab on" data-status="active">Active</button>
    <button class="tab" data-status="backlog">Backlog</button>
    <button class="tab" data-status="done">Done</button>
    <button class="tab" data-status="all">All</button>
  </div>
</div>
<main id="list"></main>
<script>
const TASKS = __TASKS_JSON__;
const STATE = { status: "active", area: "", q: "" };

// Tiny markdown renderer — handles headers, bold, italic, code, lists, links, paragraphs.
function md(src) {
  src = src.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  // fenced code
  src = src.replace(/```([\s\S]*?)```/g, (_, c) => "<pre><code>" + c.replace(/^\n/, "") + "</code></pre>");
  const lines = src.split("\n");
  const out = [];
  let inList = null; // "ul" | "ol" | null
  let para = [];
  const flushPara = () => { if (para.length) { out.push("<p>" + para.join(" ") + "</p>"); para = []; } };
  const closeList = () => { if (inList) { out.push("</" + inList + ">"); inList = null; } };
  for (const raw of lines) {
    const line = raw.replace(/\s+$/, "");
    if (!line.trim()) { flushPara(); closeList(); continue; }
    let m;
    if ((m = line.match(/^(#{1,3})\s+(.*)$/))) {
      flushPara(); closeList();
      out.push("<h" + m[1].length + ">" + inline(m[2]) + "</h" + m[1].length + ">");
    } else if ((m = line.match(/^[-*]\s+(.*)$/))) {
      flushPara();
      if (inList !== "ul") { closeList(); out.push("<ul>"); inList = "ul"; }
      out.push("<li>" + inline(m[1]) + "</li>");
    } else if ((m = line.match(/^\d+\.\s+(.*)$/))) {
      flushPara();
      if (inList !== "ol") { closeList(); out.push("<ol>"); inList = "ol"; }
      out.push("<li>" + inline(m[1]) + "</li>");
    } else if (line.startsWith("<pre>")) {
      flushPara(); closeList(); out.push(line);
    } else {
      closeList();
      para.push(inline(line));
    }
  }
  flushPara(); closeList();
  return out.join("\n");
}
function inline(s) {
  return s
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|[^*])\*([^*]+)\*/g, "$1<em>$2</em>")
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
}

function populateAreas() {
  const sel = document.getElementById("area");
  const areas = [...new Set(TASKS.map(t => t.area).filter(Boolean))].sort();
  for (const a of areas) {
    const o = document.createElement("option"); o.value = a; o.textContent = a;
    sel.appendChild(o);
  }
}

function render() {
  const list = document.getElementById("list");
  const q = STATE.q.toLowerCase();
  let items = TASKS.filter(t => {
    if (STATE.status !== "all" && t.status !== STATE.status) return false;
    if (STATE.area && t.area !== STATE.area) return false;
    if (q && !(t.title.toLowerCase().includes(q) || t.body.toLowerCase().includes(q))) return false;
    return true;
  });
  // sort: done by finished desc; else started desc; fallback id desc
  items.sort((a, b) => {
    const ka = a.status === "done" ? a.finished : a.started;
    const kb = b.status === "done" ? b.finished : b.started;
    return (kb || "").localeCompare(ka || "") || (b.id || "").localeCompare(a.id || "");
  });
  document.getElementById("count").textContent = items.length + " task" + (items.length === 1 ? "" : "s");
  if (!items.length) { list.innerHTML = '<div class="empty">No tasks match.</div>'; return; }
  list.innerHTML = items.map(t => {
    const dates = t.status === "done" && t.finished
      ? t.finished
      : (t.started || "");
    return `
      <div class="task" data-id="${t.id}">
        <div class="task-head">
          <span class="id">${t.id}</span>
          <span class="title">${escapeHtml(t.title)}</span>
          ${t.area ? `<span class="pill">${escapeHtml(t.area)}</span>` : ""}
          <span class="pill status-${t.status}">${t.status}</span>
          <span class="dates">${dates}</span>
        </div>
        <div class="body">${md(t.body || "_(no body)_")}</div>
      </div>`;
  }).join("");
  for (const head of list.querySelectorAll(".task-head")) {
    head.addEventListener("click", () => head.nextElementSibling.classList.toggle("on"));
  }
}
function escapeHtml(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }

document.getElementById("q").addEventListener("input", e => { STATE.q = e.target.value; render(); });
document.getElementById("area").addEventListener("change", e => { STATE.area = e.target.value; render(); });
for (const tab of document.querySelectorAll(".tab")) {
  tab.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach(t => t.classList.remove("on"));
    tab.classList.add("on");
    STATE.status = tab.dataset.status;
    render();
  });
}
populateAreas();
render();
</script>
</body>
</html>
"""


def render_html(tasks: list[dict]) -> str:
    return HTML_TEMPLATE.replace(
        "__TASKS_JSON__", json.dumps(tasks, ensure_ascii=False)
    )


def write_if_changed(path: Path, content: str) -> bool:
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return False
    path.write_text(content, encoding="utf-8")
    return True


def main() -> int:
    if not TASKS_DIR.is_dir():
        return 0
    tasks = load_tasks()
    changed_html = write_if_changed(HTML_OUT, render_html(tasks))
    changed_md = write_if_changed(INDEX_MD, render_index_md(tasks))
    if changed_html or changed_md:
        print(f"tasks: {len(tasks)} task(s); "
              f"{'wrote ' if changed_html else 'kept '}tasks.html, "
              f"{'wrote ' if changed_md else 'kept '}TASKS.md", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
