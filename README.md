# Strawberry Hub

Blox Fruits script with a [Fluent](https://github.com/dawid-scripts/Fluent) interface.

## Loader

Paste this into your executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/redslayer34/strawberry-hub/claude/repo-exploration-ez26bn/StrawberryHub.lua"))()
```

Optional, before the loader: `getgenv().StrawberryTeam = "Marines"` (default: Pirates).

`LeftControl` shows / hides the window. On mobile, tap the round **SH** button.
Settings are saved automatically (`StrawberryHub/BloxFruits/settings/autosave.json`)
and loaded on the next run.

## Features

The hub is being rewritten in steps, each tested in game before the next.

| Step | Content | State |
|---|---|---|
| 1 | Fluent UI, level farm (quest, attack, bring mob, flying), status panel | done |
| 2a | Boss, Katakuri, Bones, Material, Kill Mob, Aura farms; Mastery; touch-friendly sliders | **this version** |
| 2b | Teleport, shop, stats, server (hop to find bosses) | next |
| 3+ | Stack farming, sea events, raids / dungeon, race, items, volcano, ESP, PVP, webhook | later |

## How it works

Everything comes from the game's own data, nothing is guessed:

| Need | Source |
|---|---|
| Active quest | `ReplicatedStorage.GuideModule` → `Data.QuestData.Task` |
| Best quest for the level | `ReplicatedStorage.Quests` + `GuideModule.Data.NPCList` (current sea) |
| Taking a quest | `Remotes.CommF_:InvokeServer("StartQuest", quest, id)` |
| Mob spawn points | `workspace._WorldOrigin.EnemySpawns` |
| Attacking | `Modules.Net` `RE/RegisterAttack` then `RegisterHit`, hit parts via `Modules.CombatUtil` |

## Development

`StrawberryHub.lua` is a **build artifact**. Edit `src/`, then re-pack.

```
src/
├── main.lua              entry point: game ready → engine → interface → Unload
├── Core/                 Services, Settings, Loop, Player
├── Game/                 Quests, Enemies, Movement, Combat, Bring, Mastery, AimHook, Data
├── Features/             Farm (one mode at a time), Fight, MobFarm, the farm modes
└── UI/                   Fluent loader, Interface, Bind, TouchSlider, MobileButton, Tabs/
tools/
├── pack.py               bundles src/ into StrawberryHub.lua
├── unpack.py             reverse, to inspect an older build
├── test.py               runs the test suites without Roblox
├── stubs.lua             minimal Roblox environment
├── fakefluent.lua        stand-in for Fluent, with its real asserts
├── tests.lua             core suite
├── uitests.lua           interface suite
└── smoke*.lua            runs main.lua start to finish
```

```bash
python3 tools/test.py     # every suite
python3 tools/test.py ui  # one suite
python3 tools/pack.py     # rebuild StrawberryHub.lua (required before testing in game)
```

Every file under `src/` becomes a module named by its dotted path
(`src/Game/Quests.lua` → `Game.Quests`), resolved by a `require` shim embedded
in the bundle. Only modules reachable from `main` are shipped, and a `require`
naming a missing module fails the build. The shim hands anything that is not
a module name (a game `ModuleScript`) to the game's own `require`.

Source is plain Lua 5.1 syntax (no `+=`, `continue` or if-expressions) so the
tests run on stock Lua.
