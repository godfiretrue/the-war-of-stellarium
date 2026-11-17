# AI_CONTEXT — The Final War of Stellarium

Read this before changing gameplay code. It records the architecture, the
conventions the project depends on, and the traps already hit once.

## Status

Playable MVP: main menu, procedurally generated 21-province continent, turn
cycle, recruitment, movement, numeric combat, behaviour-tree bot, HUD with
battle summary, victory/defeat screen, JSON save/load with auto-save each turn.
The whole UI is localized in Portuguese and English, switchable in-game from a
settings panel (language + fullscreen) and persisted between runs.

Turns are **simultaneous**: the player queues orders, the bot queues its own
orders without seeing them, and only then does one snapshot-based resolution
apply both sides. Pressing March or Recruit never changes the board by itself.

Engine: **Godot 4.7.2-stable** (the brief said 4.6.1; the project was created
with 4.7 features and runs on the installed editor). GDScript only.

**LimboAI v1.8.1 is installed and used** (`res://addons/limboai`, GDExtension).
The bot's decision structure is a behaviour tree built in code; the leaves are
GDScript tasks under `scripts/ai/tasks/`. The tree is:

```
Sequence "Elf turn"
├── Recruit                     BTRecruitTask
└── Sequence "Attack, then advance"
    ├── Attack                  BTAttackTask  (always succeeds)
    └── Advance                 BTAdvanceTask
```

Attack and advance both run every turn. That is a deliberate change: with the
old exclusive selector a single available battle suppressed all expansion,
which left fronts frozen and produced seeds where the war never ended. The
advance leaf takes undefended neighbours first, then paths toward the enemy
capital or neutral ground, and refuses a two-way swap with an army already
marching the other way — see Balance.

## Layout

```
scenes/ui/main_menu.tscn      main scene; New Game / Continue / Settings / Quit
scenes/map/map.tscn           gameplay scene: MapView + Bot + HUD instance
scenes/map/province.tscn      Node2D per province, built at runtime from ProvinceData
scenes/ui/hud.tscn            top resource bar + bottom selection/action dock
scenes/ui/settings_panel.tscn reusable overlay: language + fullscreen
shaders/terrain.gdshader      terrain painter: relief, biomes, sea, snow
scripts/data/balance.gd       every tuning number
scripts/data/province_data.gd ProvinceData Resource (owner, garrison, terrain)
scripts/data/map_state.gd     province graph, label grid, rivers, win queries
scripts/data/world_generator.gd  procedural continent (elevation, rivers, provinces)
scripts/data/map_factory.gd   entry point: seed -> MapState + starting armies
scripts/data/unit_type.gd     unit stats Resource
scripts/data/unit_catalog.gd  builds UnitType cache from Balance.UNIT_DEFS
scripts/core/game_state.gd    autoload "Game": stockpiles, income, actions
scripts/core/turn_manager.gd  autoload "TurnManager": phases + signals
scripts/core/settings.gd      autoload "Settings": language + fullscreen (user://settings.cfg)
scripts/core/loc.gd           every PT/EN string and display-time helpers
scripts/core/combat_resolver.gd  pure numeric combat
scripts/core/save_system.gd   JSON save/load, versioning, atomic write
scripts/ai/bot_controller.gd  BT-driven bot (also used for headless sims)
scripts/ai/tasks/bt_*.gd      tree leaves: recruit, attack, advance
scripts/ui/hud.gd             player controller: selection, march, recruit
scripts/ui/main_menu.gd       menu actions
scripts/ui/settings_panel.gd  settings overlay logic (shared by menu + HUD)
scripts/ui/ui_style.gd        shared palette and button styleboxes
scripts/tools/worldgen_sweep.gd  headless seed sweep (invariant test)
scripts/tools/balance_sim.gd     headless AI-vs-AI balance runner (20 games)
```

## Architecture rules

- `Game` is the single source of truth: map + gold/manpower/faction resource.
  It has no node references, so a whole game can be simulated without a scene.
- `TurnManager` owns the phase machine and emits signals. It never calls the
  bot or the HUD directly. Phases: `PLAYER_PLANNING` -> `BOT_PLANNING` ->
  `RESOLUTION` -> `NEXT_TURN` -> `PLAYER_PLANNING`.
