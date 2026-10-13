# TFAlert (Tiger's Fury Alert) - Turtle WoW & Vanilla 1.12.1

A lightweight, high-performance alert addon for Feral Druids on **Turtle WoW** (and Vanilla 1.12.1), adapted from [BSAlert-TW](https://github.com/FSuhas/BSAlert-TW).

---

## 🐾 Why Tiger's Fury Matters on Turtle WoW

In Turtle WoW's custom class rebalancing, **Tiger's Fury** was reworked into an essential rotational buff for Feral Druids:
* **Cost:** 30 Energy (Instant cast, 1 sec cooldown, requires Cat Form)
* **Effect:** Increases damage done by +50 **and regenerates 10 Energy every 3 sec for 18 sec** (Rank 4)
* **Net Value:** Generates **60 Energy** over 18 seconds for a net profit of **+30 Energy** and bonus damage!

Maintaining 100% uptime on Tiger's Fury in Cat Form is critical to optimal DPS and energy flow. **TFAlert** alerts you the exact moment Tiger's Fury is missing during combat so you never lose energy ticks or damage!

---

## ✨ Features

- **Smart Cat Form Detection:** Only alerts when you are actively in **Cat Form**. Switching to Bear Form, Caster Form, Travel Form, or dying will automatically suppress the alert.
- **Combat-Aware:** Shows the alert during combat when Tiger's Fury is down.
- **Spellbook Check:** Automatically checks if your Druid has learned Tiger's Fury, avoiding unwanted alerts on low-level characters before learning the ability.
- **Interactive Move & Resize Mode:** Type `/tfmove` to drag the icon anywhere on your screen and adjust its size live using the slider (from 64px to 256px).
- **Test Mode:** Type `/tftest` to preview the icon on your screen for 5 seconds without needing to get into combat.
- **Early Warning Threshold:** Optional `/tfthreshold <seconds>` command to alert you slightly before the buff expires (e.g., 2 seconds before).
- **Optional Sound:** Toggle an audio alert with `/tfsound` when Tiger's Fury drops.
- **Backward Compatibility:** All original slash commands (`/bsmove`, `/bsreset`, `/bshelp`) and SavedVariables (`BSAlertDB`) are fully supported.

---

## 📦 Installation

1. Copy or move this `TFAlert` folder into your World of Warcraft directory:
   ```text
   World of Warcraft\Interface\AddOns\TFAlert\
   ```
2. Restart your WoW client or type `/reload` if you use an addon reloader.
3. Log into your Druid. You will see a welcome message in your chat log:
   `TFAlert Turtle: Type /tfhelp for options.`

---

## ⚙️ Slash Commands

| Command | Description |
| :--- | :--- |
| `/tfmove` *(or `/bsmove`)* | Toggle edit mode to drag the icon and resize it with the slider |
| `/tfreset` *(or `/bsreset`)* | Reset position and size back to default center (128px) |
| `/tftest` | Preview the alert icon on your screen for 5 seconds |
| `/tfcombat` | Toggle whether combat is required (Default: **ON**) |
| `/tfcatform` | Toggle whether Cat Form is required (Default: **ON**) |
| `/tfsound` | Toggle audio alert when the buff expires (Default: **OFF**) |
| `/tfthreshold <sec>` | Set early warning in seconds before buff expires (Default: **0**) |
| `/tfhelp` *(or `/bshelp`, `/tf`)* | Display the in-game command list |

---

## 🌟 Credits & Acknowledgements

* **Original Addon ([BSAlert-TW](https://github.com/FSuhas/BSAlert-TW)):** Created by **[FSuhas / GondoLeon](https://github.com/FSuhas)** (Gon, do, Leon) for the Battle Shout alert foundation, draggable frame logic, and scale slider interface.
* **Concept & Feature Idea:** Proposed by **Wonky** to adapt the system for Turtle WoW's reworked Feral Druid Tiger's Fury mechanics.
* **Adaptation & Improvements:** Enhanced with Cat Form awareness, spellbook detection, sound notification, threshold warnings, and anchor-safe positioning for Turtle WoW and Vanilla 1.12.1.

---

## ?? Development

Run the verification suite before every commit (uses the bundled real Lua 5.0.3 compiler/interpreter in `tools/bin/lua50`):

```bash
python tools/run_tests.py
```

Build a clean release zip (runs tests first, strips `tools/` and dotfiles):

```bash
python tools/package.py
```

