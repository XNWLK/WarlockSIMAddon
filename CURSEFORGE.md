# CurseForge texts for Xn's Warlock Sim

Paste each part into its own field on CurseForge. The description is Markdown (pick "Markdown" as the editor type).

## Summary (the short line under the name)

A Warlock DPS simulator inside the game: sims your own character, ranks builds, and tells you what every item is worth.

## Description

# Xn's Warlock Sim

**A Warlock DPS simulator inside the game, for World of Warcraft: Forever.**

It reads your character (talents, race, demon and the spell numbers on your character sheet), plays a few hundred fights against a raid boss and tells you your DPS, what each spell contributes and what each stat is worth to you. No copying numbers into a website, no guessing: open the window, press **Sim!**

---

## What it does

**Sim your own character**
*Read my character* takes your talents, race, demon, a sacrificed demon and your spell power, hit, crit, haste, Intellect, Spirit, Stamina, mana per 5 and Spell Pierce straight from the game. The result shows your DPS with its margin, a bar per spell (hover for casts, crits and misses), Life Taps, lowest mana and threat.

**Stat weights**
How much one point of hit, crit, haste, Intellect and the rest is worth to *you*, in spell power. Know which stats to look for on your next item.

**What is this item worth?**
**Shift + right-click any item** in your bags, at a vendor, in a loot or quest window, or a linked item in chat. A small panel sims your character as it is and again with that one item in place of the one you wear, and tells you the difference in DPS. Both sides play the same fights, so even small upgrades show. Rings and trinkets are compared against each of the two you wear. The click can be changed if another addon already uses it.

**Numbers on your character sheet**
Open your character sheet: every item you wear shows the DPS it is worth to you, and above your weapons is the DPS your whole character sims at. One glance shows which pieces carry you and which slot is weak. It is worked out quietly in the background and updates when your gear, talents or settings change.

**Which build is best for your gear?**
*Sim builds with your gear* plays every ready-made build with **your** numbers and puts them in order. Your current talents are in the list too, in gold, so you can see how you stack up.

**Buffs, consumables and the fight**
Raid buffs, debuffs on the boss and consumables. Fight length, number of fights, 1 to 3 targets, cooldown timing, precast, movement, hits taken and latency.

**Website codes in and out**
Paste a settings or build code from [Xn's Forever Warlock Sim](https://xnwlk.github.io/WarlockSIM/) website, or make one from your character to look closer there.

---

## Exact, not a guess

The addon carries the same data and the same fight rules as the [Xn's Forever Warlock Sim](https://xnwlk.github.io/WarlockSIM/) website. Every fight gives the same damage, to the last digit, as the website's engine with the same settings. Type `/wsim test` to check it yourself on your own client.

## Smooth while it works

Fights are played a few milliseconds per frame, so the game keeps running while it sims: quick when you are out of combat, gentle while you fight. Your DPS shows as soon as it is known and the stat weights follow. Ask for the same sim again with nothing changed and the answer is instant.

---

## Commands

| Command | |
|---|---|
| `/wsim` | Open or close the window |
| `/wsim read` | Read your character |
| `/wsim test` | Check the maths against the website's engine |
| `/wsim stop` | Stop a running sim |
| `/wsim dump` | Save what the game returned, for bug reports |

## Good to know

- **Read out of combat.** The Forever client hides your stats from addons during combat, so your character is read out of combat. Sims themselves run any time.
- **Buffs are kept apart.** Raid buffs it recognises on you are taken off again, so the Buffs tab alone decides which buffs the sim uses. A flask, food or weapon oil that is on you counts as gear.
- **Level 60.** The sim plays level 60 spells against a level 63 boss. Below level 60 the DPS shown is not what you do yet.
- **Enchants and set bonuses** are not counted in the item sim, and "Use:" and "Chance on hit:" effects are not simulated (the panel says so).

---

## One of three

| | |
|---|---|
| **Xn's Warlock Sim** (this addon) | The simulator in the game, with your own character. |
| [Xn's Forever Warlock Sim](https://xnwlk.github.io/WarlockSIM/) | The simulator as a website: the build editor, charts, comparisons, the fight log, and how every number is calculated. |
| [Forever Warlocking](https://xnwlk.github.io/ForeverWarlocking/) | A 3D practice room in your browser: press the buttons yourself against training dummies and be measured against the simulator. |

Sim your character here, take the build to the website with a code to look closer, then practise its spell order in Forever Warlocking.

**Source, patch notes and bug reports:** [github.com/XNWLK/WarlockSIMAddon](https://github.com/XNWLK/WarlockSIMAddon)

*World of Warcraft and Warcraft are trademarks of Blizzard Entertainment, Inc. This is a fan project, not affiliated with or endorsed by Blizzard.*
