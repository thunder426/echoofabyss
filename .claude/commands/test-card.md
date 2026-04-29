---
description: Set up a test combat scene to play specific cards and verify their effects
argument-hint: <card_id1> [card_id2 ...] — card IDs from CardDatabase.gd
---

Set up the "Card Test" preset in TestLaunchScene.gd so the user can test specific cards in the combat scene.

Cards to test: $ARGUMENTS

## Steps

1. **Look up each card ID** in `echoofabyss/cards/data/CardDatabase.gd`. For each card, determine:
   - Card type: Minion (`MinionCardData`), Spell (`SpellCardData`), Trap (`TrapCardData`), or Environment (`EnvironmentCardData`)
   - Pool: check the `_card_pools` dictionary near the bottom of CardDatabase.gd. Enemy-only pools are: `feral_imp_clan`, `abyss_cultist_clan`, `void_rift`, `void_castle`. Cards with pool `""` are tokens.
   - Targeting: for spells check `requires_target` and `target_type`; for minions check `on_play_requires_target` and `on_play_target_type`
   - Cost type & amount: essence (minions, `essence_cost`) vs mana (spells/traps/environments, `mana_cost`). Record the numeric cost — needed later for starting-resource sizing.
   - Does the card summon minions? Scan `description`, `effect_steps`, and `hardcoded_id` for "summon"/"Summon". Track this per card.

   If a card ID is not found, tell the user and stop.

2. **Classify each card** as player-side or enemy-side:
   - Cards in enemy-only pools (`feral_imp_clan`, `abyss_cultist_clan`, `void_rift`, `void_castle`) or token pool (`""`) → enemy-side
   - All other cards → player-side

3. **Determine what board setup is needed** based on all cards' targeting AND whether the card summons minions:
   - If an **enemy-side** card summons minions (e.g. Brood Call, imp summons) → leave `_enemy_board_input` EMPTY so the enemy board fills up from the card's own summons during the test. Overriding with pre-placed minions obscures what the card actually produces.
   - Otherwise, apply targeting rules:
     - `target_type` / `on_play_target_type` contains `"enemy_minion"` or `"enemy_minion_or_hero"` → needs enemy minions on board
     - `target_type` / `on_play_target_type` contains `"friendly_minion"`, `"friendly_demon"`, `"friendly_human"`, `"friendly_void_imp"`, `"friendly_feral_imp"` → needs friendly minions on player board (pick appropriate type: use `abyssal_brute` for demon, `abyss_cultist` for human, `void_imp` for void_imp, `rabid_imp` for feral_imp, `shadow_hound` as generic fallback)
     - `target_type` / `on_play_target_type` contains `"any_minion"` → needs at least one enemy minion
     - `target_type` / `on_play_target_type` contains `"trap_or_env"` → place a trap on enemy side (use `hidden_ambush`)
     - No targeting needed and not a summoner → just ensure some enemy minions exist for general combat context

   Default enemy board (when enemy targets needed): `"shadow_hound, abyssal_brute, void_stalker"`
   Default player board (when friendly targets needed): pick 2-3 appropriate minions based on the type constraint above.

   **Board clear in player hand**: if ANY enemy-side card summons minions (or if the enemy board will grow during the test), also give the player a cheap AOE spell so they can reset the board. Default choice: `abyssal_plague` (2 mana, corrupts + damages all enemy minions). Add it to `_hand_input` as `abyssal_plague, abyssal_plague, abyssal_plague`.

4. **Build the preset values**:
   - `_hand_input.text`: comma-separated list of player-side card IDs (duplicated 2-3 times each). If the enemy side summons minions, prepend `abyssal_plague, abyssal_plague, abyssal_plague` for board clear.
   - `_enemy_hand_input.text`: comma-separated list of enemy-side card IDs (duplicated 2-3 times each)
   - `_enemy_deck_input.text`: same enemy-side card IDs duplicated 4-6 times (so the enemy AI will play them)
   - `_player_board_input.text`: friendly minions if any card needs friendly targets
   - `_enemy_board_input.text`: enemy minions if any card needs enemy targets (default `"shadow_hound, abyssal_brute, void_stalker"`). **Leave EMPTY if any enemy-side card summons minions** — let the card populate the board itself.
   - `_player_deck_input.text`: leave empty (we don't want random draws diluting the test)
   - `_player_traps_input.text` / `_enemy_traps_input.text`: empty unless trap_or_env targeting needed
   - `_enemy_name_input.text`: `"Card Test Dummy"`
   - `_player_hp_input.value`: `9999`
   - `_enemy_hp_input.value`: `9999`
   - `_inf_res_check.button_pressed`: `true` (infinite resources so cards are always playable)
   - `_preset_enemy_start_essence_max`: set to the highest `essence_cost` across all enemy-side cards (so the AI can cast its minions on turn 1). `0` if no enemy-side card uses essence.
   - `_preset_enemy_start_mana_max`: set to the highest `mana_cost` across all enemy-side cards (so the AI can cast its spells/traps/environments on turn 1). `0` if no enemy-side card uses mana.
   - Keep both values reasonable — don't exceed ~8 each. If a card costs more, cap at the card's cost.

5. **Edit `_preset_card_test()`** in `echoofabyss/debug/TestLaunchScene.gd` — update the function body with the computed values. Only modify the `_preset_card_test` function, leave everything else untouched. This includes the two preset-scoped lines near the end:
   ```
   _preset_enemy_start_essence_max = <int>
   _preset_enemy_start_mana_max    = <int>
   ```
   These are wired through `_on_launch_pressed` into `TestConfig.enemy_start_essence_max` / `enemy_start_mana_max`, which `CombatScene._apply_test_config()` uses to bump `enemy_ai.essence_max` / `enemy_ai.mana_max` above the default of 1 so enemy spells/minions are castable on turn 1.

6. **Report to the user** what you set up:
   - Which cards go to player hand vs enemy hand
   - What board state was pre-configured and why
   - Remind them to open the TestLaunchScene in Godot (the "Card Test" preset is selected by default) and click "Launch Test Combat"
