## CardDatabase.gd
## Autoload — holds every card definition in the game.
## Access any card by ID: CardDatabase.get_card("void_imp")
extends Node

## All registered cards keyed by their id string
var _cards: Dictionary = {}

func _ready() -> void:
	_register_wanderer_cards()

## Returns the CardData resource for a given id, or null if not found
func get_card(id: String) -> CardData:
	if _cards.has(id):
		return _cards[id]
	push_error("CardDatabase: unknown card id '%s'" % id)
	return null

## Returns a list of CardData for a given array of ids
func get_cards(ids: Array[String]) -> Array[CardData]:
	var result: Array[CardData] = []
	for id in ids:
		var card := get_card(id)
		if card:
			result.append(card)
	return result

# ---------------------------------------------------------------------------
# Registration helpers
# ---------------------------------------------------------------------------

func _register(card: CardData) -> void:
	if _cards.has(card.id):
		push_warning("CardDatabase: duplicate card id '%s'" % card.id)
	_cards[card.id] = card

# ---------------------------------------------------------------------------
# Wanderer starter cards
# ---------------------------------------------------------------------------

func _register_wanderer_cards() -> void:

	# --- Minions ---

	var void_imp := MinionCardData.new()
	void_imp.id             = "void_imp"
	void_imp.card_name      = "Void Imp"
	void_imp.cost           = 1
	void_imp.description    = "On play: deal 1 damage to the enemy hero."
	void_imp.atk            = 1
	void_imp.health         = 2
	void_imp.minion_type    = Enums.MinionType.DEMON
	void_imp.on_play_effect = "deal_1_enemy_hero"
	_register(void_imp)

	var shadow_hound := MinionCardData.new()
	shadow_hound.id             = "shadow_hound"
	shadow_hound.card_name      = "Shadow Hound"
	shadow_hound.cost           = 2
	shadow_hound.description    = "On play: gains +1 ATK for each other Demon on your board."
	shadow_hound.atk            = 2
	shadow_hound.health         = 3
	shadow_hound.minion_type    = Enums.MinionType.DEMON
	shadow_hound.on_play_effect = "shadow_hound_atk_bonus"
	_register(shadow_hound)

	var abyssal_brute := MinionCardData.new()
	abyssal_brute.id          = "abyssal_brute"
	abyssal_brute.card_name   = "Abyssal Brute"
	abyssal_brute.cost        = 4
	abyssal_brute.description = "Taunt."
	abyssal_brute.atk         = 3
	abyssal_brute.health      = 8
	abyssal_brute.minion_type = Enums.MinionType.DEMON
	abyssal_brute.keywords.append(Enums.Keyword.TAUNT)
	_register(abyssal_brute)

	# Wandering Spirit — spawned by hero power, not in deck
	var wandering_spirit := MinionCardData.new()
	wandering_spirit.id          = "wandering_spirit"
	wandering_spirit.card_name   = "Wandering Spirit"
	wandering_spirit.cost        = 0
	wandering_spirit.description = "Summoned by hero power."
	wandering_spirit.atk         = 1
	wandering_spirit.health      = 2
	wandering_spirit.minion_type = Enums.MinionType.SPIRIT
	_register(wandering_spirit)

	# --- Spells ---

	var soul_leech := SpellCardData.new()
	soul_leech.id             = "soul_leech"
	soul_leech.card_name      = "Soul Leech"
	soul_leech.cost           = 1
	soul_leech.description    = "Give a friendly Demon +1 ATK and +1 ARMOR. Restore 1 HP to your hero."
	soul_leech.requires_target = true
	soul_leech.target_type    = "friendly_demon"
	soul_leech.effect_id      = "soul_leech_effect"
	_register(soul_leech)

	var dark_surge := SpellCardData.new()
	dark_surge.id          = "dark_surge"
	dark_surge.card_name   = "Dark Surge"
	dark_surge.cost        = 2
	dark_surge.description = "All your Demons gain +1 ATK until end of turn."
	dark_surge.effect_id   = "dark_surge_effect"
	_register(dark_surge)

	# --- Traps ---

	var void_snare := TrapCardData.new()
	void_snare.id          = "void_snare"
	void_snare.card_name   = "Void Snare"
	void_snare.cost        = 2
	void_snare.description = "Trap: When the enemy plays a spell, deal 3 damage to the enemy hero."
	void_snare.trigger     = Enums.TrapTrigger.ON_ENEMY_SPELL
	void_snare.effect_id   = "void_snare_effect"
	_register(void_snare)

	# --- Environments ---

	var abyss_rift := EnvironmentCardData.new()
	abyss_rift.id                  = "abyss_rift"
	abyss_rift.card_name           = "Abyss Rift"
	abyss_rift.cost                = 3
	abyss_rift.description         = "Your Demons gain +1 ATK at the start of your turn."
	abyss_rift.passive_description = "Your Demons gain +1 ATK at the start of your turn."
	abyss_rift.passive_effect_id   = "abyss_rift_passive"
	_register(abyss_rift)
