#!/usr/bin/env python3
"""Engine lint for the live/sim unification refactor.

See design/refactors/LIVE_SIM_UNIFICATION_PLAN.md, section 5.3, for the full
rule set and the phase that introduces each rule.

  L1  (plan 0.3; 4.4) Rules code (RULES_FILES: CombatState, CombatSetup, the
      handlers, effects, resolvers, EffectContext, CombatManager, MinionInstance,
      PhaseTransition) holds no combat shell: no `_scene`, `ctx.scene`, `_fx` or
      `scene.`. Nor does it read run state from an autoload (`GameManager.`,
      `UserProfile.`, `TestConfig.`): a fight's inputs come from its
      CombatConfig. CombatSetup registry "stats" keys must exist on CombatState
      (they are written with `state.set`).

  L2  Gameplay randomness goes through the engine RNG (`state.rng_pick`,
      `rng_shuffle`, `rng_range`, `rng_index`), never the global RNG, so a seed
      reproduces a fight. Cosmetic VFX randomness is out of scope. A line may
      opt out with the comment `# lint: allow-rng (<reason>)`.

  L3  (plan 1.1; 4.4) Rules code never calls presentation: no `presenter` /
      `ctx.presenter`. Every mutation journals a CombatEvent; the presenter
      plays it.

  L4  No duck typing in rules files: `has_method(` anywhere, and
      `.get("x")` / `.set("x", …)` / `"x" in <handle>` on an object handle (shell, presenter,
      state, enemy_ai / turn_manager aliases, event contexts). Dictionary
      `.get("key")` is fine.

  L5  (plan 1.4; 4.2) One implementation per gameplay method: nothing
      `extends CombatState` (SimState, the last subclass, is gone).

  L6  (plan 2A.9) The engine never waits: no `await`, `get_tree(` or
      `create_timer(` in CombatState.gd. (plan 3.1a, D11) The engine holds no
      slot Node: no `BoardSlot` in CombatState.gd,
      CombatHandlers.gd, EffectResolver.gd or TargetResolver.gd — slots are
      `SlotState`.

  L7  (plan 2A.9) One engine, defined once repo-wide: each state command
      (`func cmd_*`), the turn engine (`begin_turn`, `end_turn`),
      trap routing (`_fire_traps_for`), and the AI profile table (a script that
      preloads the enemies/ai/profiles/ scripts — ProfileRegistry).

  L8  (plan 3.5) Presentation never mutates: in the VFX, UI, presenter and
      input files no BuffSystem.apply*, SlotState.place(, combat_manager.,
      trigger_manager.fire, EffectResolver.run, `state.<field> =`,
      player_board / enemy_board append / erase, or current_health writes
      (CheatPanel, a debug tool, is exempt).

  L9  (plan 4.8) No duck typing in combat/board, combat/events,
      combat/effects (VFX files exempt), relics, sim or enemies/ai:
      `has_method(`, and `.get/.set("x")` / `"x" in` on an object handle.
      Dictionary `.get("key")` is fine.

  L10 (plan 5.3) VFX runners, not ad-hoc timers: `await get_tree().create_timer`
      in combat/effects/*VFX.gd may not exceed L10_BASELINE (the count when the
      rule landed). Lower the baseline when a VFX migrates.

  L11 (plan 5.3) Names reached through an untyped scene handle resolve: in
      combat/, relics/ and debug/tests/, `_scene.X` / `scene.X` / `_combat.X` /
      `combat.X` must be declared on CombatScene (or be a Node / CanvasItem
      member), and `<handle>.state.X` on CombatState. The handles are untyped,
      so the compiler never checks these — a deleted scene helper otherwise
      fails only when a player clicks (0.617's `_player_can_afford_sparks`).

Rules not yet enforced (see ENFORCED) are still computed; `--all` prints them,
but they do not count toward the exit code.

Usage:  python3 tools/lint/lint_engine.py [--quiet] [--all] [--report-pairs]
Output: `<rule> <file>:<line>: <message>`; exit code = enforced error count (capped 255).
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

SCENE = "combat/board/CombatScene.gd"
STATE = "combat/board/CombatState.gd"
# L6 (3.1a): files that must not name the BoardSlot view.
NO_BOARDSLOT_FILES = [
    STATE,
    "combat/events/CombatHandlers.gd",
    "combat/effects/EffectResolver.gd",
    "combat/effects/TargetResolver.gd",
]

# Rules code: the engine and everything it runs. Since plan 4.4 none of it
# holds the combat shell or the presenter — gameplay goes through the typed
# CombatState, presentation follows from the journal.
SETUP = "combat/events/CombatSetup.gd"
RULES_FILES = [
    STATE, SETUP,
    "combat/events/CombatHandlers.gd",
    "combat/effects/HardcodedEffects.gd",
    "relics/RelicEffects.gd",
    "combat/effects/EffectResolver.gd",
    "combat/effects/ConditionResolver.gd",
    "combat/effects/TargetResolver.gd",
    "combat/effects/EffectContext.gd",
    "combat/board/CombatManager.gd",
    "combat/board/MinionInstance.gd",
    "combat/board/PhaseTransition.gd",
]

# Rules counted toward the exit code (L3/L4 since plan step 1.2, L5 since 1.6,
# L6/L7 since 2A.9).
ENFORCED = {"L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10", "L11"}

# L10: `await get_tree().create_timer` count in *VFX.gd when the rule landed.
L10_BASELINE = 20

# L11: untyped handles to the live CombatScene, the directories they are
# checked in, and the Node / CanvasItem members they may use besides the
# scene's own declarations.
SCENE_HANDLES = ["_scene", "scene", "_combat", "combat"]
SCENE_HANDLE_DIRS = ["combat", "relics", "debug/tests"]
NODE_MEMBERS = {
    "get_viewport", "get_tree", "add_child", "remove_child", "move_child", "is_inside_tree",
    "get_node", "get_node_or_null", "has_node", "get_parent", "get_children", "get_child",
    "get_child_count", "get_index", "find_child", "queue_free", "call_deferred", "call",
    "create_tween", "get_global_mouse_position", "get_viewport_rect", "connect", "disconnect",
    "is_connected", "emit_signal", "set_process", "set_process_input", "name", "owner",
    "position", "global_position", "scale", "rotation", "modulate", "visible", "z_index",
    "to_global", "to_local", "get_canvas_transform", "state",
}

# L1: autoloads holding run state, which rules code never reads (task 055).
RUN_STATE_RE = re.compile(r"(?<![\w.])(?:GameManager|UserProfile|TestConfig)\.")

# L1 / L3: handles that would resolve to the combat shell, and to the presenter.
SHELL_HANDLES = ["ctx.scene", "_scene", "scene", "_fx"]
PRESENTER_HANDLES = ["ctx.presenter", "presenter"]
# L4: receivers that are objects, never Dictionaries, in rules code.
OBJECT_HANDLES = SHELL_HANDLES + PRESENTER_HANDLES + [
    "ctx.state", "state", "enemy_ai", "ai", "turn_manager", "tm", "ctx", "event_ctx", "ectx",
]

# L9 (plan 4.8) scope: no duck typing anywhere in the combat layer, relics, sim
# or the AI — VFX files (*VFX.gd, combat/effects/vfx/) are exempt.
DUCK_DIRS = ["combat/board", "combat/events", "combat/effects", "relics", "sim", "enemies/ai"]
DUCK_HANDLES = ["_scene", "scene", "_combat", "combat", "target", "node", "slot", "panel"]

# L2 scope: directories scanned recursively, plus single files.
RNG_DIRS = ["combat/board", "combat/events", "sim", "enemies/ai"]
RNG_FILES = [
    "combat/effects/EffectResolver.gd",
    "combat/effects/ConditionResolver.gd",
    "combat/effects/TargetResolver.gd",
    "combat/effects/HardcodedEffects.gd",
    "relics/RelicEffects.gd",
    "enemies/data/EncounterDecks.gd",
]
RNG_RE = re.compile(r"(?<![\w.])(randi|randf|randi_range|randf_range|pick_random|shuffle)\(|\.(pick_random|shuffle)\(")
RNG_ALLOW = "lint: allow-rng"

DECL_RE = re.compile(
    r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?(?:var|func|signal|const|enum)\s+(\w+)"
)


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


def gd_files() -> list[str]:
    """Every project .gd file (repo-relative), skipping dot-dirs, tasks/ and addons/."""
    out: list[str] = []
    for dirpath, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("tasks", "addons")]
        for n in sorted(names):
            if n.endswith(".gd"):
                out.append(os.path.relpath(os.path.join(dirpath, n), ROOT))
    return out


def declared_funcs(rel: str) -> set[str]:
    return {m.group(1) for line in read(rel)
            if (m := re.match(r"^(?:static\s+)?func\s+(\w+)", line))}


class Linter:
    def __init__(self) -> None:
        self.state = declared(STATE)
        self.errors: list[str] = []

    def err(self, rule: str, rel: str, lineno: int, msg: str) -> None:
        self.errors.append(f"{rule} {rel}:{lineno}: {msg}")

    # -- L1 ------------------------------------------------------------------
    def scan_shell(self, rel: str) -> None:
        """Plan 4.4: rules code has no shell — no `_scene`, `ctx.scene`, `_fx` or
        `scene.` anywhere (the B1 class: a name the live shell lacks)."""
        shell_re = re.compile(r"(?<![\w.])(?:ctx\.scene|_scene|_fx)\b|(?<![\w.])scene\.")
        for i, raw in enumerate(read(rel), start=1):
            line = strip_comment(raw)
            m = shell_re.search(line)
            if m:
                self.err("L1", rel, i, f"`{m.group(0)}` — rules code has no combat shell; use the typed state")
            m = RUN_STATE_RE.search(line)
            if m:
                self.err("L1", rel, i, f"`{m.group(0)}` — rules code doesn't read run state; the fight's inputs come from its CombatConfig")

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

    # -- L3 / L4 --------------------------------------------------------------
    def scan_seam(self, rel: str) -> None:
        pres = "|".join(re.escape(h) for h in PRESENTER_HANDLES)
        objs = "|".join(re.escape(h) for h in OBJECT_HANDLES)
        pres_re = re.compile(rf"(?<![\w.])(?:{pres})\b")
        duck_re = re.compile(rf"(?<![\w.])(?:{objs})\.(?:get|set)\(\s*\"(\w+)\"")
        in_re = re.compile(rf"\"(\w+)\"\s+in\s+(?:{objs})\b")
        for i, raw in enumerate(read(rel), start=1):
            line = strip_comment(raw)
            if pres_re.search(line):
                self.err("L3", rel, i, "presenter — rules code never calls presentation; journal an event (state.emit_event)")
            if "has_method(" in line:
                self.err("L4", rel, i, "has_method( — duck typing; call a typed member")
            for m in duck_re.finditer(line):
                self.err("L4", rel, i, f'.get/.set("{m.group(1)}") on an object — use the typed member')
            for m in in_re.finditer(line):
                self.err("L4", rel, i, f'"{m.group(1)}" in <object> — use the typed member')

    # -- L5 ------------------------------------------------------------------
    def scan_pairs(self) -> None:
        """Since plan 4.2 (SimState deleted): nothing extends CombatState, so no
        shell can override a rule — every gameplay method has one body."""
        ext_re = re.compile(r"^\s*extends\s+CombatState\b")
        for rel in gd_files():
            for i, raw in enumerate(read(rel), start=1):
                if ext_re.match(raw):
                    self.err("L5", rel, i, "extends CombatState — the engine has one body; compose it instead")

    # -- L6 ------------------------------------------------------------------
    def scan_engine_waits(self) -> None:
        wait_re = re.compile(r"\bawait\b|get_tree\(|create_timer\(")
        for i, raw in enumerate(read(STATE), start=1):
            m = wait_re.search(strip_comment(raw))
            if m:
                self.err("L6", STATE, i, f"`{m.group(0)}` in the engine — CombatState never waits")
        # 3.1a / D11: the engine and rules code hold plain SlotState, never the BoardSlot view.
        slot_re = re.compile(r"\bBoardSlot\b")
        for rel in NO_BOARDSLOT_FILES:
            for i, raw in enumerate(read(rel), start=1):
                if slot_re.search(strip_comment(raw)):
                    self.err("L6", rel, i, "`BoardSlot` in engine / rules code — use SlotState (the node is a view)")

    # -- L8 ------------------------------------------------------------------
    def scan_presentation_mutation(self) -> None:
        import glob
        files = sorted(glob.glob(os.path.join(ROOT, "combat/effects/*VFX.gd"))
                       + glob.glob(os.path.join(ROOT, "combat/effects/vfx/*.gd"))
                       + glob.glob(os.path.join(ROOT, "combat/ui/*.gd")))
        rels = [os.path.relpath(f, ROOT) for f in files if not f.endswith("CheatPanel.gd")]
        rels += ["combat/board/%s.gd" % n for n in ("BoardSlot", "CombatPresenter", "CombatUI",
                 "CombatInputHandler", "TrapEnvDisplay", "LargePreview", "Targeting", "CounterWarning")]
        bad = re.compile(r"BuffSystem\.apply|\.place\(|combat_manager\.|trigger_manager\.fire|EffectResolver\.run"
                         r"|\bstate\.\w+\s*=[^=]|player_board\.(append|erase)|enemy_board\.(append|erase)"
                         r"|current_health\s*[-+]?=[^=]")
        for rel in rels:
            if not os.path.exists(os.path.join(ROOT, rel)):
                continue
            for i, raw in enumerate(read(rel), start=1):
                m = bad.search(strip_comment(raw))
                if m:
                    self.err("L8", rel, i, f"`{m.group(0).strip()}` in presentation code — journal an event, the presenter plays it")

    # -- L7 ------------------------------------------------------------------
    def scan_single_definitions(self) -> None:
        func_re = re.compile(r"^\s*(?:static\s+)?func\s+(cmd_\w+|begin_turn|end_turn|_fire_traps_for)\s*\(")
        seen: dict[str, list[str]] = {}
        registries: list[str] = []
        for rel in gd_files():
            lines = read(rel)
            for i, raw in enumerate(lines, start=1):
                m = func_re.match(raw)
                if m:
                    seen.setdefault(m.group(1), []).append(f"{rel}:{i}")
            if sum(raw.count('preload("res://enemies/ai/profiles/') for raw in lines) > 3:
                registries.append(rel)
        for name, where in sorted(seen.items()):
            if len(where) > 1:
                for loc in where:
                    rel, line = loc.rsplit(":", 1)
                    self.err("L7", rel, int(line), f"func {name} defined {len(where)}× repo-wide — keep the one engine body")
        if len(registries) != 1:
            self.err("L7", registries[0] if registries else "enemies/ai/ProfileRegistry.gd", 0,
                     f"AI profile table defined in {len(registries)} scripts ({', '.join(registries) or 'none'}) — keep ProfileRegistry only")

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

    # -- L9 ------------------------------------------------------------------
    def scan_duck_typing(self) -> None:
        objs = "|".join(re.escape(h) for h in OBJECT_HANDLES + DUCK_HANDLES)
        duck_re = re.compile(rf"(?<![\w.])(?:{objs})\.(?:get|set)\(\s*\"(\w+)\"")
        in_re = re.compile(rf"\"(\w+)\"\s+in\s+(?:{objs})\b")
        rules = set(RULES_FILES)
        for rel in gd_files():
            if not any(rel.startswith(d + "/") for d in DUCK_DIRS) or rel in rules:
                continue  # rules files already get the same checks as L4
            if rel.endswith("VFX.gd") or rel.startswith("combat/effects/vfx/"):
                continue
            for i, raw in enumerate(read(rel), start=1):
                line = strip_comment(raw)
                if "has_method(" in line:
                    self.err("L9", rel, i, "has_method( — duck typing; call a typed member")
                for m in duck_re.finditer(line):
                    self.err("L9", rel, i, f'.get/.set("{m.group(1)}") on an object — use the typed member')
                for m in in_re.finditer(line):
                    self.err("L9", rel, i, f'"{m.group(1)}" in <object> — use the typed member')

    # -- L10 -----------------------------------------------------------------
    def scan_vfx_timers(self) -> None:
        import glob
        hits: list[tuple[str, int]] = []
        for f in sorted(glob.glob(os.path.join(ROOT, "combat/effects/*VFX.gd"))):
            rel = os.path.relpath(f, ROOT)
            for i, raw in enumerate(read(rel), start=1):
                if "await get_tree().create_timer" in strip_comment(raw):
                    hits.append((rel, i))
        if len(hits) > L10_BASELINE:
            rel, i = hits[-1]
            self.err("L10", rel, i, f"{len(hits)} `await get_tree().create_timer` in *VFX.gd (baseline {L10_BASELINE}) "
                     "— sequence the VFX with VfxSequence instead")

    # -- L11 -----------------------------------------------------------------
    def scan_scene_handles(self) -> None:
        scene_names = declared(SCENE) | NODE_MEMBERS
        handles = "|".join(re.escape(h) for h in SCENE_HANDLES)
        state_re = re.compile(rf"(?<![\w.])(?:{handles})\.state\.(\w+)")
        scene_re = re.compile(rf"(?<![\w.])(?:{handles})\.(\w+)")
        for rel in gd_files():
            if rel == SCENE or not any(rel.startswith(d + "/") for d in SCENE_HANDLE_DIRS):
                continue
            for i, raw in enumerate(read(rel), start=1):
                line = re.sub(r'"[^"]*"', '""', strip_comment(raw))
                for m in state_re.finditer(line):
                    if m.group(1) not in self.state:
                        self.err("L11", rel, i, f"`{m.group(0)}` — CombatState declares no `{m.group(1)}`")
                for m in scene_re.finditer(line):
                    if m.group(1) not in scene_names:
                        self.err("L11", rel, i, f"`{m.group(0)}` — CombatScene declares no `{m.group(1)}`")

    def run(self) -> int:
        self.scan_rng()
        for rel in RULES_FILES:
            self.scan_shell(rel)
            self.scan_seam(rel)
        self.scan_setup_stats()
        self.scan_pairs()
        self.scan_engine_waits()
        self.scan_single_definitions()
        self.scan_presentation_mutation()
        self.scan_duck_typing()
        self.scan_vfx_timers()
        self.scan_scene_handles()
        return sum(1 for e in self.errors if e.split(" ", 1)[0] in ENFORCED)


def main() -> int:
    if "--report-pairs" in sys.argv:
        # Plan 4.4 gate: funcs defined on both CombatScene and CombatState
        # (one-line scene delegates to the state) — should be none.
        pairs = sorted(declared_funcs(SCENE) & declared_funcs(STATE))
        for name in pairs:
            print(f"pair {name}")
        print(f"report-pairs: {len(pairs)}")
        return min(len(pairs), 255)
    quiet = "--quiet" in sys.argv
    show_all = "--all" in sys.argv
    linter = Linter()
    count = linter.run()
    pending: dict[str, int] = {}
    for e in linter.errors:
        rule = e.split(" ", 1)[0]
        if rule in ENFORCED:
            if not quiet:
                print(e)
        else:
            pending[rule] = pending.get(rule, 0) + 1
            if show_all:
                print(e)
    tail = ""
    if pending:
        tail = " (not yet enforced: " + ", ".join(f"{r} {n}" for r, n in sorted(pending.items())) + ")"
    print(f"lint_engine: {count} error{'s' if count != 1 else ''}{tail}")
    return min(count, 255)


if __name__ == "__main__":
    sys.exit(main())
