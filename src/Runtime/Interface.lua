--=============================================================================
-- INTERFACE — the hub's window, built on StrawberryUI
--=============================================================================
--  Replaces the ~900 lines of bespoke UI code the runtime used to carry. Every
--  control below drives the same runtime function it always did; only the
--  presentation layer changed.
--
--  This module owns no state. It reads the runtime's tables, writes to them
--  through their own setters, and keeps a single status loop refreshing the
--  labels — one loop for all of them, not one per label.
--=============================================================================

local UI = require("UI")

local Interface = {}

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

-- internal : StrawberryHub.Internal. hub : the StrawberryHub table itself.
function Interface.build(internal, hub)
    local Config = internal.Config
    local State = internal.State
    local Core = internal.Core
    local Move = internal.Move
    local Attack = internal.Attack
    local Enemies = internal.Enemies
    local Quests = internal.Quests
    local Farming = internal.Farming
    local Combat = internal.Combat
    local Materials = internal.Materials
    local Teleport = internal.Teleport
    local Shop = internal.Shop
    local PlayerModule = internal.PlayerModule
    local Performance = internal.Performance
    local AntiDetection = internal.AntiDetection
    local Server = internal.Server
    local Events = internal.Events
    local FastAttack = internal.FastAttack
    local Diagnostics = internal.Diagnostics
    local Persist = internal.Persist
    local Util = internal.Util

    local function save() Persist.save() end

    local window = UI:CreateWindow({
        Title = "Strawberry Hub",
        Subtitle = ("Blox Fruits · Sea %d"):format(State.sea),
        Size = UDim2.fromOffset(600, 400),
    })

    -----------------------------------------------------------------------
    -- Auto Farm
    -----------------------------------------------------------------------

    local farmTab = window:CreateTab({ Name = "Auto Farm" })

    local farmSection = farmTab:CreateSection({ Name = "Farming" })

    State.selectedWeapon = Config.Farming.WeaponType or Attack.AUTO

    local weaponDropdown = farmSection:CreateDropdown({
        Name = "Weapon",
        Description = "Which weapon the farm equips before engaging",
        Values = internal.listWeapons(),
        Default = State.selectedWeapon,
        Callback = function(value)
            State.selectedWeapon = value
            Config.Farming.WeaponType = value
            save()
        end,
    })

    farmSection:CreateButton({
        Name = "Refresh weapon list",
        Callback = function()
            weaponDropdown:Refresh(internal.listWeapons())
            UI:Notify({ Title = "Weapons", Content = "List refreshed", Duration = 2 })
        end,
    })

    farmSection:CreateDropdown({
        Name = "Mode",
        Values = { "Quest", "No Quest" },
        Default = Config.Farming.Mode,
        Callback = function(value)
            Config.Farming.Mode = value
            save()
        end,
    })

    farmSection:CreateToggle({
        Name = "Auto Farm Level",
        Description = "Farm the active quest's mobs continuously",
        Default = false,
        Callback = function(value) Farming.set(value) end,
    })

    farmSection:CreateToggle({
        Name = "Automation Core",
        Description = "Dynamic detection, state machine and recovery. "
            .. "Off falls back to the legacy hardcoded-coordinate loop.",
        Default = Config.Farming.UseAutomationCore,
        Callback = function(value)
            Config.Farming.UseAutomationCore = value
            -- Hand back cleanly: otherwise the anchor and bring driver stay
            -- posted while the core is no longer running.
            if not value and hub.AutomationCore then
                pcall(function() hub.AutomationCore:stop() end)
            end
            save()
        end,
    })

    local movementSection = farmTab:CreateSection({ Name = "Movement" })

    movementSection:CreateSlider({
        Name = "Travel speed",
        Description = "Capped at 200 studs/s — beyond that the game flags it",
        Min = 50, Max = 200, Default = Config.Farming.TweenSpeed, Rounding = 0,
        Callback = function(value)
            Config.Farming.TweenSpeed = math.min(value, Config.Farming.MaxTweenSpeed)
            save()
        end,
    })

    movementSection:CreateSlider({
        Name = "Height above mob",
        Min = 0, Max = 40, Default = Config.Farming.AttackHeight, Rounding = 0,
        Callback = function(value)
            Config.Farming.AttackHeight = value
            save()
        end,
    })

    movementSection:CreateSlider({
        Name = "Side offset",
        Min = 0, Max = 15, Default = Config.Farming.SafeDistance, Rounding = 0,
        Callback = function(value)
            Config.Farming.SafeDistance = value
            save()
        end,
    })

    movementSection:CreateToggle({
        Name = "Safe mode",
        Description = "Never mutates mob state (size, speed). Recommended.",
        Default = Config.Farming.SafeMode,
        Callback = function(value)
            Config.Farming.SafeMode = value
            save()
        end,
    })

    local bringSection = farmTab:CreateSection({ Name = "Bring Mob" })

    bringSection:CreateToggle({
        Name = "Bring Mob",
        Description = "Mobs come to you instead of you chasing them",
        Default = Config.Farming.BringMob,
        Callback = function(value)
            Config.Farming.BringMob = value
            if not value then Attack.releaseHold() end
            save()
        end,
    })

    bringSection:CreateToggle({
        Name = "Quest mobs only",
        Description = "Never pull anything the active quest does not name",
        Default = Config.Farming.BringQuestOnly,
        Callback = function(value)
            Config.Farming.BringQuestOnly = value
            save()
        end,
    })

    bringSection:CreateSlider({
        Name = "Bring radius",
        Min = 50, Max = 1000, Default = Config.Farming.BringDistance, Rounding = 0,
        Callback = function(value)
            Config.Farming.BringDistance = value
            save()
        end,
    })

    bringSection:CreateSlider({
        Name = "Bring height",
        Min = 2, Max = 40, Default = Config.Farming.BringHeight, Rounding = 0,
        Callback = function(value)
            Config.Farming.BringHeight = value
            save()
        end,
    })

    local statusSection = farmTab:CreateSection({ Name = "Status" })
    local targetLabel = statusSection:CreateLabel({ Name = "Target: —" })
    local engineLabel = statusSection:CreateLabel({ Name = "Combat engine: —" })
    local toolLabel = statusSection:CreateLabel({ Name = "Held weapon: —" })

    -----------------------------------------------------------------------
    -- Combat
    -----------------------------------------------------------------------

    local combatTab = window:CreateTab({ Name = "Combat" })
    local targetSection = combatTab:CreateSection({ Name = "Target" })

    local targetDropdown = targetSection:CreateDropdown({
        Name = "Selected target",
        Values = Enemies.listNames(),
        Callback = function(value) Config.Combat.SelectedTarget = value end,
    })

    targetSection:CreateButton({
        Name = "Refresh target list",
        Callback = function()
            targetDropdown:Refresh(Enemies.listNames())
            UI:Notify({ Title = "Targets", Content = "List refreshed", Duration = 2 })
        end,
    })

    targetSection:CreateToggle({
        Name = "Farm selected target",
        Default = false,
        Callback = function(value) Combat.setTarget(value) end,
    })

    targetSection:CreateToggle({
        Name = "Kill Aura",
        Default = false,
        Callback = function(value) Combat.setKillAura(value) end,
    })

    targetSection:CreateSlider({
        Name = "Kill Aura range",
        Min = 20, Max = 250, Default = Config.Combat.AuraRange, Rounding = 0,
        Callback = function(value) Config.Combat.AuraRange = value end,
    })

    local fastSection = combatTab:CreateSection({ Name = "Fast Attack" })

    fastSection:CreateToggle({
        Name = "Fast Attack",
        Default = Config.FastAttack.Enabled,
        Callback = function(value)
            Config.FastAttack.Enabled = value
            if not value then FastAttack:Stop() end
            save()
        end,
    })

    fastSection:CreateToggle({
        Name = "No animation",
        Description = "Hides combat animations client-side",
        Default = Config.FastAttack.NoAnimation,
        Callback = function(value)
            FastAttack:SetNoAnimation(value)
            save()
        end,
    })

    fastSection:CreateSlider({
        Name = "Attack interval (ms)",
        Min = 20, Max = 500,
        Default = math.floor(Config.FastAttack.Interval * 1000), Rounding = 0,
        Callback = function(value)
            Config.FastAttack.Interval = value / 1000
            save()
        end,
    })

    fastSection:CreateSlider({
        Name = "Fast Attack range",
        Min = 10, Max = 200, Default = Config.FastAttack.Range, Rounding = 0,
        Callback = function(value)
            Config.FastAttack.Range = value
            save()
        end,
    })

    fastSection:CreateSlider({
        Name = "Simultaneous targets",
        Min = 1, Max = 30, Default = Config.FastAttack.MaxTargets, Rounding = 0,
        Callback = function(value)
            Config.FastAttack.MaxTargets = value
            save()
        end,
    })

    local engineSection = combatTab:CreateSection({ Name = "Engine" })

    engineSection:CreateDropdown({
        Name = "Fallback method",
        Values = Attack.METHODS,
        Default = Config.Combat.Method,
        Callback = function(value)
            Config.Combat.Method = value
            save()
        end,
    })

    engineSection:CreateSlider({
        Name = "Hitbox range",
        Min = 20, Max = 250, Default = Config.Combat.HitboxRange, Rounding = 0,
        Callback = function(value)
            Config.Combat.HitboxRange = value
            save()
        end,
    })

    engineSection:CreateSlider({
        Name = "Delay between attacks (ms)",
        Min = 30, Max = 500,
        Default = math.floor(Config.Combat.AttackDelay * 1000), Rounding = 0,
        Callback = function(value)
            Config.Combat.AttackDelay = value / 1000
            save()
        end,
    })

    engineSection:CreateButton({
        Name = "Repair deformed mobs",
        Callback = function()
            local repaired = Attack.repairMobs()
            UI:Notify({
                Title = "Repair",
                Content = ("%d mob(s) restored"):format(repaired),
                Duration = 5,
            })
        end,
    })

    engineSection:CreateButton({
        Name = "Restart calibration",
        Description = "Retests every attack strategy from scratch",
        Callback = function()
            State.workingMethod = nil
            State.damageSeen = 0
            State.attackCount = 0
            UI:Notify({
                Title = "Calibration",
                Content = "Testing each strategy again",
                Duration = 5,
            })
        end,
    })

    engineSection:CreateButton({
        Name = "Reset combat engine",
        Callback = function()
            Attack.init()
            Attack.hookAnimations()
            UI:Notify({
                Title = "Combat engine",
                Content = Attack.ready() and "Ready"
                    or ("Failed: " .. tostring(State.attackError)),
                Duration = 6,
            })
        end,
    })

    -----------------------------------------------------------------------
    -- Materials
    -----------------------------------------------------------------------

    local materialsTab = window:CreateTab({ Name = "Materials" })
    local materialsSection = materialsTab:CreateSection({ Name = "Farm material" })

    for _, name in ipairs(Util.keys(Config.Materials)) do
        materialsSection:CreateToggle({
            Name = name,
            Default = false,
            Callback = function(value) Materials.set(name, value) end,
        })
    end

    -----------------------------------------------------------------------
    -- Teleport
    -----------------------------------------------------------------------

    local teleportTab = window:CreateTab({ Name = "Teleport" })
    local travelSection = teleportTab:CreateSection({ Name = "Travel" })

    travelSection:CreateButton({
        Name = "Teleport to Sea 1",
        Description = "Main",
        Arrow = true,
        Callback = function() Teleport.toSea(1) end,
    })

    travelSection:CreateButton({
        Name = "Teleport to Sea 2",
        Description = "Dressrosa",
        Arrow = true,
        Callback = function() Teleport.toSea(2) end,
    })

    travelSection:CreateButton({
        Name = "Teleport to Sea 3",
        Description = "Zou",
        Arrow = true,
        Callback = function() Teleport.toSea(3) end,
    })

    local islandsSection = teleportTab:CreateSection({ Name = "Islands" })

    local islandDropdown = islandsSection:CreateDropdown({
        Name = "Select island",
        Values = Teleport.listIslands(),
        Callback = function(value) State.selectedIsland = value end,
    })

    islandsSection:CreateButton({
        Name = "Teleport to island",
        Arrow = true,
        Callback = function()
            if State.selectedIsland then
                Teleport.toIsland(State.selectedIsland)
            else
                UI:Notify({
                    Title = "Teleport",
                    Content = "Pick an island first",
                    Duration = 3,
                })
            end
        end,
    })

    islandsSection:CreateButton({
        Name = "Refresh island list",
        Callback = function()
            islandDropdown:Refresh(Teleport.listIslands())
        end,
    })

    -----------------------------------------------------------------------
    -- Shop
    -----------------------------------------------------------------------

    local shopTab = window:CreateTab({ Name = "Shop" })
    local generalSection = shopTab:CreateSection({ Name = "General" })

    generalSection:CreateButton({
        Name = "Redeem all codes",
        Callback = function()
            Shop.redeemAll()
            UI:Notify({ Title = "Shop", Content = "Codes redeemed", Duration = 4 })
        end,
    })

    generalSection:CreateButton({ Name = "Reroll race", Callback = Shop.rerollRace })
    generalSection:CreateButton({ Name = "Reset stats", Callback = Shop.resetStats })

    local abilitiesSection = shopTab:CreateSection({ Name = "Abilities" })
    for _, ability in ipairs(Config.Abilities) do
        abilitiesSection:CreateButton({
            Name = "Buy " .. ability.name,
            Arrow = true,
            Callback = function() Shop.buyAbility(ability) end,
        })
    end

    local stylesSection = shopTab:CreateSection({ Name = "Fighting styles" })
    for _, style in ipairs(Config.FightingStyles) do
        stylesSection:CreateToggle({
            Name = "Auto " .. style.name,
            Description = style.npc,
            Default = false,
            Callback = function(value) Shop.setFightingStyle(style, value) end,
        })
    end

    -----------------------------------------------------------------------
    -- Player
    -----------------------------------------------------------------------

    local playerTab = window:CreateTab({ Name = "Player" })
    local statsSection = playerTab:CreateSection({ Name = "Auto stats" })

    for _, key in ipairs(Util.keys(Config.Player.Stats)) do
        statsSection:CreateToggle({
            Name = key,
            Default = Config.Player.Stats[key],
            Callback = function(value)
                Config.Player.Stats[key] = value
                save()
            end,
        })
    end

    statsSection:CreateSlider({
        Name = "Points per tick",
        Min = 1, Max = 20, Default = Config.Player.StatsPerTick, Rounding = 0,
        Callback = function(value) Config.Player.StatsPerTick = value end,
    })

    statsSection:CreateToggle({
        Name = "Enable auto stats",
        Default = false,
        Callback = function(value) PlayerModule.setStats(value) end,
    })

    local miscPlayerSection = playerTab:CreateSection({ Name = "Session" })

    miscPlayerSection:CreateToggle({
        Name = "Anti AFK",
        Default = Config.Player.AntiAFK,
        Callback = function(value)
            Config.Player.AntiAFK = value
            save()
        end,
    })

    miscPlayerSection:CreateToggle({
        Name = "Auto Buso Haki",
        Default = Config.Player.AutoHaki,
        Callback = function(value)
            Config.Player.AutoHaki = value
            save()
        end,
    })

    -----------------------------------------------------------------------
    -- Server
    -----------------------------------------------------------------------

    local serverTab = window:CreateTab({ Name = "Server" })
    local serverSection = serverTab:CreateSection({ Name = "Server" })

    serverSection:CreateLabel({ Name = "Job ID: " .. tostring(game.JobId) })
    serverSection:CreateButton({
        Name = "Rejoin same server",
        Arrow = true,
        Callback = Server.rejoin,
    })
    serverSection:CreateButton({
        Name = "Server hop",
        Arrow = true,
        Callback = function() Server.hop(false) end,
    })
    serverSection:CreateButton({
        Name = "Hop to least populated",
        Arrow = true,
        Callback = function() Server.hop(true) end,
    })

    -----------------------------------------------------------------------
    -- Misc
    -----------------------------------------------------------------------

    local miscTab = window:CreateTab({ Name = "Misc" })
    local eventsSection = miscTab:CreateSection({ Name = "Events" })

    eventsSection:CreateToggle({
        Name = "Auto Sea Beast",
        Default = false,
        Callback = function(value) Events.setSeaBeast(value) end,
    })

    local perfSection = miscTab:CreateSection({ Name = "Performance" })
    perfSection:CreateButton({ Name = "FPS boost", Callback = Performance.fpsBoost })
    perfSection:CreateButton({ Name = "Remove fog", Callback = Performance.removeFog })

    local controlSection = miscTab:CreateSection({ Name = "Control" })

    controlSection:CreateToggle({
        Name = "Debug logs",
        Default = Config.Debug,
        Callback = function(value)
            Config.Debug = value
            save()
        end,
    })

    controlSection:CreateButton({
        Name = "Stop everything",
        Description = "Disables every running loop at once",
        Callback = function()
            Core.stopAll()
            Move.stopTween()
            UI:Notify({
                Title = "Stopped",
                Content = "All features disabled",
                Duration = 4,
            })
        end,
    })

    controlSection:CreateButton({
        Name = "Unload hub",
        Arrow = true,
        Callback = function()
            if getgenv().StrawberryHub then getgenv().StrawberryHub.Unload() end
        end,
    })

    -----------------------------------------------------------------------
    -- Diagnostics
    -----------------------------------------------------------------------

    local diagTab = window:CreateTab({ Name = "Diagnostics" })
    local diagSection = diagTab:CreateSection({ Name = "Instrumentation" })

    local diagStateLabel = diagSection:CreateLabel({ Name = "State: off" })

    diagSection:CreateToggle({
        Name = "Enable measurement",
        Description = "Costs nothing while off — a single boolean test per probe",
        Default = Config.Diagnostics.Enabled,
        Callback = function(value)
            Config.Diagnostics.Enabled = value
            Diagnostics.setEnabled(value)
            save()
        end,
    })

    diagSection:CreateButton({
        Name = "Export report",
        Arrow = true,
        Callback = function()
            Diagnostics.Export()
            UI:Notify({
                Title = "Diagnostics",
                Content = "Copied to clipboard + StrawberryHub/diagnostics.txt",
                Duration = 6,
            })
        end,
    })

    diagSection:CreateButton({
        Name = "Reset counters",
        Callback = function()
            Diagnostics.reset()
            UI:Notify({ Title = "Diagnostics", Content = "Counters reset", Duration = 4 })
        end,
    })

    local coreSection = diagTab:CreateSection({ Name = "Automation Core" })
    local coreLabel = coreSection:CreateLabel({ Name = "Core: not attached" })

    -----------------------------------------------------------------------
    -- Protection
    -----------------------------------------------------------------------

    local protTab = window:CreateTab({ Name = "Protection" })
    local protSection = protTab:CreateSection({ Name = "Anti-detection" })

    local protLabel = protSection:CreateLabel({ Name = "State: —" })

    protSection:CreateToggle({
        Name = "Anti-detection",
        Description = "Blocks the game's detection / ban / kick telemetry",
        Default = Config.AntiDetection.Enabled,
        Callback = function(value)
            Config.AntiDetection.Enabled = value
            if value then
                AntiDetection.enable()
            else
                -- The hook stays in place — removing it entirely is riskier
                -- than leaving it pass-through.
                UI:Notify({
                    Title = "Anti-detection",
                    Content = "Paused — hook left in place, passing everything through",
                    Duration = 4,
                })
            end
            save()
        end,
    })

    protSection:CreateToggle({
        Name = "Block abuse-report screenshots",
        Default = Config.AntiDetection.DisableAbuseScreenshots,
        Callback = function(value)
            Config.AntiDetection.DisableAbuseScreenshots = value
            if value then AntiDetection.startFFlags() end
            save()
        end,
    })

    protSection:CreateButton({
        Name = "Reapply hooks",
        Callback = function()
            AntiDetection.enable()
            UI:Notify({
                Title = "Anti-detection",
                Content = AntiDetection.isActive() and "Active"
                    or ("Failed: " .. tostring(State.antiDetectError)),
                Duration = 5,
            })
        end,
    })

    -----------------------------------------------------------------------
    -- Status loop — one loop for every label, not one per label
    -----------------------------------------------------------------------

    State.flags.Status = true
    Core.loop("Status", 1, function()
        local quest = Quests.current()
        targetLabel:SetText(quest
            and ("Target: %s  (Lv %d)"):format(quest.Name, Core.level())
            or "Target: —")

        engineLabel:SetText(Attack.ready() and "Combat engine: ready"
            or ("Combat engine: FAILED — " .. tostring(State.attackError)))

        diagStateLabel:SetText(Diagnostics.isEnabled()
            and "State: measuring — remember to export"
            or "State: off (no cost)")

        protLabel:SetText(("State: %s   |   Blocked remotes: %d"):format(
            AntiDetection.isActive()
                and (Config.AntiDetection.Enabled and "ACTIVE" or "paused (hook in place)")
                or ("INACTIVE — " .. tostring(State.antiDetectError or "not installed")),
            #Config.AntiDetection.Remotes))

        local core = hub.AutomationCore
        coreLabel:SetText(core and ("Core: " .. core:describe()) or "Core: not attached")

        local character = Core.character()
        local held = character and character:FindFirstChildOfClass("Tool")
        local tooltip = "-"
        if held then
            local okTip, text = pcall(function() return held.ToolTip end)
            if okTip and text and text ~= "" then tooltip = text end
        end

        toolLabel:SetText(("%s (%s) | Blade: %s | %s%s | Hits: %d | Damage: %d"):format(
            held and held.Name or "fists", tooltip,
            Attack.bladeName() or "none",
            Attack.currentStrategy(),
            State.workingMethod and " OK" or " ?",
            State.attackCount or 0, State.damageSeen or 0))
    end)

    UI:Notify({
        Title = "Strawberry Hub",
        Content = ("Loaded — Sea %d"):format(State.sea),
        Duration = 5,
    })

    return window
end

return Interface
