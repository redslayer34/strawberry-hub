# Strawberry Hub

Blox Fruits script. Its window is Banana Hub's UI recoloured in strawberry red (bundled, nothing downloaded);
`getgenv().StrawberryUI = "Fluent"` before the loader brings back the [Fluent](https://github.com/dawid-scripts/Fluent) window.

## Loader

Paste this into your executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/redslayer34/strawberry-hub/claude/repo-exploration-ez26bn/StrawberryHub.lua"))()
```

Optional, before the loader: `getgenv().StrawberryTeam = "Marines"` (default: Pirates).

`LeftControl` shows / hides the window, and so does the round strawberry button (bottom left, draggable).
Settings are saved automatically (`StrawberryHub/BloxFruits/settings/autosave.json`)
and loaded on the next run.

## Strawberry Volcano (Prehistoric Island)

A standalone script that does the Prehistoric Island over and over, with no window:
it crafts the Volcanic Magnet (10 Scrap Metal, 15 Blaze Ember from the Dragon Hunter), sails out
until the island spawns, runs the volcano event (Lava Golems, erupting rocks), collects the
dragon eggs and dino bones, resets, and starts again. It is the hub's "Fully Prehistoric Island"
(Banana's flow) with a small status panel (`RightControl` hides it). Sea 3, level 1500.

```lua
getgenv().StrawberryVolcano = {
    Weapon = "Melee",        -- golems and the magnet's mobs: "Melee", "Sword" or "Blox Fruit"
    SkillWeapons = { Melee = true, Sword = true, ["Blox Fruit"] = true, Gun = true },  -- skills on the rocks
    CraftMagnet = true,      -- false: bring your own Volcanic Magnet
    CollectEggs = true,      -- the Dragon Eggs after the event
    CollectBones = true,
    Boat = "Guardian",
    Speed = 150,             -- flying speed (Teddy's; faster makes hits land late)
    BoatSpeed = 350,
    Team = "Pirates",
    WalkOnWater = true,
    SecureHits = false,      -- test: the newer hubs' extra hit check
    FpsBoost = false,
    BlackScreen = false,
    WebhookUrl = "",         -- your own webhook: a message when the island spawns
    ShowScreen = true,
}
loadstring(game:HttpGet("https://raw.githubusercontent.com/redslayer34/strawberry-hub/claude/repo-exploration-ez26bn/StrawberryVolcano.lua"))()
```

Anything left out keeps its default. Loading it unloads the hub or the Kaitun, and the other way round.

## Features

The hub is being rewritten in steps, each tested in game before the next.

| Step | Content | State |
|---|---|---|
| 1 | Fluent UI, level farm (quest, attack, bring mob, flying), status panel | done |
| 2a | Boss, Katakuri, Bones, Material, Kill Mob, Aura farms; Mastery; touch-friendly sliders | done |
| 2b | Teleport (islands, NPCs, seas), Shop, Player (auto stats, team, speed), Server (status, hop, rejoin, JobId, reload after hop) | **this version** |
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

## Simulator (find bugs without the game)

`tools/sim.py` replays a real case against a fake Blox Fruits: an account profile, a strict fake server
(it only moves forward when the step is really done), the character flying, boats, seats, hits, deaths,
skill cooldowns and a virtual clock. The report lists every status the hub showed and the incidents
(stuck, flapping, errors, remotes nobody answered).

```bash
python3 tools/sim.py --list            # the scenarios (tools/sim/scenarios/)
python3 tools/sim.py guitar_puzzle     # one (report also in build/sim-guitar_puzzle.txt)
python3 tools/sim.py all               # every one (also the "sim" suite of tools/test.py)
```

Subagents in `.claude/agents/` write and run scenarios for you (ask Claude Code to use one):

| Agent | For |
|---|---|
| `sim-scenario-writer` | any feature or bug report: writes a new scenario and runs it |
| `sim-soul-guitar` | the Soul Guitar chain and its puzzle |
| `sim-leviathan` | spy, Frozen Dimension, the fight, the heart harpoon |
| `sim-sea-events` | volcano / Prehistoric, Kitsune, Mirage, sea beasts, boats |
| `sim-kaitun` | account profiles through the Kaitun engine (stuck tasks, loops) |
| `sim-travel` | router, portals, respawn teleports, sea travel |
| `sim-bug-hunter` | runs everything, groups the incidents, digs into the worst |

## Development

`StrawberryHub.lua` is a **build artifact**. Edit `src/`, then re-pack.

```
src/
├── main.lua              entry point: game ready → engine → interface → Unload
├── kaitun.lua            entry point of StrawberryKaitun.lua (Kaitun/)
├── volcano.lua           entry point of StrawberryVolcano.lua (Volcano/)
├── Core/                 Services, Settings, Loop, Player
├── Game/                 Quests, Enemies, Movement, Combat, Bring, Mastery, AimHook, World, Server, Data
├── Features/             Farm (one mode at a time), Travel, Fight, MobFarm, the farm modes, Stats, PlayerTweaks
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
