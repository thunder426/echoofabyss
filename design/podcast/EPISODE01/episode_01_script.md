# Episode 1: Into the Abyss — Why Build a Roguelike Deckbuilder?

**Format:** Two-person conversation podcast
**Hosts:**
- **Dev** — the creator of Echo of Abyss (you)
- **Host** — a card game enthusiast who's curious about the design and dev process

**Estimated runtime:** 30–40 minutes

---

## COLD OPEN (1 min)

**Host:**
You've got a board with five slots, two resource pools fighting over an eleven-point budget, minions slamming into each other simultaneously, face-down traps, runes that chain into rituals — and you built all of this solo, in Godot, as a learning project. Today, we're going to unpack how and why. Welcome to Into the Abyss. I'm here with the creator of Echo of Abyss — welcome.

**Dev:**
Thanks for having me. Yeah, when you list it all out like that it sounds like a lot. But every piece came from one question — "what decision can I give the player right now that actually matters?"

---

## SEGMENT 1 — Origin Story: Why a Roguelike Deckbuilder? (8–10 min)

**Host:**
Let's start at the very beginning. Why a deckbuilder? Why roguelike? There are a lot of genres you could've picked.

**Dev:**
Honestly, a card game felt like the right scope. You don't need a massive open world or hundreds of animations — it's mostly UI, data, and strategy. And strategy is what I love most and what I think I'm best at designing. As for roguelike — to me that's the obvious choice for a single-player card game. There really isn't a better format. PvP is great, but you need a big enough player base from day one to make matchmaking work. With a roguelike, one person can sit down, have a complete experience, and come back for another run. It just fits.

**Host:**
So what were you playing before you started building Echo of Abyss? Were you deep into Slay the Spire? Hearthstone? Something else?

**Dev:**
I've been a card game fan for a long time. The first one I ever played was Yu-Gi-Oh — back in high school, a classmate just handed me a stack of cards and said "let's play this!" And I was hooked. There's something about building a deck, testing it, and actually winning with something you put together yourself — that's a feeling that never gets old. Collecting cards is its own addiction, that goes without saying. Later I got into Hearthstone. I was already a WoW player, so when I heard Blizzard was making a WoW-themed card game, I was all over it. Played from the earliest beta, stuck with it through every expansion for the first few years. That was a really formative experience for me as a card game player.

**Host:**
And at what point did it go from "I love these games" to "I'm going to build my own"?

**Dev:**
It actually didn't come from the games themselves — it came from AI. When all these AI tools started getting really good, I asked myself: "What's the thing I want to build most with this?" And the answer was a game. Making a card game was always a fantasy, but it was never realistic before. I'm not a full-time game developer. But AI tools changed the equation completely. Suddenly the things I couldn't do alone — I could do.

**Host:**
You chose Godot over Unity, Unreal, or even a web-based engine. Why?

**Dev:**
It's open source, which means I can actually understand what's going on under the hood. And honestly — it's also easier for AI to write Godot code without producing a ton of bugs. The codebase is cleaner, the documentation is straightforward, and AI tools seem to handle GDScript really well. That practical reason mattered more than anything.

**Host:**
And you went solo. No team, no studio. What's that actually like day-to-day?

**Dev:**
My day-to-day is basically a conversation loop with AI. I'll sit down with Claude or ChatGPT and brainstorm — we'll talk through card effects, enemy designs, what kind of talent branch would be fun, background lore for the world. Once I have a solid idea, I feed it into Claude Code and let it implement the feature. Then I spin up another AI session to review the code — make sure the architecture is clean and scalable. After that I jump over to Midjourney or ChatGPT image gen or Nana Banana to get the art done. And then — and this is the part people underestimate — I playtest. A lot. I play the game over and over, tweaking numbers, making sure nothing is brokenly strong or completely useless.

**Host:**
So if someone's listening and thinking "I want to build a card game too" — what would you tell them about the gap between the idea and the reality?