- `end_player_turn()` starts bot planning; the bot calls
  `finish_bot_planning()` when it is done; only then does `_resolve()` run.
  Keeping AI code out of the turn manager is what makes a headless run a loop
  of `bot.play_turn()` + the two turn calls.
- Player and bot use the **same** `Game.queue_move()` / `queue_recruit()` /
  `cancel_order()` methods and both queue the same plain dictionary orders, so
  the bot cannot break the rules the player follows and never reads the
  player's queue (it only sees board state).
- `GameState.resolve_turn()` is the only code that mutates owners and
  garrisons. Planning code validates and records; it never applies an action.
- The behaviour tree only orchestrates. Decision logic lives in
  `BotController` (`recruit_phase`, `attack_phase`, `advance_phase`), and the
  leaves are deliberately duck-typed (`has_method`) so the task scripts do not
  reference `BotController` by class name — that would be a circular class
  dependency.
- `MapView` renders and hit-tests; it does not mutate game state. `GameHUD`
  turns clicks into queued orders.
- Data values stay English (`territory_type` = "River Town", unit ids, save
  fields). Translation happens only at display time through `Loc`
  (`Loc.territory_type`, `Loc.unit_name`, `Loc.t`). Never translate a value
  before storing or comparing it.
- `Settings` is the only writer of `user://settings.cfg` and the only place
  that changes `Loc.language`. It emits `changed`; open screens rebuild their
  text in place instead of reloading the scene.
- `UiStyle` owns the palette and the styleboxes shared by the menu, the HUD and
  the settings panel. New screens take their look from it rather than building
  their own `StyleBoxFlat`s.
- Custom Resources never hold node references (only ids/values), per project
  rules.

## Rules implemented

- 21 provinces generated per seed; 6 of them are guaranteed anchors (two
  capitals, three fortresses, one river town), the rest are generated and
  neutral. The province graph is always connected.
- 2 factions + neutral provinces; each faction starts with a connected block
  around its capital (~30% of the map, clamped 5-8 provinces).
- 10 cities per map: the 6 anchors plus up to 4 promoted towns.
- Recruitment is only allowed in cities/castles (`ProvinceData.is_city`); open
  corridors are movement-only.
- Income at resolution: 15 gold and 5 manpower per province, capital +8/+2,
  faction resource (Humans: Aether on Plains, Elves: Iron on Mountains) +2.
- Upkeep per army: `ceil(avg_unit_cost / 15 * troops ^ 1.2)`.
- Humans pay 0.7x recruitment; Elves get 1.15x income.
- Orders are validated when queued, against the current board **and** the units
  already committed from the same origin. A province may send many friendly
  marches but at most one attack order per turn. Recruit gold/manpower are
  reserved at queue time and refunded by `cancel_order()`.
- Movement only between adjacent provinces. Units are not removed while
  planning; the garrison is only read to validate later orders.
- Resolution works from one snapshot taken before any order:
  1. recruits join their province's garrison first (they defend, but moves were
     validated before they existed, so they never march);
  2. every army leaves its origin at once; what stays behind is that
     province's only defence;
  3. destinations resolve in a seed-shuffled order — never faction order — so
     neither side has first-mover advantage.
- Defence is the snapshot garrison plus friendly reinforcements arriving this
  turn. An undefended province is taken without a fight; two factions arriving
  at the same undefended province fight a field battle; two armies swapping
  provinces also fight in the field. Field battles reuse `CombatResolver` on a
  throwaway plains `ProvinceData`.
- Survivors return to their origin only if their faction still owns it after
  every capture; otherwise they are lost.
- Combat: attacker `sum(atk*count)`, defender `sum(def*count) * terrain`
  (Plains 1.0, Mountains 1.25), both x random 0.9-1.1.
  `ratio = att/(att+def)`; attacker loses `ceil(att*(1-ratio)*0.7)`,
  defender loses `ceil(def*ratio*1.0)`.
- Income and upkeep are applied after resolution, then the next planning phase
  starts. Win: own every province. Lose: own none.

## World generation

`MapFactory.create_default_map(seed)` -> `WorldGenerator.build(seed)` returns a
finished `MapState`; negative seed means "pick a random one". Everything the
map needs (fields, rivers, province shapes, names, owners) is derived from the
seed, so a save only stores the seed (see save version note below).

