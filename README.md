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

### Attuned Items

- **One table of every stat your attuned items give**, with a **Total** of what this character actually gets beside
  Misc, your armor type and Weapon, plus an **Inactive** column for attuned gear this character can't use.
- **Sortable:** by stat, or by any column to see your biggest bonuses first.
- **Load Stats / Refresh** asks the server for the latest numbers (it casts View Attuned Items, so it works out of
  combat only).

### Loot Database

- **Live search** across every item, with no cap on results.
- **Where an item comes from:** a sortable table of its sources, with type, zone, drop chance and drops per 1000.
  Quests for the other faction are left out.
- **What a creature or object drops:** click a creature or container source, or use **Target's Loot** for your
  target. **Still to Attune** narrows it to what you haven't attuned.
- **Back** walks through everything you opened, so you can follow a drop chain and come back.
- **Right-click** a source to track it on the map.
- **Options** opens the game's Loot Database settings (Alt-click to open items, source lines in tooltips).

### Resource Bank

- **A type list beside the materials:** All, Recently Looted, then each type with how many it holds, in sections:
  Gathering (Ores & Metals, Herbs, Leather & Scales, Cloth, Cooking), Crafting (Elemental, Enchanting, Gems,
  Alchemy, Inscription, Engineering), Reagents and Other. One click shows just that type.
- **Materials the game files as "Other"** (pigments, vials, orbs, venom sacs...) are sorted into the type they're
  used with.
- **What you carry beside what's stored:** In Bank, In Bags and Looted columns, all sortable.
- **Click** a material to withdraw a stack, **right-click** to deposit every stack you carry, or use
  **Deposit All**.
- Live search, and the list updates as the bank changes.

### Leaderboards

- **Every board in one list:** the general boards, then dungeons and raids by expansion (WotLK, TBC, Classic and
  their Mythic versions), then prestiged runs. Click an expansion to open its boards.
- **The ranks in a table** with place, player and account, score (counts, times or percentages) and date. Your own
  place is highlighted and scrolled into view.
- **Refresh** asks for a board again; the server answers at most once a minute per board.

More screens are on the way: Lootfilter.

## Commands

- `/scomp` or `/companion`: opens or closes the window.
- `/scomp attunable`, `/scomp attuned`, `/scomp lootdb`, `/scomp bank` or `/scomp leaderboards`: opens a screen.
- `/scomp replace attunable off`: gives a screen back to the game's own window (`on` takes it back).

The **Game Window** button in the title bar opens the game's own window for the screen you're on.

## Install

Download the latest release, extract the `SynastriaCompanion` folder into `Interface/AddOns`, and restart the game.
