#!/usr/bin/env python3
"""Engine lint for the live/sim unification refactor.

See design/refactors/LIVE_SIM_UNIFICATION_PLAN.md, section 5.3, for the full
rule set and the phase that introduces each rule.

  L1  Rules code reaching through the combat shell (`_scene.x`, `scene.x`,
      `ctx.scene.x`, `.get/.set/.has_method("x")`) must name something the
      LIVE shell (CombatScene) actually has. A name that only exists on
      CombatState / SimState works in tests (which run on SimState) and crashes
      or silently no-ops in the real game. `<shell>.state.x` must name
      something on CombatState. CombatSetup registry "stats" keys must exist on
      CombatState (they are written with `state.set`).

  L2  Gameplay randomness goes through the engine RNG (`state.rng_pick`,
      `rng_shuffle`, `rng_range`, `rng_index`), never the global RNG, so a seed
      reproduces a fight. Cosmetic VFX randomness is out of scope. A line may
      opt out with the comment `# lint: allow-rng (<reason>)`.

Usage:  python3 tools/lint/lint_engine.py [--quiet]
Output: `<rule> <file>:<line>: <message>`; exit code = error count (capped 255).
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LINT_DIR = os.path.dirname(os.path.abspath(__file__))

SCENE = "combat/board/CombatScene.gd"
STATE = "combat/board/CombatState.gd"
SIM_STATE = "sim/SimState.gd"

# Files whose shell handle is a member named `_scene`.
UNDERSCORE_SCENE_FILES = [
    "combat/events/CombatHandlers.gd",
    "combat/effects/HardcodedEffects.gd",
    "relics/RelicEffects.gd",
]
# Files whose shell handle is `scene` (a member, a local alias of ctx.scene,
# or a parameter) and/or `ctx.scene`.
SCENE_FILES = [
    "combat/effects/EffectResolver.gd",
    "combat/effects/ConditionResolver.gd",
    "combat/effects/TargetResolver.gd",
    "combat/board/CombatManager.gd",
    "combat/board/MinionInstance.gd",
]
SETUP = "combat/events/CombatSetup.gd"

# L2 scope: directories scanned recursively, plus single files.
RNG_DIRS = ["combat/board", "combat/events", "sim", "enemies/ai"]
RNG_FILES = [
    "combat/effects/EffectResolver.gd",
    "combat/effects/ConditionResolver.gd",
    "combat/effects/TargetResolver.gd",
    "combat/effects/HardcodedEffects.gd",
    "relics/RelicEffects.gd",
]
RNG_RE = re.compile(r"(?<![\w.])(randi|randf|randi_range|randf_range|pick_random|shuffle)\(|\.(pick_random|shuffle)\(")
RNG_ALLOW = "lint: allow-rng"

# Object / Node / Node2D members reachable on CombatScene without a declaration.
BUILTINS = {
    "get", "set", "has_method", "call", "callv", "call_deferred", "emit_signal",
    "connect", "disconnect", "is_connected", "has_signal", "get_script",
    "is_inside_tree", "get_tree", "get_node", "get_node_or_null", "has_node",
    "add_child", "remove_child", "get_parent", "get_children", "queue_free",
    "get_viewport", "get_viewport_rect", "create_tween", "is_queued_for_deletion",
    "get_global_mouse_position", "global_position", "position", "name",
    "set_meta", "get_meta", "has_meta", "free", "is_instance_valid",
}

DECL_RE = re.compile(
    r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?(?:var|func|signal|const|enum)\s+(\w+)"
)
GETSET_NAME_RE = r'\.(?:get|set|has_method)\(\s*"(\w+)"'


def read(rel: str) -> list[str]:
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        return fh.read().splitlines()


def declared(rel: str) -> set[str]:
    names: set[str] = set()
    for line in read(rel):
        m = DECL_RE.match(line)
        if m:
            names.add(m.group(1))
    return names


def load_allow(name: str) -> set[tuple[str, str]]:
    """Allow-list rows are `path:name  # reason`."""
    path = os.path.join(LINT_DIR, name)
    rows: set[tuple[str, str]] = set()
    if not os.path.exists(path):
        return rows
    for raw in open(path, encoding="utf-8"):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        file_part, _, name_part = line.rpartition(":")
        rows.add((file_part.strip(), name_part.strip()))
    return rows


def strip_comment(line: str) -> str:
    # Good enough for GDScript: drop everything after a '#' that is not inside
    # a string literal.
    out, in_str, quote = [], False, ""
    for ch in line:
        if in_str:
            out.append(ch)
            if ch == quote:
                in_str = False
        elif ch in "\"'":
            in_str, quote = True, ch
            out.append(ch)
        elif ch == "#":
            break
        else:
            out.append(ch)
    return "".join(out)


class Linter:
    def __init__(self) -> None:
        self.scene = declared(SCENE) | BUILTINS
        self.state = declared(STATE)
        self.sim = declared(SIM_STATE)
        self.allow = load_allow("l1_allow.txt")
        self.errors: list[str] = []

    def err(self, rule: str, rel: str, lineno: int, msg: str) -> None:
        self.errors.append(f"{rule} {rel}:{lineno}: {msg}")

    # -- L1 ------------------------------------------------------------------
    def check_shell_name(self, rel: str, lineno: int, name: str, via: str) -> None:
        if name in self.scene or (rel, name) in self.allow:
            return
        where = []
        if name in self.state:
            where.append("CombatState")
        if name in self.sim:
            where.append("SimState")
        if where:
            self.err("L1", rel, lineno,
                     f"{via}{name} exists on {'/'.join(where)} but not on CombatScene "
                     f"(works in sim/tests, breaks live) — use .state.{name}")
        else:
            self.err("L1", rel, lineno, f"{via}{name} is not declared on any combat shell")

    def check_state_name(self, rel: str, lineno: int, name: str) -> None:
        if name in self.state or (rel, "state." + name) in self.allow:
            return
        extra = " (SimState only)" if name in self.sim else ""
        self.err("L1", rel, lineno, f".state.{name} is not declared on CombatState{extra}")

    def scan_file(self, rel: str, handles: list[str]) -> None:
        alt = "|".join(re.escape(h) for h in handles)
        # `<handle>.state.<name>` — must be on CombatState.
        state_re = re.compile(rf"(?<![\w.])(?:{alt})\.state\.(\w+)")
        # `<handle>.<name>` (not followed by `(` for get/set/has_method, handled below)
        direct_re = re.compile(rf"(?<![\w.])(?:{alt})\.(\w+)")
        # `<handle>.get/set/has_method("name")`
        str_re = re.compile(rf"(?<![\w.])(?:{alt}){GETSET_NAME_RE}")
        state_str_re = re.compile(rf"(?<![\w.])(?:{alt})\.state{GETSET_NAME_RE}")
        for i, raw in enumerate(read(rel), start=1):
            line = strip_comment(raw)
            for m in state_re.finditer(line):
                name = m.group(1)
                if name not in ("get", "set", "has_method"):
                    self.check_state_name(rel, i, name)
            for m in state_str_re.finditer(line):
                self.check_state_name(rel, i, m.group(1))
            for m in direct_re.finditer(line):
                name = m.group(1)
                if name in ("get", "set", "has_method"):
                    continue
                self.check_shell_name(rel, i, name, ".")
            for m in str_re.finditer(line):
                self.check_shell_name(rel, i, m.group(1), '.get/set("')

    def scan_setup_stats(self) -> None:
        in_stats = False
        depth = 0
        for i, raw in enumerate(read(SETUP), start=1):
            line = strip_comment(raw)
            if not in_stats:
                idx = line.find('"stats"')
                if idx < 0:
                    continue
                line = line[idx + len('"stats"'):]
                in_stats, depth = True, 0
            for key in re.findall(r'"(\w+)"\s*:', line):
                if key not in self.state:
                    self.err("L1", SETUP, i, f'registry stat "{key}" is not declared on CombatState')
            depth += line.count("{") - line.count("}")
            if depth <= 0 and ("}" in line or "{" in line):
                in_stats = False

    # -- L2 ------------------------------------------------------------------
    def scan_rng(self) -> None:
        files = list(RNG_FILES)
        for d in RNG_DIRS:
            for dirpath, _dirs, names in os.walk(os.path.join(ROOT, d)):
                for n in sorted(names):
                    if n.endswith(".gd"):
                        files.append(os.path.relpath(os.path.join(dirpath, n), ROOT))
        for rel in sorted(set(files)):
            for i, raw in enumerate(read(rel), start=1):
                if RNG_ALLOW in raw:
                    continue
                m = RNG_RE.search(strip_comment(raw))
                if m:
                    self.err("L2", rel, i, f"global RNG `{m.group(0)}` — use state.rng_* (engine RNG)")

    def run(self) -> int:
        self.scan_rng()
        for rel in UNDERSCORE_SCENE_FILES:
            self.scan_file(rel, ["_scene"])
        for rel in SCENE_FILES:
            self.scan_file(rel, ["ctx.scene", "scene"])
        self.scan_setup_stats()
        return len(self.errors)


def main() -> int:
    quiet = "--quiet" in sys.argv
    linter = Linter()
    count = linter.run()
    if not quiet:
        for e in linter.errors:
            print(e)
    print(f"lint_engine: {count} error{'s' if count != 1 else ''}")
    return min(count, 255)


if __name__ == "__main__":
    sys.exit(main())
