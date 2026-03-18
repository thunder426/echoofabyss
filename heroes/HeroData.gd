## HeroData.gd
## Static definition of a single hero.
## Registered in HeroDatabase and accessed by id.
class_name HeroData
extends Resource

## Unique identifier — used everywhere in code (GameManager.current_hero, save files, etc.)
var id: String = ""

## Display name shown in the UI
var hero_name: String = ""

## Short subtitle (e.g. "Void Caller")
var title: String = ""

## Faction name (e.g. "Abyss Order")
var faction: String = ""

## Path to the portrait image used on the hero select screen
var portrait_path: String = ""

## Path to the decorative frame PNG used on the hero select card
var frame_path: String = ""

## Typed passive abilities for this hero.
## Combat code checks passives via HeroDatabase.has_passive(hero_id, passive_id).
var passives: Array[HeroPassive] = []

## Card IDs that make up this hero's starter deck.
## GameManager._build_starter_deck() delegates here.
var starter_deck: Array[String] = []

## Branch IDs for each talent branch belonging to this hero (e.g. ["swarm", "corruption", "void_bolt"]).
## Use TalentDatabase.get_branch(id) to get the talent nodes for each branch.
var talent_branch_ids: Array[String] = []

## Card IDs that are added to the reward pool when this hero has permanently unlocked them
## (boss drops). RewardScene reads this instead of hardcoding per-hero pool names.
var hero_reward_pool: Array[String] = []

## Flavour quote shown on the hero select card.
var flavor: String = ""