Grid: **288x162 cells of 4 px**, covering the fixed 1152x648 world.
`MapState.grid_size` / `cell_size` describe it; `MapState.label_grid` maps a
cell to a province index.

Pipeline (`world_generator.gd`):

1. `_generate_fields` - warped elliptical landmass + a mountain field built by
   `_build_ranges`/`_apply_ranges` (long tapered chains of segments, never
   radial blobs: noise-only belts produced worm/crater artifacts). Then
   `_carve_anchor_passes` keeps plains/coast anchors low. Moisture has a
   west-to-east rain shadow behind ranges, temperature has latitude plus a
   lapse rate.
2. `_keep_main_land` - drops disconnected islands so the continent is one piece.
3. `_trace_rivers` - `_priority_flood` fills depressions (adding a tiny
   `FILL_EPSILON` per step so basin floors keep a downhill gradient),
   `_compute_drainage` picks the steepest descent and accumulates, cells above
   `RIVER_MIN_DRAINAGE` become river, and `_extract_rivers` turns them into
   smoothed polylines with a width from the accumulated volume. Without the
   epsilon, flat lake beds made rivers coil in concentric loops.
4. `_grow_provinces` - 6 anchors are fixed, the rest are grown by seeded
   multi-source BFS until `TARGET_PROVINCES` (21) regions exist; a retry loop
   merges/regrows until the graph is connected.
5. `_assemble_state` - classification (mountain/forest/coast/plains), names,
   cities, ownership, polygons, and the RGB field image for the shader.

Rendering: `map_view.gd` feeds `MapState.field_image` (R=elevation,
G=moisture, B=temperature) to `shaders/terrain.gdshader`, which paints sea,
biomes, hill-shaded relief, rock and snow. Rivers and march routes are drawn by
`_draw_overlay` on a node above the provinces. `province_view.gd` only adds
ownership tint, borders and markers.

Invariants are checked by `scripts/tools/worldgen_sweep.gd` (24 seeds, ~700-
1000 ms per world, exits 1 on failure):

```
godot --headless --path . --script res://scripts/tools/worldgen_sweep.gd
```

It asserts 21 provinces, all 6 anchors present, connected graph, non-empty
polygons, exactly 10 cities, at least 6 rivers and at least 3 provinces per
faction. Run it after any change to generation.

## Balance findings (measured, not guessed)

`BotController` supports `bot_faction` and `auto_play=false`, which is how the
AI-vs-AI runs were done. `scripts/tools/balance_sim.gd` drives 20 fixed seeds
(`41000..41019`, 400-turn cap, autosave off):

```
godot --headless --path . --script res://scripts/tools/balance_sim.gd
```

It queues both sides' orders through the real GameState API and counts queue
failures, unfinished games and turn length:

| Config | Result |
|---|---|
| humans 0.7, elves 1.15, simultaneous resolution, 20 games | Elves 19, Humans 1; 5% / 95%; 57.1 turns average; 0 unfinished; 0 queue failures |

The first-mover advantage is gone: resolution order is seeded, not faction
order. The remaining split follows the faction modifiers (Humans pay 0.7x to
recruit, Elves get 1.15x gold/manpower) plus the Elves' stronger early army.
A 95/5 split is still lopsided, but the task here was to remove the
sequential-turn unfairness and make every seed finish, not to rebalance the
factions. Do not tune by cost multipliers alone; re-measure with the 20-game
runner above.

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
  `autoload_manage` writes `project.godot`; tree lookup always works. The
  settings autoload is typed at the call site: `var _settings: GameSettings =
  get_node("/root/Settings")` (its script has `class_name GameSettings` because
  a class name may not equal the autoload name).
- All player-facing text goes through `Loc`; a new string needs a key in **both**
  tables (`pt` and `en`) or `Loc.t` warns and returns the raw key. Literal keys
  used in scripts are checked by `Loc.STRINGS`; dynamic `battle_*` keys are
  literals too, so keep them quoted.
- HUD buttons use `focus_mode = NONE` and shortcuts live in
  `GameHUD._unhandled_key_input` (Space end turn, M march, Esc cancel, S save,
  R recruit). Never rely on a focused button for a shortcut: a focused button
  would swallow Space.
- Hand-written UIDs (`uid://mycustomid`) are rejected: Godot warns and falls
  back to the text path. Use the UID from the generated `.uid` sidecar.
