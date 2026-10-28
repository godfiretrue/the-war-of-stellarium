# AI_CONTEXT — The Final War of Stellarium

Read this before changing gameplay code. It records the architecture, the
conventions the project depends on, and the traps already hit once.

## Status

Playable MVP: main menu, 7-province map, turn cycle, recruitment, movement,
numeric combat, behaviour-tree bot, HUD with battle summary, victory/defeat
screen, JSON save/load with auto-save each turn.

Engine: **Godot 4.7.2-stable** (the brief said 4.6.1; the project was created
with 4.7 features and runs on the installed editor). GDScript only.

**LimboAI v1.8.1 is installed and used** (`res://addons/limboai`, GDExtension).
The bot's decision structure is a behaviour tree built in code; the leaves are
GDScript tasks under `scripts/ai/tasks/`. The tree is:

```
Sequence "Elf turn"
├── Recruit                     BTRecruitTask
└── Selector "Attack or advance"
    ├── Attack                  BTAttackTask  (fails when no battle happened)
    └── Advance                 BTAdvanceTask
```

Because the selector is exclusive, a turn where the bot fights does **not**
also advance. That is a deliberate change from the first rule-based version
(which always advanced) and it makes games shorter — see Balance.

## Layout

```
scenes/ui/main_menu.tscn      main scene; New Game / Continue / Quit
scenes/map/map.tscn           gameplay scene: MapView + Bot + HUD instance
scenes/map/province.tscn      Area2D hexagon, built at runtime from ProvinceData
scenes/ui/hud.tscn            top bar + bottom action bar
scripts/data/balance.gd       every tuning number
scripts/data/province_data.gd ProvinceData Resource (owner, garrison, terrain)
scripts/data/map_state.gd     province graph + win/elimination queries
scripts/data/map_factory.gd   the fixed 7-province layout (edit here)
scripts/data/unit_type.gd     unit stats Resource
scripts/data/unit_catalog.gd  builds UnitType cache from Balance.UNIT_DEFS
scripts/core/game_state.gd    autoload "Game": stockpiles, income, actions
scripts/core/turn_manager.gd  autoload "TurnManager": phases + signals
scripts/core/combat_resolver.gd  pure numeric combat
scripts/core/save_system.gd   JSON save/load, versioning, atomic write
scripts/ai/bot_controller.gd  BT-driven bot (also used for headless sims)
scripts/ai/tasks/bt_*.gd      tree leaves: recruit, attack, advance
scripts/ui/hud.gd             player controller: selection, march, recruit
scripts/ui/main_menu.gd       menu actions
```

## Architecture rules

- `Game` is the single source of truth: map + gold/manpower/faction resource.
  It has no node references, so a whole game can be simulated without a scene.
- `TurnManager` owns the phase machine and emits signals. It never calls the
  bot or the HUD directly. Phases: `PLAYER_TURN` -> `BOT_TURN` ->
  `RESOLUTION` -> `NEXT_TURN` -> `PLAYER_TURN`.
- The bot calls `TurnManager.finish_bot_turn()` when it is done; that keeps AI
  code out of the turn manager.
- Player and bot use the **same** `Game.recruit()` / `Game.move()` methods, so
  the bot cannot break the rules the player follows.
- The behaviour tree only orchestrates. Decision logic lives in
  `BotController` (`recruit_phase`, `attack_phase`, `advance_phase`), and the
  leaves are deliberately duck-typed (`has_method`) so the task scripts do not
  reference `BotController` by class name — that would be a circular class
  dependency.
- `MapView` renders and hit-tests; it does not mutate game state. `GameHUD`
  turns clicks into `Game` actions.
- Custom Resources never hold node references (only ids/values), per project
  rules.

## Rules implemented

- 7 provinces, symmetric-ish graph, 2 factions + 3 neutral provinces.
- Income at resolution: 15 gold and 5 manpower per province, capital +8/+2,
  faction resource (Humans: Aether on Plains, Elves: Iron on Mountains) +2.
- Upkeep per army: `ceil(avg_unit_cost / 15 * troops ^ 1.2)`.
- Recruit anywhere you own. Humans pay 0.7x; Elves get 1.15x income.
- Movement only between adjacent provinces; moving into an undefended province
  captures it.
