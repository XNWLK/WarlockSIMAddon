# Xn's Warlock Sim

A Warlock DPS simulator **inside the game**, for World of Warcraft: Forever. It reads your character — talents, race,
demon and the spell numbers on your character sheet — plays a few hundred fights in the background and shows your DPS,
what each spell contributes and what each stat is worth to you.

> Built for the WoW: Forever beta client (interface 16001). What changed in each version:
> [changelog](CHANGELOG.md).

## One of three

| | |
|---|---|
| **Xn's Warlock Sim** (this addon) | The simulator in the game, with your own character. |
| [Xn's Forever Warlock Sim](https://xnwlk.github.io/WarlockSIM/) ([source](https://github.com/XNWLK/WarlockSIM)) | The simulator as a website: every setting, the build editor, charts, comparisons, the fight log, and how each number is calculated. |
| [Forever Warlocking](https://xnwlk.github.io/ForeverWarlocking/) ([source](https://github.com/XNWLK/ForeverWarlocking)) | A 3D practice room in the browser: you press the buttons yourself against training dummies and are measured against the simulator. |

All three use the same data and the same rules. Every fight the addon plays gives the same damage, to the last digit,
as the website's engine with the same settings. The rules themselves are described in the website's
[rule book](https://github.com/XNWLK/WarlockSIM/blob/main/MECHANICS.md).

A way to use them together: sim your character here, take the build to the website with a code to look closer, then
practise its priority list in Forever Warlocking — it reads the same build and settings codes.

## Install

1. Download `WarlockSim-x.y.z.zip` from the newest entry on the
   [Releases page](https://github.com/XNWLK/WarlockSIMAddon/releases).
2. Unzip it into `World of Warcraft\_classic_beta_\Interface\AddOns`, so that there is a folder `AddOns\WarlockSim`.
   (To update, unzip over the old folder.)
3. Restart the game and tick **Xn's Warlock Sim** in the AddOns list.
4. Type `/wsim` or click the minimap button to open the window; Escape closes it. Key bindings for opening it and for simming your\n   character are in the game's Key Bindings, under AddOns.

## What it does

| Tab | |
|---|---|
| **Character** | *Read my character* takes your talents, race, demon, sacrificed demon and your spell power, hit, crit, haste, Intellect, Spirit, Stamina, mana per 5 s and Spell Pierce from the game. *Sim!* plays the fights. The order of your spells (the priority list) is taken from the ready build closest to your talents, or from one you pick. |
| **What if** | Your character with +10 spell power, +1% hit, +1% crit, +1% haste or +20 Intellect in one click, or any change you type in (a minus for less): the change in DPS, the spells it comes from and what one point is worth. Both sides play the same fights. |
| **Builds** | *Sim builds with your gear* plays every build of the website with **your** gear numbers and puts them in order — which build is best for your gear. Your own character, with the talents you have now, is in the list in gold. |
| **Buffs** | Raid buffs, debuffs on the boss and consumables, as on the website. |
| **Fight** | Number of fights, fight length, 1–3 targets, when cooldowns are used, precast, movement, hits taken, latency, stat weights on or off, how much of each frame the sim may take, the click that sims an item and how many fights it plays, the minimap button. |
| **Codes** | Paste a settings code or a build code from the website, or make one from your character to open there. |

The result shows DPS with its margin, a bar per spell (hover for casts, crits and misses), the stat weights in spell
power, Life Taps, lowest mana and threat.

### Numbers on your character sheet

Open your character sheet: over every item you wear there is a small number, the **DPS that item is worth to you** —
your character as it is against the same character with that slot empty — and above the weapon slots the **DPS your
character sims at**. One glance shows which pieces carry you and which slot is weak.

The numbers are worked out in the background when you open the sheet, one item after the other (a few seconds each
round), and again when your items, talents or the sim's settings change. A sim you start yourself always goes first.
Green is a real contribution; grey means the item gives nothing the sim counts, or less than the run can tell apart.
"Sheet numbers" on the Character tab switches them off.

### Sim an item

**Shift + right-click an item** — in your bags, on your character sheet, at a vendor, in a loot or quest window. A small panel
opens at the mouse and plays your character as it is, and again with that one item in place of the one you wear in its
slot, and tells you the difference in DPS — for a ring or a trinket against each of the two you wear. The same fights
are played on both sides, so even small differences show. It also lists what changed ("+14 spell power, -1% hit") so
you can see what was counted.

- **An item you are wearing** is simmed against an empty slot: the panel says what the item is worth to you.
- **An item link in chat:** click it, and under the window that opens there is a **Sim this item** button.

Enchants and set bonuses are left out on both sides, and "Use:" and "Chance on hit:" effects are not simulated (the
panel names them).

The click can be changed on the Fight tab ("Sim an item with": Alt + right-click, Alt + left-click and others, or off) if
Shift + right-click is taken by another addon or gets in your way.

| Command | |
|---|---|
| `/wsim` | Opens or closes the window (`/warlocksim` works too). |
| `/wsim read` | Reads your character. |
| `/wsim minimap` | Shows or hides the minimap button. |
| `/wsim test` | Plays 14 fights and compares them with the website's engine: the maths check. |
| `/wsim dump` | Saves what the game returned when your character was read (for bug reports). |
| `/wsim stop` | Stops a running sim. |
| `/wsim blocked` | Lists actions of this addon the game blocked, if any (for bug reports). |

## Good to know

- **Not in combat.** The Forever client hides your numbers from addons while you fight, so your character can only be
  read out of combat. Sims can run at any time.
- **Kept over a reload.** The character you read last and the numbers on your character sheet are kept per character,
  over a `/reload` and the next login. Read again after you changed items or talents.
- **Your numbers are read as they are.** Raid buffs the addon recognises on you are taken off again, so that the Buffs
  tab alone decides which buffs the sim uses. Anything else that is on you while reading — a flask, food, a weapon stone
  or oil — stays inside your numbers and counts as gear. The Character tab lists what it found.
- **Level 60.** The sim plays level-60 spells against a level-63 boss. Below level 60 the DPS shown is not what you do.
- **Speed.** The game gives addons one processor core, shared with the game itself, and no background threads — an addon
  cannot use more cores. Fights are played a few milliseconds per frame. "While simming" on the Fight tab decides how
  many: "Automatic" (quick while you are out of combat, gentle while you fight), "Stay smooth", "Sim faster" or
  "Fastest". The DPS is shown as soon as it is known, the stat weights follow; and a sim asked for again with nothing
  changed is answered at once. Fewer fights are quicker and less exact (the "+-" behind the DPS says how exact).
- **On the website, not in the addon:** the build editor, charts, comparing runs, the fight timeline and log, share
  links (settings codes and build codes do work here).

## For maintainers

The addon holds a copy of the simulator's data (`WarlockSim/Data.lua`, generated) and a line-by-line port of its engine
(`Engine.lua`, `Sim.lua`). With the simulator's folder next to this one:

```
cd tools
npm install                 # once: the Lua runner the checks use
node gen-data.js            # data from the simulator -> WarlockSim/Data.lua
node gen-expected.js        # exact results for the in-game self-test -> WarlockSim/Expected.lua
node check-all.js           # every check; "full" for the long engine comparison
```

`check-engine.js` plays the same fights in both engines and compares damage, casts, crits, mana, health and threat per
spell. A changed fight rule in the simulator has to be carried into `Sim.lua` / `Engine.lua` by hand; the check fails
until it is.

## Notice

World of Warcraft and Warcraft are trademarks of Blizzard Entertainment, Inc. This is a fan project, not affiliated
with or endorsed by Blizzard. Spell names, values and icons belong to their owner.