**Dev:**
I'd break it into three pieces. Art is hard physically — even with AI generating it, you're spending hours and hours prompting, iterating, rejecting, re-prompting until you get something that actually fits the mood you want. It's a grind. Game design is hard mentally — you need to understand what makes your game fun and then have the discipline to keep everything balanced. It's tempting to add cool stuff, but if you can't control the power level, the game falls apart. And coding — that part is honestly not as hard as it used to be, because AI can do a lot of the heavy lifting. But here's the catch: you still have to know what good code looks like. If you let AI write spaghetti and don't enforce clean architecture early, you'll pay for it later when every new feature takes twice as long because you're fighting your own codebase.


---

## SEGMENT 2 — The Dual-Resource System: Essence and Mana (10–12 min)

**Host:**
Alright, let's get into the design. Most deckbuilders have one resource — you spend energy or mana, you play cards. Echo of Abyss has two: Essence for minions, Mana for spells, traps, environments. And they share a combined cap of eleven. Why split it?

**Dev:**
The core idea is that your resource split *is* your strategy. Every turn you end, you pick: grow Essence or grow Mana. That's not just a number going up — it's a commitment. If you go heavy Essence, you're saying "I want a wide board, I want to overwhelm with bodies." If you lean Mana, you're saying "I want spells, traps, removal, runes." And because the cap is eleven, you can't have everything. A 7-Essence / 4-Mana player is a fundamentally different deck than a 4/7 player, even if they started with the same cards.

**Host:**
Eleven is a specific number. How did you land on that?

**Dev:**
It comes from the math. You start with 1 Essence and 1 Mana, and I'm designing minions that go all the way up to 10 Essence. So the ceiling on Essence is 10, you always need at least 1 Mana — that's 11. But the real reason for the cap isn't the number itself, it's the constraint. Without a cap, the choice to grow Essence or Mana stops mattering at some point — you'd just max both and never think about it again. The cap forces you to commit. Every point you put into one pool is a point you'll never have in the other.

**Host:**
So the player makes this choice every single turn — Essence or Mana. Does that ever feel repetitive, or is there genuine tension each time?

**Dev:**
That's where the "or" does the heavy lifting. Early game, turns one through three, it feels obvious — you need a bit of both. But by turn five or six, you're making real trade-offs. Do I go to 6 Essence so I can drop my Void Devourer next turn? Or do I push to 4 Mana so I can play Void Execution to clear their biggest threat right now? The cards in your hand create the pressure. The resource choice is how you respond to it.

**Host:**
And then there are the conversion spells — Energy Conversion and Flux Siphon. Zero cost, convert up to three of one resource into the other. That feels like a safety valve.

**Dev:**
Exactly. They exist so you don't get completely locked out. Say you went 7 Essence / 4 Mana, but this turn you drew two great spells and no minions. Without conversion, those spells are dead cards. With Flux Siphon, you can trade some of that Essence you weren't going to use anyway. It's not free — you're giving up the option to play a minion — but it means your resource split is a lean, not a wall.

**Host:**
Some minions cost both — like Runic Void Imp at 2 Essence plus 1 Mana. What's the design intent behind dual-cost cards?

**Dev:**
Dual-cost cards are the bridge between the two pools. They're deliberately stronger for their total cost, but they tax both resources, so you need a balanced economy to use them. It rewards players who don't go all-in on one side. It also creates these moments where you're doing mental math — "I have 5 Essence and 3 Mana, can I play the dual-cost minion AND still have Mana for a trap?" That's the kind of puzzle I want every turn to feel like.

**Host:**
How does the AI handle resource growth? Does the enemy make the same Essence-or-Mana choice?

**Dev:**
Every enemy AI has its own profile, and each profile handles resource growth differently based on what kind of deck it's running. A spell-heavy enemy like the Abyss Cultists will prioritize Mana growth after the early game. An aggro swarm deck like the Feral Imps will pump Essence almost every turn. But it's not just a fixed curve — the AI also looks at what's in its hand. If it's holding a critical spell and it's one Mana short of casting it, it'll grow Mana next turn even if it's normally an Essence-focused deck. So the AI is making the same meaningful choice the player is.

**Host:**
Has the dual-resource system ever created a problem you didn't expect?