- A full-rect, left-anchored `MenuMargin` whose child's minimum width exceeds
  its anchor rectangle grows in both directions when `grow_horizontal = 2`,
  pushing the menu off-screen. Keep `grow_horizontal = 1` (END) on the menu
  container.
- `BehaviorTree.instantiate(agent, blackboard, owner, scene_root)` rejects a
  null blackboard **and** a null scene root. Pass `Blackboard.new()` and
  `get_tree().current_scene`; a bot instanced at runtime has no scene owner,
  so the explicit scene root is required.
- LimboAI tasks: a GDScript leaf extends `BTAction` and implements
  `_tick(delta) -> int` returning `BT.SUCCESS` / `BT.FAILURE` / `BT.RUNNING`.
  This bot never returns `RUNNING` — a turn is resolved in one tick.
- JSON parses every number as float: cast with `int()` when loading saves.
- Saves go to `user://savegame.json` via a `.tmp` file + rename. Never `.tres`.
- Save `VERSION` is **3**. World generation renames/moves generated provinces,
  so old saves cannot be rebuilt: `_migrate` returns `{}` for any version that
  is not the current one and the caller treats that as "no save".
- Orders are plain dictionaries (`{"type": "move", ...}`), never Resources or
  actions. Validation happens at queue time, so build orders through
  `queue_move()` / `queue_recruit()`; `resolve_turn()` trusts what it is given.
- Saves are written only at the start of a turn with an empty queue, and
  `SaveSystem.save_game()` refuses when orders are queued. The HUD disables
  Save for the same reason, so a load always resumes at a clean turn.
- The Orders and Battle cards are top-anchored and size to their content;
  `CARD_MAX_HEIGHT_RATIO` caps their scroll areas at 45% of the screen, so long
  lists scroll instead of pushing the card off-screen. Check both at 1152x648
  after changing row heights.
- A `PackedInt32Array` fetched from a `Dictionary`/`Array` with `as` is a
  **copy**; mutate the original or write it back. `PackedInt32Array` has no
  `pop_back` (convert to `Array` first).
- World geometry is hard-coded to 1152x648: ellipse centre (576, 286), radii
  (575, 240), shader `world_size`, grid 288x162 with `CELL = 4`. Change the
  window size and all four must move together.
- In `game_eval`, `gen.call(...)` returns `Variant`, so annotate noise locals
  (`var warp: FastNoiseLite = gen.call(...)`) or GDScript fails to infer types.
  A runtime error there leaves the game loop frozen (`EVAL_GAME_NOT_READY`);
  restart the project rather than retrying.
- After an editor tool write, `GDScript::reload ... error code 43` diagnostics
  are frequently bogus — verify by running the project, not by the diagnostic.
  A script that once failed to parse stays poisoned; delete and recreate it.
- Controls added by `build_layout` lose their offsets when an anchor preset is
  applied afterwards: set offsets again on the source scene.
- Scene-root `Control` nodes are not viewport-sized; call
  `set_anchors_and_offsets_preset(PRESET_FULL_RECT)` in `_ready()`. A `Control`
  whose parent is a `CanvasLayer` is sized against the viewport, so the same
  call is what makes the settings dim layer cover the screen.
- `ColorRect` and containers default to `MOUSE_FILTER_STOP`; set 2 (IGNORE) on
  backgrounds or map clicks never reach the map.
- LimboAI icons must be imported: if the editor was open when the addon was
  copied in, run a filesystem scan before trusting `Failed loading ... ctex`
  errors.

## Not implemented (post-MVP, do not add now)

Heroes and spells, morale/desertion, real-time tactical battles, diplomacy,
governments/laws, End of the World events, Rats faction.

## Next steps

1. Lengthen games and even the split: raise starting garrisons or lower combat
   lethality, then re-measure with the 20-game runner.
2. Optional: author the tree as a `.tres` in the LimboAI editor instead of
   code, once the shape is stable.
3. Optional: the main menu still draws a visibly pixelated planet — replace it
   with a downscaled render of the generated field, or hide the planet.
4. Optional: gamepad navigation for the HUD. Buttons are `focus_mode = NONE`
   today so keyboard shortcuts never steal focus; a controller pass needs focus
   neighbours and a way to keep Space/M working while a button has focus.
