# Patch notes — Xn's Warlock Sim (addon)

What changed in each version, newest first. Download a version from the
[Releases page](https://github.com/XNWLK/WarlockSIMAddon/releases).

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