**Dev:**
Balancing it was way harder than I expected. Early on I actually had the player starting with 1 Essence and 0 Mana. Sounds reasonable, right? Minions first, spells later. But it created this horrible problem where even a 1-Mana spell was incredibly expensive, because to cast it you had to skip an Essence growth on one of your first turns. That's a huge sacrifice in the early game when you desperately need board presence. The entire Mana cost model had to be rethought. Every spell that felt fair at "1 Mana" was actually costing you a turn of Essence development to unlock. Spell-focused strategies became nearly unplayable — you'd fall behind on board and just get overwhelmed before your spells came online. So I switched to starting at 1 and 1, and suddenly everything clicked. Both pools are live from turn one, both sides of your deck are accessible, and the interesting choices start immediately instead of five turns in. It was a small change on paper but it completely reshaped how the game feels.

---

## SEGMENT 3 — The Board Matters: Why Positional Combat? (10–12 min)

**Host:**
Here's something that jumped out to me — Echo of Abyss has a board. Five slots per side. Minions sit in positions, they attack simultaneously, there's adjacency that matters. A lot of roguelike deckbuilders don't have a board at all. Slay the Spire is pure hand-play. Why did you add this layer?

**Dev:**
Because I wanted the game to feel like a war, not a math problem. In Slay the Spire — which I love — your turn is: calculate optimal card order, play cards, end turn. It's brilliant but it's essentially solitaire. I wanted two armies clashing. I wanted you to look at the board and think "if I put my Guard here, it protects my Void Spawner, but it also means their Frenzied Imp can't reach my hero." The board makes positioning a decision, not just card order.

**Host:**
Five slots — not three, not seven. What does five give you?

**Dev:**
Five is the sweet spot where the board feels full but not overwhelming. Three slots and the board fills too fast — you run out of room and the game becomes "who can play one big thing." Seven slots and it takes too long to fill, the early game drags, and there's too much to track. Five means by mid-game you're usually managing three or four minions and making real choices about what goes where and what gets sacrificed.

**Host:**
Speaking of sacrifice — Void Devourer eats adjacent friendly minions for stats. That's an adjacency mechanic. How central is positioning?

**Dev:**
It's one of the places where the board really earns its existence. Void Devourer costs 6 Essence, comes in as a 2/6 with Guard — decent but not amazing. But if you set up two small minions next to the slot where you'll play it, suddenly it's an 8/12 Guard. That requires planning. You had to leave those slots free, you had to have cheap minions in the right positions. It turns a single card play into a three-turn setup.

**Host:**
Let's talk about simultaneous combat. When minions attack, both sides deal damage at the same time. That's different from Hearthstone where the attacker chooses and the defender just takes it.

**Dev:**
Right. Simultaneous combat means trading matters. If your 3-attack minion fights their 3-attack minion, both die. In Hearthstone, your attacker might survive with 1 HP because you chose the fight. Here, you have to think about whether you can afford the trade. It also makes Guard way more interesting — a Guard minion isn't just a wall, it's a thing that's going to fight back and take damage every time it blocks. You have to decide: is it worth sending my minion into their Guard and losing it, or do I use a spell to remove the Guard first?

**Host:**
Guard forces enemies to attack it. With five slots and potentially multiple Guard minions — does that create a "turtle" problem where neither side can break through?

**Dev:**
Not really, for a couple reasons. First, there aren't that many Guard cards in the game — it's a powerful keyword, so I've been deliberate about not handing it out freely. Second, even when Guard is on the board, you have options. You can trade into it and break through. You can use removal spells to take it out. Or you can just bypass the board entirely with direct damage spells to the face — Void Bolt, Void Execution, those don't care about Guard at all. Guard creates a speed bump, not a brick wall.

**Host:**
The board also means you have minion states — Exhausted, Swift, Normal. A minion can't attack the turn it's summoned unless it has Swift, and even Swift minions can only hit other minions, not the hero. Why that restriction?

**Dev:**
It's about tempo and counterplay. If every minion could attack the hero immediately, the game would be a race to dump stats on the board. The summoning sickness — coming in Exhausted — gives your opponent one turn to respond. Swift is the compromise: you can affect the board immediately, trade into a threat, but you can't go face. It means aggressive decks still have to fight for the board before they can push damage.

**Host:**
And then there's the whole trap and rune layer sitting on top of the board — face-down traps that trigger reactively, face-up runes with persistent auras. How does that interact with the board state?

