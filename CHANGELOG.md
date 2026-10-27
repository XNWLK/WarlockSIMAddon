# Changelog — Xn's Warlock Sim

What changed in each version, newest first. Download a version from the
[Releases page](https://github.com/XNWLK/WarlockSIMAddon/releases).

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
