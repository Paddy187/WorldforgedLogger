# Worldforged Logger

A small World of Warcraft 3.3.5a addon that logs every **Worldforged** item you loot from the world — item ID, map, coordinates and more in its own database, so you can easily add missing items to LootCollector.

It works standalone, and gets extra features when LootCollector is installed.

## Features

- **Automatic logging** of Worldforged items (detected via the "Worldforged" line in the item tooltip, the same way LootCollector does it).
- **World loot only**: items are logged when they come from a loot window or a gather/open cast. Vendor purchases, mail, trades, bank and quest rewards are ignored.
- **Complete data per item**: item ID (base ID for upgraded items), name, quality, continent, map area ID, instance zone (`iz`), X/Y position (4 decimals), zone, subzone, source/target, finder, first/last seen and count.
- **Duplicate-safe**: the same item on the same map within a small radius is counted instead of being logged twice.
- **Own saved data**: everything is stored in a separate SavedVariables file (`WorldforgedLoggerDB`), independent of any other addon.
- **Options page with a table** of everything logged so far, including a *In LootCollector* column (Yes / Other map / No) when LootCollector is loaded.
- **Export** to three formats (copy with Ctrl+C):
  - **Full Lua** – every field as a Lua table
  - **CoordAuthority** – ready-to-paste rows for LootCollector's `Modules\CoordAuthority.lua`
  - **CSV** – for spreadsheets
- **"Only show items missing in LootCollector"** filter, applied to both the table and the exports.
- **Manual add**: `/wfl add [item link]` logs an item at your current position.