# Synastria Companion

Cleaner, faster replacements for Synastria's own windows, in one flat window that matches
[Synastria Build Suite](https://github.com/iExpulsion/SynastriaBuildSuite). When the game opens one of the windows
it covers, Companion opens instead, and the **minimap button** opens any screen without the game's spells.

![The Synastria Companion window on Attunable Items: the screens in the sidebar, filters across the top, and every attunable item in a sortable table](docs/images/attunable-items.png)

## Screens

### Attunes

#### Attuned Stats

- **One table of every stat your attuned items give**, grouped like a character sheet, with a **Total** of what
  this character actually gets beside Misc, your armor type and Weapon, plus an **Inactive** column for attuned gear
  this character can't use. Hover a column name for what it counts.
- **Sortable:** by stat, or by any column to see your biggest bonuses first.
- **Load Stats / Refresh** asks the server for the latest numbers (it casts View Attuned Items, so it works out of
  combat only).

![Attuned Stats: attributes, physical and spell stats with Total, Misc, Plate, Weapon and Inactive columns](docs/images/attuned-stats.png)

#### Attunable Items

The attune search, rebuilt:

- **Every result is shown.** The game's window stops at 500.
- **Filters apply as you type.** No Search button.
- **Sortable columns:** item, slot, item level, required level and number of sources, plus each attuned item's
  forge in the modes that list attuned items.
- **The same filters as the game:** mode (Attunable or Attuned, for the character or the account, or All), class
  for multi-class characters, rarity, slot, Mythic, Has Affix, more than five sources, level ranges and zone.
- **The attuned share** of everything your filters match, shown below the list.
- **Click** an item to open it in the Item Database. **Shift-click** links it.

### Loot

#### Auto Loot

The game's Lootfilter:

- **Rules on the left, the selected rule on the right:** its name, on or off, what must match (all conditions, any,
  or the first and any other), what to do, and up to eight conditions. Counters show how close you are to the
  limits of 32 rules and 8 conditions.

![Auto Loot: the rule list with each rule's action, and the selected rule's match setting and item conditions](docs/images/auto-loot.png)
- **Every condition is searchable** by name, with a description on hover. Values use the right control for each:
  yes or no, a number, a choice, several choices, an item search, or a zone. **+** copies a condition.
- **Changes wait for Apply,** and **Discard** throws them away. Turning a rule on or off and the loot options save
  at once when nothing else is waiting.
- **Options** groups what gets looted under the Auto Loot switch: what you loot from, gathering, and what happens to
  items.

  ![Auto Loot options: the Auto Loot switch, then Loot From, Gathering and Items checkboxes](docs/images/auto-loot-options.png)

- **Export and Import** use the game's own share strings, for the whole filter or one rule, so filters others post
  still work. **Reset to Default** asks you to click twice.

#### Resource Bank

- **A type list beside the materials:** All, Recently Looted, then each type with how many it holds, in sections:
  Gathering, Crafting, Reagents and Other. One click shows just that type.
- **Materials the game files as "Other"** (pigments, vials, orbs, venom sacs...) are sorted into the type they're
  used with.
- **What you carry beside what's stored:** In Bank, In Bags and Looted columns, all sortable.
- **Click** a material to withdraw a stack, **right-click** to deposit every stack you carry, or use
  **Deposit All**.
- Live search, and the list updates as the bank changes.

![Resource Bank: material types by section on the left, and the materials with In Bank, In Bags and Looted counts](docs/images/resource-bank.png)

#### Item Database

The game's Loot Database:

- **Live search** across every item, with no cap on results.
- **Where an item comes from:** a sortable table of its sources, with type, zone, drop chance and drops per 1000.
  Quests for the other faction are left out.
- **What a creature or object drops:** click a creature or container source, or use **Target's Loot** for your
  target. **Still to Attune** narrows it to what you haven't attuned.
- **Back** walks through everything you opened, so you can follow a drop chain and come back.
- **Right-click** a source to track it on the map.
- **Options** opens the game's Loot Database settings (Alt-click to open items, source lines in tooltips).

![Item Database: a search for "heart" with each item's type, item level and attune status](docs/images/item-database.png)

### Community

#### Leaderboards

- **Every board in one list:** the general boards, then dungeons and raids by expansion (WotLK, TBC, Classic and
  their Mythic versions), then prestiged runs. Click an expansion to open its boards.
- **The ranks in a table** with place, player and account, score (counts, times or percentages), and the date on
  boards that have one. Your own place is highlighted and scrolled into view, and speed buff times show above it.
- **Refresh** asks for a board again; the server answers at most once a minute per board.

![Leaderboards: the board list by category, and the Total Attunes board's ranked players and scores](docs/images/leaderboards.png)

## Commands

- `/scomp` or `/companion`: opens or closes the window.
- `/scomp <screen>`: opens a screen: `attunable`, `attuned` (or `stats`), `lootfilter` (or `autoloot`), `bank`,
  `lootdb` (or `itemdb`), `leaderboards`.
- `/scomp minimap`: shows or hides the minimap button.
- `/scomp reset`: moves the window back to the center of the screen.
- `/scomp replace attunable off`: gives a screen back to the game's own window (`on` takes it back).

The **minimap button** opens or closes the window on a left-click and lists the screens on a right-click; drag it to
move it. The server only sends Attuned Stats when asked, so opening that screen asks for them on the same click,
from the minimap button, its menu or the sidebar. You don't need the game's View spells on your bars. That needs you
out of combat. The **Game Window** button in the title bar opens the game's own window for the screen you're on.

## Install

Download the latest release, extract the `SynastriaCompanion` folder into `Interface/AddOns`, and restart the game.
