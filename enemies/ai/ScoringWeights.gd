## ScoringWeights.gd
## Tunable weight parameters for the scoring-based AI system.
## Specialized profiles create an instance and override fields in _init().
class_name ScoringWeights
extends RefCounted

# ---------------------------------------------------------------------------
# Minion value weights (stats are on ×100 scale: 500 ATK = display "5")
# ---------------------------------------------------------------------------

## Per-point weight on effective ATK.
var atk_weight: float = 1.0

## Per-point weight on current HP.
var hp_weight: float = 0.5

## Per-point weight on current shield.
var shield_weight: float = 0.4

## Flat bonus for Guard keyword.
var guard_bonus: float = 150.0

## Flat bonus for Lifedrain keyword.
var lifedrain_bonus: float = 200.0

## Flat bonus for Deathless keyword/buff.
var deathless_bonus: float = 300.0

## Bonus when minion is in SWIFT state (can attack this turn).
var swift_bonus: float = 50.0

## Bonus per 100 shield regen/turn (REGEN_1 = ×1, REGEN_2 = ×2).
var shield_regen_bonus: float = 100.0

## Per-point weight on on-death effect value estimates.
var on_death_weight: float = 0.5

## Per-point weight on passive aura value estimates.
var passive_weight: float = 0.5

# ---------------------------------------------------------------------------
# Board-level weights
# ---------------------------------------------------------------------------

## Per-point weight on hero HP advantage (friendly_hp - opponent_hp).
var hero_hp_weight: float = 0.3

## Per-card weight on hand size advantage.
var hand_size_weight: float = 50.0

## Per-minion weight on board count advantage.
var board_count_weight: float = 30.0

## Penalty when our board is empty and opponent has minions.
var empty_board_penalty: float = 200.0

## Bonus for playing a minion per empty slot remaining (encourages flooding).
## At default 80.0: playing into 4 empty slots = +320 bonus, 1 empty slot = +80.
var board_fill_bonus: float = 80.0

# ---------------------------------------------------------------------------
# Attack scoring
# ---------------------------------------------------------------------------

## Multiplier on hero damage value (higher = more aggro).
var face_damage_weight: float = 1.8

## Massive bonus when an attack would kill the opponent hero.
var lethal_bonus: float = 99999.0

## Per-point penalty for overkill damage (wasted damage on a minion).
var overkill_penalty: float = 0.3

# ---------------------------------------------------------------------------
# Lookahead
# ---------------------------------------------------------------------------

## Discount factor on the opponent's estimated response (uncertainty).
## Lower = less cautious. 0.4 balances awareness without over-penalizing aggression.
var lookahead_discount: float = 0.4

# ---------------------------------------------------------------------------
# Resource growth
# ---------------------------------------------------------------------------

## Multiplier on the "value unlocked by growing this resource" calculation.
var resource_unlock_weight: float = 1.0

# ---------------------------------------------------------------------------
# Thresholds
# ---------------------------------------------------------------------------

## Minimum score improvement required to execute an action.
## Prevents the AI from making marginally negative plays.
var action_threshold: float = 0.0

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func duplicate_weights() -> ScoringWeights:
	var w := ScoringWeights.new()
	w.atk_weight = atk_weight
	w.hp_weight = hp_weight
	w.shield_weight = shield_weight
	w.guard_bonus = guard_bonus
	w.lifedrain_bonus = lifedrain_bonus
	w.deathless_bonus = deathless_bonus
	w.swift_bonus = swift_bonus
	w.shield_regen_bonus = shield_regen_bonus
	w.on_death_weight = on_death_weight
	w.passive_weight = passive_weight
	w.hero_hp_weight = hero_hp_weight
	w.hand_size_weight = hand_size_weight
	w.board_count_weight = board_count_weight
	w.empty_board_penalty = empty_board_penalty
	w.board_fill_bonus = board_fill_bonus
	w.face_damage_weight = face_damage_weight
	w.lethal_bonus = lethal_bonus
	w.overkill_penalty = overkill_penalty
	w.lookahead_discount = lookahead_discount
	w.resource_unlock_weight = resource_unlock_weight
	w.action_threshold = action_threshold
	return w
