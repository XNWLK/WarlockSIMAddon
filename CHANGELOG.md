# Changelog — Xn's Warlock Sim

What changed in each version, newest first. Download a version from the
[Releases page](https://github.com/XNWLK/WarlockSIMAddon/releases).

## v0.14.1

- Item sims: an "Equip: Improves your chance to get a critical strike by 1%." line (no "with spells", e.g. Emberfury
  Talisman) was counted but also listed as "Not counted". Crit that names no type counts for spells and attacks, so it
  is now read as spell crit and no longer listed; the same for "Improves your chance to hit by X%.". Crit or hit that
  names attacks only still does nothing for your spells.

## v0.14.0

- Wrack follows the Warlock SIM's new model: while you channel Wrack, Corruption, Bane of Agony and Siphon Life keep
  their normal ticks and get one extra tick at every half-way point between two of them that falls inside the channel.
  Bane of Agony's extra ticks grow with the time since it was cast, like its normal ones. Stopping Wrack changes
  nothing else, and a DoT that runs out leaves no smaller last tick. A half-way point gives its extra tick once, even
  when Wrack is cast again at that moment.
- Wrack cast while Wrack is channelling replaces it, like recasting any drain: the new Wrack runs its own 6 ticks and
  the ticks the old one had left are lost (before, they were added to the new one). If the new Wrack is resisted, the
  old one is lost too. The DoTs' extra ticks go on across the recast. The built-in builds never do this.

## v0.13.5

- Simming an item now ignores the enchant on the item you would take off: both sides (as you are, and with the new
  item) are simmed without it, so the two items are compared as they are. The result says which enchant was ignored,
  e.g. "Enchant ignored: Revelation on Witchblade". An enchant text the addon cannot read is named and still counted.

## v0.13.4

- The What if tab has two more boxes: **Shadow power** and **Fire power** (spell damage for that school only, like
  "Increases damage done by Shadow spells" on gear).

## v0.13.3

- From the official notes of Forever's patch of 2026-11-10:
  - Wrack deals 60 + 20% of your spell power per tick (was 60.2).
  - Bane of Havoc now takes a global cooldown. With 2 or more targets it is cast at the pull, and your first spell
    comes one global cooldown later. Incinerate builds lose about 1% against 2 or 3 targets; one target is unchanged.
- Amplify Curse stays up when its Bane of Agony misses: the next Bane of Agony still gets the bonus.
- Wrack DS casts Corruption before Bane of Agony, and uses a Nightfall proc only once it has 8 seconds or less left,
  so it does not cut a Wrack short at once. About +0.5%.

## v0.13.2

- New talents in the two Demo builds, as on the website (both still 2/31/18):
  - **Fire Demo:** Demonic Embrace 4, Demonic Energies 1, Demonic Brand 2.
  - **Shadow Demo:** Demonic Embrace 3, Demonic Energies 1, Demonic Brand 3.
- DPS barely moves: Fire Demo changes by less than 0.1% depending on race, and Shadow Demo is the same except a hair
  more for Undead.

## v0.13.1

- Shadow Demo and Fire Demo take 2 points of Demonic Embrace (+6% Stamina) instead of Master Summoner, as on the
  website. Still 2/31/18. Only Undead see a difference (Touch of the Grave grows with your health): about +0.07%.

## v0.13.0

- Forever's Wrack patch of 2026-11-10:
  - While you channel Wrack, your Corruption, Bane of Agony and Siphon Life tick twice as often. They last just as
    long. Bane of Doom and Immolate are not affected. A DoT that ends between two ticks deals the part of a tick it
    has built up.
  - Wrack deals 70% of its old damage, and its old +10% to your DoTs is gone.
  - Wrack cast again while it still channels does not cut it short: the new Wrack keeps the ticks the old one had left.
  - Soul Siphon counts only Corruption, Bane of Agony and Siphon Life (no longer Bane of Doom or Curse of the
    Elements).
- Wrack DS keeps Bane of Agony and Siphon Life up again (it used Bane of Doom and no Siphon Life before).
- Near the end of a fight, "is this DoT still worth casting" counts the faster ticks when Wrack is the filler (also
  on the helper bar).
- Same rules as the website's version of 2026-11-10.

## v0.12.1

- Three ready builds have new names, as on the website: **Shadow Demo** (was Demo Pact Shadow Bolt Succubus), **Fire
  Demo** (was Demo Pact Fire Imp) and **Incinerate Pandemic** (was Destro Incinerate Succubus). Their talents and
  priority lists are the same.

## v0.12.0

- New ready builds: **Wrack DS** (35/11/5, the Imp sacrificed, no demon out, Spellstone) replaces Wrack Succubus, and
  **Incinerate DS** (7/11/33, the Succubus sacrificed, no demon out, Firestone) is new. SM Ruin is gone. The five ready
  builds are Demo Pact Succubus SB, Demo Pact Fire, Incinerate Succubus, Incinerate DS and Wrack DS.
- Wrack DS only Life Taps right after a full Wrack (6 seconds after you last spent mana).
- Forever's patch of 2026-11-03: Wrack hits about twice as hard, Improved Drains no longer raises Wrack, Shadow and
  Flame gives 4-20% (was 2-10%), and Salvation is gone (no longer on the Buffs tab or read from your buffs).
- Build codes can use the new conditions of the website's priority editor (0.11.1 and 0.12.0): "needs a recast",
  "still pays off", "you know a spell", points in a talent, "a demon is out", "Keep Curse of the Elements up", mana
  needed for the rest of the fight, free mana ready, the shortest DoT time left, the time since you last spent mana, a
  spell's cast time and the execute % as numbers, and the full checks of Death Coil at the end, Searing Pain before Soul
  Fire and Life Tap for the pet. Conditions compare exactly, as the built-in priority actions do.
- If "Play it like" was set to a build that is gone, the closest ready build is used.
- Same rules as the website's version of 2026-11-04.

## v0.11.1

- Build codes from the website can now use the new conditions of its priority editor: "needs a recast", "still pays
  off", "you know a spell", points in a talent, "a demon is out", "Keep Curse of the Elements up", mana needed for the
  rest of the fight, free mana ready, the shortest DoT time left, a spell's cast time and the execute % as numbers, and
  the full checks of Death Coil at the end, Searing Pain before Soul Fire and Life Tap for the pet.
- Conditions compare exactly, as the built-in priority actions do; the mana % condition uses the same sum as Life Tap.
- The ready builds and their results are unchanged. Same rules as the website's version of 2026-11-01.

## v0.11.0

- New: the helper, off by default ("Helper" on the Character tab, or `/wsim helper`). On a raid boss a small bar shows
  the spell the sim would cast next with your character, the two after it, and cooldowns or a mana potion to use with
  it. The sim's own priority list decides, for the ready build your talents fit ("Play it like" on the Character tab).
- The bar also shows how many seconds the boss has left, worked out from how fast its health went down in the last 20
  seconds. The priority list plays with that time: DoTs that would not pay off any more are left out, Death Coil comes
  at the very end, Life Tap goes by the time left, and the execute phase starts at the boss's real health.
- Only on raid bosses: a boss encounter in a raid, or a boss you target (world bosses). Not in 5-player dungeons.
- It reads the boss's health, your mana, your buffs (Shadow Trance) and the boss's debuffs (your DoTs, Improved Shadow
  Bolt, Curse of the Elements) from the game. Should the game ever hide one of them from addons, the helper follows your
  own casts instead; without the boss's health the time shown is the fight length of the Fight tab, in grey.
- `/wsim helper move` lets you drag the bar where you want it. The key that casts a spell on your action bars is shown
  on its icon.
- The Character tab's "Sim!" button is narrower to make room for the box.

## v0.10.0

- Trinkets work in the fight: if you wear one whose effect the sim knows, it is used during the fight. 19 trinkets are
  known, among them Talisman of Ephemeral Power, Zandalarian Hero Charm, Talisman of Ascendance, Eye of Moam, The Black
  Book, Hazza'rah's Charm of Destruction, Shard of the Fallen Star, Warmth of Forgiveness and Darkmoon Card: Blue
  Dragon. "Trinkets" on the Fight tab sets when they are used: with your other cooldowns (the default), whenever ready,
  in the execute phase, or never. A mana trinket is used when its mana is missing.
- The enchant on your main hand counts too, if it does more than give stats: Revelation, Grand Sorcerer, Grand Arcanist
  and Insight. How often Revelation triggers is not known; the sim uses a guess.
- The Character tab names the trinkets and the enchant whose effects count. Item sims and the numbers on the
  character sheet count them as well: a trinket you wear is worth its use effect.
- Every ready build now uses "Life Tap by need": Life Tap only when the mana you have will not last the rest of the
  fight, and not while free mana (Innervate, Mana Tide, a potion, a rune or a mana trinket) is ready. With plenty of
  mana it taps less; with default settings the results stay the same.
- Wrack Succubus only channels Wrack while Corruption, Bane of Agony and Siphon Life all have at least 4 seconds left,
  and casts Shadow Bolt in between.
- Fixed: in item sims, a "Use:" or "Chance on hit:" line could be read as a stat the item always gives (Talisman of
  Ephemeral Power came out as +175 spell power all the time).
- "Destro Incinerate Imp" is gone (Destro Incinerate Succubus does better). Five ready builds remain.
- New on the Buffs tab: Dark Inspiration, +15% Spirit from a Shadow Priest in your party.
- Build codes from the website with conditions on built-in actions work in the addon, and settings codes keep the
  website's cheat mode (spells that always hit or always crit).
- Also in this version (0.9.9 had no release of its own): Troll Berserking lasts 15 seconds (was 10).
- After updating, your character is read again once and the numbers on the character sheet are worked out again.

## v0.9.9

- Follows the Forever patch notes: Troll Berserking lasts 15 seconds (was 10). Its 10% haste and 3 minute cooldown are
  unchanged.
- After updating, your character is read again once and the numbers on the character sheet are worked out again.

## v0.9.8

- Follows more Forever patch notes:
  - Orc: Blood Fury has a 2 minute cooldown again (was 3 minutes).
  - Undead: Touch of the Grave can happen again 15 seconds after it did (was 25 seconds).
- After updating, your character is read again once and the numbers on the character sheet are worked out again.

## v0.9.7

- A fight lasts 3 minutes by default again (it was 2 minutes), as on the website: fights in Forever are expected to be
  longer. Results come out about 1 to 2% lower. If your fight length was still 2 minutes it is moved to 3 once; a length
  you set after this update stays.
- After updating, your character is read again once and the numbers on the character sheet are worked out again.

## v0.9.6

- Follows the Forever patch notes of 2026-10-26:
  - Human: Ruthless gives +1% crit (was 2%); The Human Spirit gives +10% Spirit (was 5%).
  - Orc: Savage is gone, and Command is back: your demon deals 5% more damage (its spells, its melee and the Demonic
    Brand bonus).
- After updating, your character is read again once and the numbers on the character sheet are worked out again.

## v0.9.5

- The ready build "Aff Pact Shadow Bolt Succubus" is gone: it gave nothing that "Demo Pact Shadow Bolt Succubus" does
  not. Six ready builds remain.
- "SM Ruin (classic)" is now called "SM Ruin".
- After updating, your character is read again once and the numbers on the character sheet are worked out again.

## v0.9.4

- Your demon's melee now gets 8/17 of your spell hit, all of it counting: 17% spell hit gives 8% melee hit, and then the
  Succubus never misses (she can still be dodged). Below that she misses a little more than before. Its spells still hit
  as often as yours. Imp builds do not change.
- New on the Buffs tab: the Atiesh auras of a Warlock, a Mage or a Druid in your party, and Blood Pact from another
  Warlock's Imp.
- Innervate and Power Infusion have a "how many" box for when several Druids or Priests give you theirs. The next one
  comes when the last one is over.
- Build codes from the website that use your own rules, groups and variables in the priority list now work in the addon.
- After updating, your character is read again once and the numbers on the character sheet are worked out again.

## v0.9.3

- Gear codes tell the website more about each item: its item level, the level needed to wear it, its icon, its item set
  and its stats exactly as the game gives them. That way the website's gear builder can learn items it does not know yet.
- Spell Penetration and Spell Pierce are two stats now, as on the website. Spell Penetration lowers the boss's resistance
  down to 0, Spell Pierce can take it below 0. Which one an item has goes by its own words: a line that says "Spell
  Piercing" is Spell Pierce, one that says "Spell Penetration" is Spell Penetration. Item sims count both.
- Enchants on your necklace, belt and off-hand item are in the gear code too (Forever has them).
- Spell Penetration on the items you wear now counts when your character is read. The character sheet has no number
  for it, so the addon adds it up from your items and enchants.
- New on the Codes tab: "Bags too". With it ticked, "My gear as a code" also lists the items in your bags that you can
  wear.
- After updating, your character is read again once and the numbers on the character sheet are worked out again.

## v0.9.2

- Amplify Curse now makes your whole next Bane of Agony 50% stronger, its spell power part included. Before, it only
  raised the spell's base damage.
- After updating, your character is read again once and the numbers on the character sheet are worked out again.

## v0.9.1

- Your demon's melee now crits with your spell crit, and only with that (the same as its spells). Before, it had a
  crit of its own plus a melee crit from your Agility.
- Agility no longer does anything, so it is gone: Grace of Air Totem and Scroll of Agility IV are no longer on the Buffs
  tab, and Agility on items and enchants is not counted (an Agility enchant is no longer called unreadable). Old settings
  codes with them load without a notice.
- After updating, your character is read again once and the numbers on the character sheet are worked out again.
- The addon now names its CurseForge page as its website, for addon managers.

## v0.9.0

- Follows the Forever patch of 2026-10-16:
  - Shadow Mastery gives 2/4/6/8/10% Shadow damage.
  - Malediction is gone. Grim Reach takes its place in the tree (range only, no damage). A character or build code that
    still has Malediction points gets them as Grim Reach, up to 2.
  - Human Ruthless: +2% crit with any weapon (no sword needed any more). Orc Savage: +1% crit. Both also count for your
    Succubus' melee.
  - Blood Fury: 3 minute cooldown.
  - Eureka! (Gnome): an 8 second buff. A damaging spell that finishes while it is up deals 10% more and costs 10% less;
    channelled spells only on the ticks that come while it lasts. Damage over time spells get nothing.
  - Touch of the Grave (Undead): 30% chance, then 25 seconds before it can happen again. It deals 5% of your maximum
    health and nothing raises that any more.
  - Windfury Totem and Flametongue Totem are gone from the Buffs tab (they only help players now, not your demon), and
    so is Tranquil Air Totem. Blessing of Salvation is now Salvation (same -30% threat).
  - Ready builds, searched again under the new rules: Aff Pact Shadow Bolt Succubus is now 8/31/12, Destro Incinerate
    Succubus 14/4/33, SM Ruin (classic) 30/0/21 and Wrack Succubus 33/0/18.
- Old settings codes with the removed totems load without a notice.
- After updating, your character is read again once and the numbers on the character sheet are worked out again.

## v0.8.0

- Gear codes: "My gear as a code" on the Codes tab turns everything you wear into a code for the website's gear
  builder: each item with its name and stats, and your enchants. Paste it there to look at your own gear on the website.
  An enchant whose text the addon cannot read is counted as 0 and named.
- Fixed: a Human Warlock's sword was never recognised, so Sword Specialization was left out when your character was read
  and in item sims.

## v0.7.0

- Sims stop as soon as the result is exact enough ("Stop early" on the Fight tab, on by default). The number of fights
  set is then the most that are played. Comparisons gain the most, because both sides play the same fights: What if,
  item sims, stat weights and the numbers on the character sheet often finish after a few dozen fights.
- Opening the window reads your character (out of combat), so "Read my character" is rarely needed.
- Below level 60 the addon says more clearly that its DPS is a level 60 number: on the Character tab, under a result,
  in the item panel and on the character sheet.

## v0.6.4

- If the game ever blocks an action of this addon, it is noted with the action and the time, and said once in chat.
  `/wsim blocked` lists them (and `/wsim dump` saves them for a bug report). The addon only listens; it changes nothing.

## v0.6.3

- Closing the window with Escape no longer brings up the message "WarlockSim has been blocked from an action only
  available to the Blizzard UI".

## v0.6.2

- Escape really closes the window now (the way 0.6.1 used did not work in the game).

## v0.6.1

- Escape closes the window.

## v0.6.0

- Minimap button: click opens or closes the window, right-click sims your character, drag moves it around the minimap.
  "Minimap button" on the Fight tab (or `/wsim minimap`) hides it.
- Key bindings: "Open or close the window" and "Sim my character", in the game's Key Bindings under AddOns.
- Your character and the numbers on your character sheet are kept over a `/reload` and a new login. The sheet numbers
  are only worked out again when your items, talents or settings changed.
- New tab "What if": your character with +10 spell power, +1% hit, +1% crit, +1% haste or +20 Intellect in one click,
  or any change you type in (a minus for less). It shows the change in DPS, the spells it comes from and what one point
  is worth. Both sides play the same fights.
- The number of fights of an item sim (and of the sheet numbers) can be set on the Fight tab ("Item sims").

## v0.5.1

- The total DPS on the character sheet now sits right above the weapon slots.
- Sim! answers sooner: the DPS and the spell bars are shown as soon as the first run is done, the stat weights follow.
  The list of builds also grows build by build.
- A sim asked for again with nothing changed is answered at once.
- New speed "Automatic", now the default: the sim takes more of each frame while you are out of combat and stays gentle
  while you fight. (Fight tab, "While simming".)
- The fight engine does the same work with half the function calls of the first version. The results are unchanged.
- The tip at the bottom of the window no longer gets cut off.

## v0.5.0

- Numbers on your character sheet: over every item you wear, the DPS that item is worth to you (your character as it is
  against the same character with that slot empty), and the DPS your character sims at. They are worked out in the
  background when you open the sheet and again when your items, talents or the sim's settings change. "Sheet numbers" on
  the Character tab switches them off.

## v0.4.1

- Item sims are on Shift + right-click by default. Alt + right-click and other clicks can be chosen on the Fight tab
  ("Sim an item with").

## v0.4.0

- The click for item sims can be chosen, or switched off, on the Fight tab. A tip line at the bottom of the window says
  which click it is.
- "Sim builds with your gear" (was "Rank the builds"): reads your character again, then plays every build of the sim
  with your gear numbers. Your own character's row is gold.
- Tabs are now Character, Builds, Buffs, Fight, Codes.
- Faster fight engine, and a third speed, "Fastest".

## v0.3.0

- Click an item in your bags, on your character sheet, at a vendor or in a loot window with the item-sim click: a small
  panel opens at the mouse and sims it against what you wear in that slot.
- An item you are wearing is simmed against an empty slot: what it is worth to you.

## v0.2.0

- "Sim this item" under the window of a clicked item link: your character as it is against your character with that one
  item changed, for rings and trinkets against both you wear. Shows what was counted ("+14 spell power, -1% hit").

## v0.1.1

- The addon is called Xn's Warlock Sim.

## v0.1.0

- First version: reads your character (talents, race, demon, sheet numbers), sims it and shows DPS, damage per spell and
  stat weights; ranks the sim's builds with your numbers; fight, buff and consumable settings; reads and writes the
  website's settings codes and build codes. `/wsim` opens the window.
