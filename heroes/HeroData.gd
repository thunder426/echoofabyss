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

## Extra pixel height added (upward) to the hero-select portrait window.
## Lets wide/landscape portraits show more of the head without cropping.
## Default 0 = base 215px window.
var select_portrait_extra_height: float = 0.0

## Path to the combat portrait shown as the player status panel background
var combat_portrait_path: String = ""

## Path to the decorative frame PNG used on the hero select card
var frame_path: String = ""

## Typed passive abilities for this hero.
## Combat code checks passives via HeroDatabase.has_passive(hero_id, passive_id).
var passives: Array[HeroPassive] = []

## Branch IDs for each talent branch belonging to this hero (e.g. ["swarm", "corruption", "void_bolt"]).
## Use TalentDatabase.get_branch(id) to get the talent nodes for each branch.
var talent_branch_ids: Array[String] = []

## Flavour quote shown on the hero select card.
var flavor: String = ""
