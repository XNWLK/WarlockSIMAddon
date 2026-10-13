# Warlock Sim (addon)

A Warlock DPS simulator **inside the game**, for World of Warcraft: Forever. It reads your character — talents, race,
demon and the spell numbers on your character sheet — plays a few hundred fights in the background and shows your DPS,
what each spell contributes and what each stat is worth to you.

It is the in-game companion of [Xn's Forever Warlock Sim](https://xnwlk.github.io/WarlockSIM/)
([source](https://github.com/XNWLK/WarlockSIM)) and uses the same data and the same rules: every fight the addon plays
gives the same damage, to the last digit, as the website's engine with the same settings. How the rules work is
described in the website's [rule book](https://github.com/XNWLK/WarlockSIM/blob/main/MECHANICS.md).

> First version. Built for the WoW: Forever beta client (interface 16001).

## Install

Copy the `WarlockSim` folder into `World of Warcraft\_classic_beta_\Interface\AddOns`, restart the game and tick
**Warlock Sim** in the AddOns list. Type `/wsim` to open the window.

## What it does

| Tab | |
|---|---|
| **Character** | *Read my character* takes your talents, race, demon, sacrificed demon and your spell power, hit, crit, haste, Intellect, Spirit, Stamina, mana per 5 s and Spell Pierce from the game. *Sim!* plays the fights. The order of your spells (the priority list) is taken from the ready build closest to your talents, or from one you pick. |
| **Builds** | Plays every ready build of the website with **your** numbers and ranks them — which build is best for your gear. |
| **Fight** | Number of fights, fight length, 1–3 targets, when cooldowns are used, precast, movement, hits taken, latency, stat weights on or off. |
| **Buffs** | Raid buffs, debuffs on the boss and consumables, as on the website. |
| **Codes** | Paste a settings code or a build code from the website, or make one from your character to open on the website (for its charts, comparisons and "show the maths"). |

The result shows DPS with its margin, a bar per spell (hover for casts, crits and misses), the stat weights in spell
power, Life Taps, lowest mana and threat.

Commands: `/wsim` (window) · `/wsim read` · `/wsim test` (plays 14 fights and compares them with the website's engine)
· `/wsim dump` (saves what the game returned, for bug reports) · `/wsim stop`.

## Good to know

- **Not in combat.** The Forever client hides your numbers from addons while you fight, so your character can only be
  read out of combat. Sims can run at any time.
- **Your numbers are read as they are.** Raid buffs the addon recognises on you are taken off again, so that the Buffs
  tab alone decides which buffs the sim uses. Anything else that is on you while reading — a flask, food, a weapon stone
  or oil — stays inside your numbers and counts as gear. The Character tab lists what it found.
- **Level 60.** The sim plays level-60 spells against a level-63 boss. Below level 60 the DPS shown is not what you do.
- **Speed.** The game gives addons one processor core and no background threads. Fights are played a few milliseconds
  per frame so the game stays smooth; a sim of 300 fights takes a while, a ranking of all builds several times as long.
  Fewer fights are quicker and less exact (the "+-" behind the DPS says how exact).
- **Not in the addon** (use the website): the build editor, charts, comparing runs, the fight timeline and log, share
  links (settings codes and build codes work).

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
