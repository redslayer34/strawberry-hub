--=============================================================================
-- FARM TAB
--=============================================================================

local Bind = require("UI.Bind")
local Data = require("Game.Data")
local Enemies = require("Game.Enemies")
local Farm = require("Features.Farm")
local Loop = require("Core.Loop")
local Player = require("Core.Player")
local Quests = require("Game.Quests")
local Settings = require("Core.Settings")

local function statusText()
    local lines = {
        "Level " .. tostring(Player.level()) .. "  |  Sea " .. tostring(Player.sea() or "?"),
    }

    local quest = Quests.active() and Quests.target()
    if quest then
        local current, required = Quests.progress()
        local progress = current and (current .. "/" .. required) or ("x" .. tostring(quest.count))
        lines[#lines + 1] = "Quest: " .. quest.mob .. "  " .. progress
    else
        lines[#lines + 1] = "Quest: none"
    end

    lines[#lines + 1] = Quests.describe()
    lines[#lines + 1] = Farm.status()
    return table.concat(lines, "\n")
end

return function(Window)
    local tab = Window:AddTab({ Title = "Farm", Icon = "swords" })

    local level = tab:AddSection("Level Farm")
    Bind.toggle(level, "AutoFarmLevel", "Auto Farm Level",
        "Takes the best quest for your level and farms its mobs.")
    Bind.dropdown(level, "Weapon", "Weapon", Settings.WEAPONS,
        "Equipped automatically while farming.")
    Bind.toggle(level, "BringMob", "Bring Mob",
        "Gathers the quest's mobs on one spot.")
    Bind.slider(level, "BringCount", "Bring Count", 1, 5, 0,
        "How many mobs are gathered at once.")
    Bind.slider(level, "FarmHeight", "Farm Height", 5, 25, 0,
        "Studs above the mob. Too high and hits stop landing.")

    local bosses = tab:AddSection("Bosses")
    bosses:AddParagraph({
        Title = "One farm at a time",
        Content = "If several are on, the first one wins: Stack events > Boss > Katakuri > Tyrant > Bones > Material > Kill Mob > Aura > Level.",
    })
    Bind.toggle(bosses, "AutoBoss", "Auto Boss", "Kills the chosen boss once it has spawned.")
    Bind.dropdown(bosses, "Boss", "Boss", Data.BOSSES)
    Bind.toggle(bosses, "AllBosses", "Any Boss", "Kills whichever boss is alive instead.")
    Bind.toggle(bosses, "HopForBoss", "Hop to find it",
        "Changes server when the boss has not spawned for 15 seconds.")

    local sea3 = tab:AddSection("Sea 3")
    Bind.toggle(sea3, "AutoKatakuri", "Auto Katakuri",
        "Farms Cake Land mobs, then Cake Prince / Dough King when they spawn.")
    Bind.toggle(sea3, "IgnoreKatakuri", "Ignore Cake Prince", "Keep farming the mobs only.")
    Bind.toggle(sea3, "HopKatakuri", "Hop to find Cake Prince",
        "Changes server when Cake Prince has not been seen for 15 seconds.")
    Bind.toggle(sea3, "AutoTyrant", "Auto Tyrant of the Skies",
        "Tiki Outpost mobs; once the 4 eyes are lit, breaks the arena trees; then the Tyrant.")
    Bind.toggle(sea3, "AutoBone", "Auto Bones", "Farms the Haunted Castle mobs.")
    Bind.toggle(sea3, "FarmSpecialQuest", "Take the farm's quest",
        "Katakuri (2275+), Bones (2050+), Tyrant (2575+): takes their quest first, as Banana does.")

    local materials = tab:AddSection("Materials")
    Bind.dropdown(materials, "Material", "Material", Data.materialNames(),
        "Travels to the right sea by itself.")
    Bind.toggle(materials, "AutoMaterial", "Auto Material")

    local mobs = tab:AddSection("Kill Mob")
    local mobList = Bind.dropdown(mobs, "Mob", "Mob", Enemies.knownNames(),
        "Mobs of the current sea. Refresh after moving around.")
    mobs:AddButton({
        Title = "Refresh mob list",
        Callback = function() mobList:SetValues(Enemies.knownNames()) end,
    })
    Bind.toggle(mobs, "AutoKillMob", "Auto Kill Mob")

    local aura = tab:AddSection("Aura")
    Bind.toggle(aura, "AutoAura", "Auto Aura", "Kills every mob that comes within range, without moving away.")
    Bind.slider(aura, "AuraRadius", "Aura Radius", 50, 1000, 0)

    local mastery = tab:AddSection("Mastery")
    Bind.toggle(mastery, "MasteryFarm", "Mastery Farm",
        "Works with any farm: finishes low mobs with your fruit or gun skills.")
    Bind.dropdown(mastery, "MasteryWeapon", "Mastery Weapon", Settings.MASTERY_WEAPONS)
    Bind.slider(mastery, "MasteryHealth", "Switch Below Health %", 5, 100, 0)
    mastery:AddParagraph({ Title = "Skills", Content = "The keys used for each weapon are chosen in Combat & Skills below." })

    local helpers = tab:AddSection("Farm Helpers")
    Bind.toggle(helpers, "AutoClick", "Auto Click", "Hits whatever is within 80 studs when no farm is fighting.")
    Bind.toggle(helpers, "AutoKen", "Auto Observation", "Turns Ken (E) back on whenever it is off.")
    Bind.toggle(helpers, "DodgeSkills", "Dodge Mob Skills", "Flies 200 studs up while the fought mob casts a skill.")
    Bind.toggle(helpers, "LowHpEscape", "Fly Up When Low HP", "Stays high above the fight until your health is over 80 %.")
    Bind.slider(helpers, "LowHpPercent", "Low HP %", 5, 90, 0)
    Bind.slider(helpers, "LowHpHeight", "Escape Height", 100, 5000, 0)
    Bind.toggle(helpers, "SafeWithItems", "Safe Spot With Fist / Chalice",
        "Waits at the Café (Sea 2) or the Mansion (Sea 3) while holding one, unless a feature on needs it.")

    local combat = tab:AddSection("Combat & Skills")
    Bind.slider(combat, "AttackDelay", "Attack Delay", 0, 0.5, 2,
        "Seconds between two attacks. 0 = every frame.")
    combat:AddParagraph({ Title = "Which skills", Content = "Used by the mastery farm, the sea events, the trees and the trials." })
    Bind.multiDropdown(combat, "SkillsMelee", "Melee Skills", { "Z", "X", "C" })
    Bind.multiDropdown(combat, "SkillsSword", "Sword Skills", { "Z", "X" })
    Bind.multiDropdown(combat, "SkillsGun", "Gun Skills", { "Z", "X" })
    Bind.multiDropdown(combat, "SkillsFruit", "Blox Fruit Skills", { "Z", "X", "C", "V", "F" })
    Bind.slider(combat, "SkillHoldMelee", "Melee Hold Time", 0, 5, 1)
    Bind.slider(combat, "SkillHoldSword", "Sword Hold Time", 0, 5, 1)
    Bind.slider(combat, "SkillHoldGun", "Gun Hold Time", 0, 5, 1)
    Bind.slider(combat, "SkillHoldFruit", "Blox Fruit Hold Time", 0, 5, 1)
    Bind.toggle(combat, "SkillFast", "Use Skills Fast", "Taps the keys instead of holding them.")

    local status = tab:AddSection("Status")
    local panel = status:AddParagraph({ Title = "Status", Content = statusText() })
    Loop.start("StatusPanel", 0.5, function()
        panel:SetDesc(statusText())
    end)

    return tab
end
