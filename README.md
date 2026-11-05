# Synastria Companion

Cleaner, faster replacements for Synastria's own windows, in one flat window that matches
[Synastria Build Suite](https://github.com/iExpulsion/SynastriaBuildSuite). When the game opens one of the windows
it covers, Companion opens instead.

## Screens

### Attunable Items

The attune search, rebuilt:

- **Every result is shown.** The game's window stops at 500.
- **Filters apply as you type.** No Search button.
- **Sortable columns:** item, slot, item level, required level, number of sources, and status (attuned, with its
  forge, or attune progress).
- **The same filters as the game:** mode (Attunable or Attuned, for the character or the account, or All), class
  for multi-class characters, rarity, slot, Mythic, Has Affix, more than five sources, level ranges and zone.
- **The attuned share** of everything your filters match, shown below the list.
- **Click** an item to open it in the Loot Database. **Shift-click** links it.

### Loot Database

- **Live search** across every item, with no cap on results.
- **Where an item comes from:** a sortable table of its sources, with type, zone, drop chance and drops per 1000.
  Quests for the other faction are left out.
- **What a creature or object drops:** click a creature or container source, or use **Target's Loot** for your
  target. **Still to Attune** narrows it to what you haven't attuned.
- **Back** walks through everything you opened, so you can follow a drop chain and come back.
- **Right-click** a source to track it on the map.
- **Options** opens the game's Loot Database settings (Alt-click to open items, source lines in tooltips).

More screens are on the way: Attuned Items, Resource Bank, Leaderboards and Lootfilter.

## Commands

- `/scomp` or `/companion`: opens or closes the window.
- `/scomp attunable` or `/scomp lootdb`: opens a screen.
- `/scomp replace attunable off`: gives a screen back to the game's own window (`on` takes it back).

The **Game Window** button in the title bar opens the game's own window for the screen you're on.

## Install

Download the latest release, extract the `SynastriaCompanion` folder into `Interface/AddOns`, and restart the game.
