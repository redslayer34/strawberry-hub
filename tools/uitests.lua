--=============================================================================
-- UI TESTS — the Fluent interface, built against a fake Fluent
--=============================================================================
--  The fake (tools/fakefluent.lua) reproduces the real library's asserts,
--  so a control missing a required field fails here instead of silently
--  hiding every tab after it in game.
--=============================================================================

local passed, failed = 0, 0
local failures = {}

local function check(name, condition, detail)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = name .. (detail ~= nil and ("  -- " .. tostring(detail)) or "")
    end
end

local function eq(name, actual, expected)
    check(name, actual == expected,
        string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

-- In-memory file system for SaveManager / autosave.
local FILES = {}
isfile = function(path) return FILES[path] ~= nil end
writefile = function(path, content) FILES[path] = content end
readfile = function(path) return FILES[path] end

local modules = { "UI.Fluent", "UI.Bind", "UI.MobileButton", "UI.Interface", "UI.Tabs.Farm", "UI.Tabs.Settings" }
for _, name in ipairs(modules) do
    local ok, err = pcall(require, name)
    check("loads " .. name, ok, err)
end

local Bind = require("UI.Bind")
local FluentLoader = require("UI.Fluent")
local Interface = require("UI.Interface")
local Loop = require("Core.Loop")
local MobileButton = require("UI.MobileButton")
local Settings = require("Core.Settings")

-- A player with just enough for the status panel.
local players = game:GetService("Players")
local player = newInstance("Player", "Tester", players)
players.LocalPlayer = player
local data = newInstance("Folder", "Data", player)
local level = newInstance("IntValue", "Level", data)
level.Value = 1234

local function reset()
    Loop.stopAll()
    clearTasks()
    Settings.reset()
    WARNINGS = {}
    FILES = {}
end

---------------------------------------------------------------------------
-- Loader
---------------------------------------------------------------------------

reset()
do
    local originalFetch = FluentLoader.fetch
    local library, saveManager, interfaceManager = newFakeFluent()
    local byUrl = {
        [FluentLoader.URLS.library] = library,
        [FluentLoader.URLS.saveManager] = saveManager,
        [FluentLoader.URLS.interfaceManager] = interfaceManager,
    }
    FluentLoader.fetch = function(url) return byUrl[url] end

    local a, b, c = FluentLoader.load()
    eq("library returned", a, library)
    eq("SaveManager returned", b, saveManager)
    eq("InterfaceManager returned", c, interfaceManager)

    check("README release URL", FluentLoader.URLS.library
        == "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua")

    FluentLoader.fetch = function(url)
        if url == FluentLoader.URLS.library then return library end
        error("404")
    end
    local _, missingSave, missingInterface = FluentLoader.load()
    check("missing addons are nil", missingSave == nil and missingInterface == nil)
    eq("missing addons warn", #WARNINGS, 2)

    FluentLoader.fetch = function() error("offline") end
    check("missing library is an error", not pcall(FluentLoader.load))

    FluentLoader.fetch = originalFetch
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

reset()
local library, saveManager, interfaceManager, record = newFakeFluent()
record.savedConfig = { AutoFarmLevel = true, BringCount = "4" }
local unloaded = false

local okBuild, window, failedTabs = pcall(Interface.build, library, saveManager, interfaceManager, {
    version = "test",
    unload = function() unloaded = true end,
})
check("interface builds", okBuild, window)
eq("no tab failed", failedTabs and #failedTabs, 0)
eq("callbacks never errored", record.callbackErrors, nil)

local config = record.windowConfig or {}
eq("window title", config.Title, "Strawberry Hub")
eq("window width", config.Size and config.Size.X.Offset, 580)
eq("window height", config.Size and config.Size.Y.Offset, 460)
eq("tab width", config.TabWidth, 160)
eq("acrylic off by default", config.Acrylic, false)
eq("minimize key", config.MinimizeKey and config.MinimizeKey.Name, "LeftControl")

local titles = {}
for _, tab in ipairs(record.tabs) do titles[#titles + 1] = tab.Title end
eq("tabs in order", table.concat(titles, ","), "Farm,Stack,Farm Other,Fruit & Raid,Items,Races,Teleport,Shop,Player,PVP,ESP,Server,Webhook,Settings")
eq("first tab selected", record.selectedTab, 1)

for key in pairs(Settings.DEFAULTS) do
    check("setting has a control: " .. key, library.Options[key] ~= nil)
end
eq("no duplicate Idx", #record.duplicates, 0)

eq("SaveManager folder", saveManager.Folder, "StrawberryHub/BloxFruits")
eq("InterfaceManager folder", interfaceManager.Folder, "StrawberryHub")
check("theme settings not saved in configs", saveManager.Ignore.InterfaceTheme == true)
check("config section built", library.Options.SaveManager_ConfigName ~= nil)
check("interface section built", library.Options.InterfaceTheme ~= nil)

eq("autoload config applied once", record.autoloadCalls, 1)
eq("saved toggle restored", Settings.get("AutoFarmLevel"), true)
eq("saved slider string restored as a number", Settings.get("BringCount"), 4)

local last = record.notifications[#record.notifications]
check("loaded notification", last and last.Content:find("Loaded") ~= nil, last and last.Content)

---------------------------------------------------------------------------
-- Controls write the settings
---------------------------------------------------------------------------

local Options = library.Options
Options.AutoFarmLevel:SetValue(false)
eq("toggle writes its setting", Settings.get("AutoFarmLevel"), false)

Options.Weapon:SetValue("Sword")
eq("dropdown writes its setting", Settings.get("Weapon"), "Sword")

-- Fluent's Round gives "0" (a string) for 0 with Rounding 2.
Options.AttackDelay:SetValue(0)
eq("rounded slider stays a number", type(Settings.get("AttackDelay")), "number")
Options.AttackDelay:SetValue(0.25)
eq("rounded slider value", Settings.get("AttackDelay"), 0.25)

Options.TweenSpeed:SetValue(9999)
eq("slider clamped to its max", Settings.get("TweenSpeed"), 350)

Options.MasterySkills:SetValue({ Z = true, C = true, X = false })
local skills = Settings.get("MasterySkills")
check("multi-dropdown writes a set", skills.Z and skills.C and not skills.X and not skills.V)
eq("multi-dropdown keeps only the chosen skills", (function()
    local n = 0
    for _ in pairs(library.Options.MasterySkills.Value) do n = n + 1 end
    return n
end)(), 2)

Options.StackEliteHunter:SetValue(true)
eq("stack toggle writes its setting", Settings.get("StackEliteHunter"), true)
Options.StackEliteHunter:SetValue(false)

Options.Material:SetValue("Vampire Fang")
eq("material dropdown writes its setting", Settings.get("Material"), "Vampire Fang")
check("mob list refresh button", record.buttons["Refresh mob list"] ~= nil)
record.buttons["Refresh mob list"]:Click()
eq("refresh does not error", record.callbackErrors, nil)

-- Shop and teleport buttons.
do
    local rs = game:GetService("ReplicatedStorage")
    local remotes = rs:FindFirstChild("Remotes") or newInstance("Folder", "Remotes", rs)
    local commF = remotes:FindFirstChild("CommF_") or newInstance("RemoteFunction", "CommF_", remotes)
    commF.OnInvoke = function() return "ok" end
    commF.Invoked = nil

    record.buttons["Buso Haki"]:Click()
    local call = commF.Invoked and commF.Invoked[1]
    check("Buso Haki buys through CommF_", call and call[1] == "BuyHaki" and call[2] == "Buso")
    local note = record.notifications[#record.notifications]
    eq("purchase result shown", note and note.SubContent, "ok")

    local before = #commF.Invoked
    record.buttons["Reroll race"]:Click()
    eq("reroll waits for confirmation", #commF.Invoked, before)
    local dialog = record.dialogs[#record.dialogs]
    dialog.Buttons[1].Callback()
    local reroll = commF.Invoked[#commF.Invoked]
    check("confirmed reroll", reroll[1] == "BlackbeardReward" and reroll[2] == "Reroll")

    local Travel = require("Features.Travel")
    Options.FightingStyle:SetValue("Godhuman")
    record.buttons["Buy fighting style"]:Click()
    eq("fighting style travels to its teacher", Travel.pending() and Travel.pending().label, "Ancient Monk")
    Travel.cancel()

    Options.Team:SetValue("Marines")
    record.buttons["Switch team"]:Click()
    local team = commF.Invoked[#commF.Invoked]
    check("switch team", team[1] == "SetTeam" and team[2] == "Marines")

    check("JobId input not saved", saveManager.Ignore.JoinJobId == true)
    check("server panel", record.paragraphs.Server ~= nil)
end

---------------------------------------------------------------------------
-- Autosave
---------------------------------------------------------------------------

eq("nothing saved while the autoload runs", #record.saves, 0)
stepTasks()   -- autosave switches on
Options.BringMob:SetValue(false)
Options.FarmHeight:SetValue(15)
eq("save is deferred", #record.saves, 0)
stepTasks()
eq("changes grouped into one save", #record.saves, 1)
local save = record.saves[1] or { values = {} }
eq("autosave config name", save.name, "autosave")
eq("autosave holds the new value", save.values.BringMob, false)
eq("autosave becomes the autoload config",
    FILES["StrawberryHub/BloxFruits/settings/autoload.txt"], "autosave")

FILES["StrawberryHub/BloxFruits/settings/autoload.txt"] = "mine"
Options.BringMob:SetValue(true)
stepTasks()
eq("a chosen autoload config is kept", FILES["StrawberryHub/BloxFruits/settings/autoload.txt"], "mine")

---------------------------------------------------------------------------
-- Status panel and Unload
---------------------------------------------------------------------------

stepTasks()
local status = record.paragraphs.Status
check("status panel refreshed", status and tostring(status.Description):find("Level 1234") ~= nil,
    status and status.Description)

record.buttons.Unload:Click()
local dialog = record.dialogs[#record.dialogs]
check("unload asks first", dialog ~= nil and not unloaded)
eq("dialog has two buttons", dialog and #dialog.Buttons, 2)
if dialog then dialog.Buttons[1].Callback() end
check("confirm unloads", unloaded)

Interface.destroy()
Options.BringMob:SetValue(false)
stepTasks()
stepTasks()
local savesAfterDestroy = #record.saves
Options.BringMob:SetValue(true)
stepTasks()
eq("no autosave after destroy", #record.saves, savesAfterDestroy)

---------------------------------------------------------------------------
-- A broken tab does not take the others down
---------------------------------------------------------------------------

reset()
do
    local brokenLibrary, brokenSave, brokenInterface, brokenRecord = newFakeFluent()
    table.insert(Interface.TABS, 1, {
        name = "Broken",
        build = function(win)
            local tab = win:AddTab({ Title = "Broken", Icon = "" })
            -- The exact mistake that hid every tab after the first one.
            tab:AddSlider("Oops", { Title = "No bounds", Default = 1 })
        end,
    })
    local ok, _, failedList = pcall(Interface.build, brokenLibrary, brokenSave, brokenInterface, {})
    table.remove(Interface.TABS, 1)

    check("build survives a broken tab", ok, failedList)
    eq("broken tab reported", failedList and failedList[1], "Broken")
    local names = {}
    for _, tab in ipairs(brokenRecord.tabs) do names[#names + 1] = tab.Title end
    eq("other tabs still built", table.concat(names, ","), "Broken,Farm,Stack,Farm Other,Fruit & Raid,Items,Races,Teleport,Shop,Player,PVP,ESP,Server,Webhook,Settings")
    local note = brokenRecord.notifications[#brokenRecord.notifications]
    check("player told which tab failed", note and note.Content:find("Broken") ~= nil)
    check("failure logged", #WARNINGS > 0)
    Interface.destroy()
end

---------------------------------------------------------------------------
-- Bind always passes Fluent's required fields
---------------------------------------------------------------------------

reset()
do
    local lib, _, _, rec = newFakeFluent()
    local win = lib:CreateWindow({ Title = "t", Size = UDim2.fromOffset(1, 1) })
    local tab = win:AddTab({ Title = "t" })
    local ok = pcall(Bind.slider, tab, "FarmHeight", "Height", 5, 25)
    check("slider without rounding gets a default", ok)
    eq("slider registered", lib.Options.FarmHeight ~= nil, true)
    eq("no callback error", rec.callbackErrors, nil)

    check("window without size is caught by the fake",
        not pcall(newFakeFluent().CreateWindow, newFakeFluent(), { Title = "x" }))
end

---------------------------------------------------------------------------
-- Touch slider
---------------------------------------------------------------------------

reset()
do
    local TouchSlider = require("UI.TouchSlider")

    -- The instance shape Fluent builds for a slider.
    local section = { Container = newInstance("Frame", "Container") }
    local element = newInstance("TextButton", "Element", section.Container)
    local inner = newInstance("Frame", "SliderInner", element)
    newInstance("UISizeConstraint", "UISizeConstraint", inner)
    local rail = newInstance("Frame", "SliderRail", inner)
    rail.AbsolutePosition = Vector2.new(100, 0)
    rail.AbsoluteSize = Vector2.new(200, 4)
    local dot = newInstance("ImageLabel", "SliderDot", rail)

    local values = {}
    local slider = { Min = 0, Max = 20 }
    function slider:SetValue(v) values[#values + 1] = v end

    check("touch area added", TouchSlider.enhance(section, slider))
    local area = inner:FindFirstChild("StrawberryTouch")
    check("touch area is a button", area and area.ClassName == "TextButton")
    eq("touch area is tall", area and area.Size.Y.Offset, 36)
    eq("dot enlarged", dot.Size.X.Offset, 22)

    local touch = Enum.UserInputType.Touch
    area.InputBegan:Fire({ UserInputType = touch, Position = Vector2.new(250, 0) })
    eq("tap at 75 % sets 75 % of the range", values[1], 15)
    local uis = game:GetService("UserInputService")
    uis.InputChanged:Fire({ UserInputType = touch, Position = Vector2.new(400, 0) })
    eq("dragging past the end clamps to max", values[2], 20)
    uis.InputEnded:Fire({ UserInputType = touch, Position = Vector2.new(400, 0) })
    uis.InputChanged:Fire({ UserInputType = touch, Position = Vector2.new(100, 0) })
    eq("no update after release", #values, 2)

    check("an enhanced slider is not enhanced twice", not TouchSlider.enhance(section, slider))
    check("unknown layout leaves the slider stock",
        not TouchSlider.enhance({ Container = newInstance("Frame", "Empty") }, slider))
    TouchSlider.destroy()
    uis.InputChanged:Fire({ UserInputType = touch, Position = Vector2.new(150, 0) })
    eq("destroy drops the connections", #values, 2)
end

---------------------------------------------------------------------------
-- Mobile button
---------------------------------------------------------------------------

reset()
do
    local lib, _, _, rec = newFakeFluent()
    local win = lib:CreateWindow({ Title = "t", Size = UDim2.fromOffset(1, 1) })

    eq("no button without touch", MobileButton.create(win), nil)

    local gui = MobileButton.create(win, true)
    check("button created", gui ~= nil)
    eq("button parented to CoreGui", gui and gui.Parent, game:GetService("CoreGui"))
    local button = gui and gui.Toggle

    button.Activated:Fire()
    eq("tap toggles the window", rec.minimized, 1)

    local touch = Enum.UserInputType.Touch
    button.InputBegan:Fire({ UserInputType = touch, Position = Vector2.new(0, 0) })
    button.InputChanged:Fire({ UserInputType = touch, Position = Vector2.new(30, 10) })
    button.InputEnded:Fire({ UserInputType = touch, Position = Vector2.new(30, 10) })
    button.Activated:Fire()
    eq("a drag is not a tap", rec.minimized, 1)
    eq("drag moves the button", button.Position.X.Offset, 46)
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------

Loop.stopAll()
clearTasks()

print(string.format("ui: %d passed, %d failed", passed, failed))
for _, failure in ipairs(failures) do print("  FAIL " .. failure) end
if failed > 0 then os.exit(1) end