- One attack per province per round (`acted_provinces`, cleared at resolution).
- Combat: attacker `sum(atk*count)`, defender `sum(def*count) * terrain`
  (Plains 1.0, Mountains 1.25), both x random 0.9-1.1.
  `ratio = att/(att+def)`; attacker loses `ceil(att*(1-ratio)*0.7)`,
  defender loses `ceil(def*ratio*1.0)`.
- Win: own every province. Lose: own none.

## Balance findings (measured, not guessed)

`BotController` supports `bot_faction` and `auto_play=false`, which is how the
AI-vs-AI runs were done. Set `Game.quiet = true` first or the log floods.

```gdscript
var human_bot = BotController.new()
human_bot.bot_faction = 0
human_bot.auto_play = false
root.get_node("Map").add_child(human_bot)
game.quiet = true
tm.start_game()
while not tm.game_over:
    human_bot.play_turn()
    tm.end_player_turn()
```

Measured with 16 runs per configuration:

| Config | Result |
|---|---|
| humans 0.7, elves 1.15, rule-based bot, impatience 3 | humans 16/16, ~9 turns |
| humans 0.7, elves 1.15, behaviour tree, impatience 3 | humans 14/16, ~5.4 turns |

**The 45-55% target is not met.** Two separate causes, both structural:

1. The player faction resolves first in a round, so when both sides become
   impatient the first mover wins the decisive battle.
2. Conquest snowballs: losing a capital kills recruitment, and provinces left
   with the 1-troop advance reserve fall quickly, so games now end in ~5 turns.

Fixing 1 needs simultaneous resolution (queue both sides' attacks, resolve
once). Fixing 2 needs either larger garrisons, lower combat lethality
(`DEFENDER_LOSS_FACTOR` / `ATTACKER_LOSS_FACTOR`) or upkeep-free home armies.
Do not tune by cost multipliers alone; measure 20+ runs.

## Conventions and gotchas

- snake_case, tabs, one class per file, `class_name` on data/system classes.
- Do **not** declare `class_name Health` (LimboAI ships one) — `CombatHealth`
  is the agreed alternative. Do not name a variable `range`.
- A script cannot reference its own `class_name` at creation time (it is not
  in the global class table yet). Construction lives in `UnitCatalog` /
  `MapFactory` for that reason.
- New `class_name` scripts need `filesystem_manage(op="scan")` before another
  script can use them as a type.
- Autoloads are resolved with `get_node_or_null("/root/Game")` instead of the
  bare global name. The editor's autoload cache can be stale after
  `autoload_manage` writes `project.godot`; tree lookup always works.
- `BehaviorTree.instantiate(agent, blackboard, owner, scene_root)` rejects a
  null blackboard **and** a null scene root. Pass `Blackboard.new()` and
  `get_tree().current_scene`; a bot instanced at runtime has no scene owner,
  so the explicit scene root is required.
- LimboAI tasks: a GDScript leaf extends `BTAction` and implements
  `_tick(delta) -> int` returning `BT.SUCCESS` / `BT.FAILURE` / `BT.RUNNING`.
  This bot never returns `RUNNING` — a turn is resolved in one tick.
- JSON parses every number as float: cast with `int()` when loading saves.
- Saves go to `user://savegame.json` via a `.tmp` file + rename. Never `.tres`.
- After an editor tool write, `GDScript::reload ... error code 43` diagnostics
  are frequently bogus — verify by running the project, not by the diagnostic.
  A script that once failed to parse stays poisoned; delete and recreate it.
- Controls added by `build_layout` lose their offsets when an anchor preset is
  applied afterwards: set offsets again on the source scene.
- Scene-root `Control` nodes are not viewport-sized; call
  `set_anchors_and_offsets_preset(PRESET_FULL_RECT)` in `_ready()`.
- `ColorRect` and containers default to `MOUSE_FILTER_STOP`; set 2 (IGNORE) on
  backgrounds or map clicks never reach the map.
- LimboAI icons must be imported: if the editor was open when the addon was
  copied in, run a filesystem scan before trusting `Failed loading ... ctex`
  errors.

## Not implemented (post-MVP, do not add now)

Heroes and spells, morale/desertion, real-time tactical battles, diplomacy,
governments/laws, End of the World events, Rats faction.

## Next steps

1. Simultaneous attack resolution to fix first-mover snowballing.
2. Lengthen games: raise starting garrisons or lower combat lethality, then
   re-measure 20+ AI-vs-AI runs.
3. Optional: author the tree as a `.tres` in the LimboAI editor instead of
   code, once the shape is stable.