**Dev:**
That's where the game gets its depth. The board isn't just minions — it's the visible information. You can see my minions, I can see yours. But my traps are hidden. So when you're deciding whether to attack my 100/300 minion with your 400/200, you have to ask: is there a Hidden Ambush that's going to deal 4 damage to my attacker? You don't know. And runes change the math for everything — a Dominion Rune means every Demon on my side has +1 attack. That's not on the card, it's on the board state. You have to read the whole board, not just individual cards.

**Host:**
It sounds like the board turns every turn into a mini-puzzle with incomplete information. Was there a moment during development where the board "clicked" and you knew it was the right call?

**Dev:**
Yeah, actually. I was playtesting, and I had this perfect setup going — Abyssal Summoning Circle on the field, a Blood Rune and Dominion Rune powering my board, demons getting buffed, the ritual was about to fire. I was one turn from closing out the game. And then the enemy AI played Cyclone — destroyed my environment. Just like that, my whole ritual chain was gone. The summoning circle, the synergy I'd been building for four turns — wiped. And in that moment I wasn't even mad, I was excited. Because I realized the game had just done something I didn't script. The AI made a correct strategic decision that completely changed the outcome, using a card that interacts with a system I designed separately. The board, the runes, the environments, the removal — they all talked to each other in a way that created a real "oh no" moment. That's when I knew the board was earning its complexity.

**Host:**
Last question on the board — with all this complexity, how do you keep it readable? Five minions per side, buffs, debuffs, traps, runes, two resource bars, a hand of up to ten cards — that's a lot of visual information.

**Dev:**
The rule I follow is: minimal but necessary. On the board itself, each minion shows ATK, HP, and its current status — that's it. Everything else — buffs, debuffs, keywords, full card text — lives in a hover preview. You can get the detail when you want it, but it's not cluttering the board when you're just trying to read the battlefield. For runes specifically, I made a deliberate choice to drop the card art entirely and use pure symbols instead. The most important thing with a rune is that you recognize what it is at a glance — you need to know "that's a Dominion Rune, every demon has +1 ATK" without reading text. Clean symbols do that better than a small painting. It actually turned out to look pretty good. At least I think so.

---

## WRAP-UP (2–3 min)

**Host:**
Alright, let's bring it together. You started with "I want to make a card game," you split resources into two pools to make every turn a strategic commitment, and you added a board to make combat feel like a war instead of solitaire. If you had to describe Echo of Abyss in one sentence to someone who's never seen it — what is it?

**Dev:**
Echo of Abyss is a tactical roguelike deckbuilder where two armies fight across a board, powered by two competing resources — built by AI, directed by a lifelong card game player who finally got to make the game he always wanted.

**Host:**
And what's next? What are you working on right now?

**Dev:**
Right now I'm finishing up enemy design for Act 4 — that's the final stretch of the run. After that, I'm designing a second Abyss Order hero and a neutral hero to give players more starting options. And then I'm building out the next chapter of enemy encounters — thinking desert ancient tomb themed. New faction, new mechanics, new AI profiles. There's a lot on the roadmap.

**Host:**
Thanks for walking us through this. For anyone who wants to follow the development — where can they find you?

**Dev:**
You can find me on X — @Thunder_Eternal. That's where I post updates, screenshots, and the occasional design rant. Come say hi.

**Host:**
That's episode one. Next time, we'll dig into the enemy AI — how do you make five different enemy clans feel like they have personalities? Until then — thanks for listening.

---

## PRODUCTION NOTES

**Tone:** Conversational, not scripted-sounding. All lines are fully written but should be delivered naturally — paraphrase rather than read word-for-word. The script is a guide, not a teleprompter.

**Recording tips:**
- Read through the full script once before recording so the flow feels natural
- It's okay to go off-script when a thought leads somewhere interesting — the Host questions will pull you back on track
- The best moments will come from reacting naturally, not reciting perfectly
- Keep answers under 2 minutes each; if you're going long, the Host's next question is your exit ramp

**Possible cuts if running long:**
- Trim the conversion spell discussion in Segment 2
- Condense the Guard/turtle discussion in Segment 3
- The cold open can be shortened to just the Host introduction
