# FishingMode

A small fishing addon for **WoW Forever** (interface 16001).

Type `/fishing` to enter fishing mode. One key then does everything:

1. Press it to cast Fishing.
2. Press it again when the bobber splashes to reel in. No need to hover the bobber.
3. The catch is looted automatically.

## Features

- Equips your fishing pole when fishing mode starts, and your weapons when it ends.
- Lowers music, ambience and dialog while fishing so you can hear the splash. Your normal volumes come back afterwards.
- Leaves fishing mode automatically when you enter combat.
- Options window for the key and the volume levels.

## Commands

| Command | What it does |
| --- | --- |
| `/fishing` | Turn fishing mode on or off |
| `/fishing options` | Open the options window |
| `/fishing key <KEY>` | Set the fishing key, e.g. `/fishing key G` or `/fishing key BUTTON3` |

The default key is `F`. It only takes effect while fishing mode is on.

## Install

Copy the `FishingMode` folder into:

```
World of Warcraft/forever/Interface/AddOns/
```

Restart the game, then enable **FishingMode** in the AddOns list on the character select screen.
