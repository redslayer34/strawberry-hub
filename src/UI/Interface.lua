--=============================================================================
-- INTERFACE — the Fluent window, its tabs, and settings persistence
--=============================================================================
--  Built in the order Fluent's own example uses: window, addons wired to the
--  library, tabs, SelectTab(1), notification, then the autoload config.
--
--  Each tab builds inside its own pcall: a broken tab is reported and
--  skipped, and every other tab still appears.
--=============================================================================

local MobileButton = require("UI.MobileButton")
local Settings = require("Core.Settings")
local TouchSlider = require("UI.TouchSlider")

local Interface = {}

Interface.FOLDER = "StrawberryHub"
Interface.CONFIG_FOLDER = "StrawberryHub/BloxFruits"
Interface.AUTOSAVE = "autosave"
Interface.SAVE_DELAY = 1

Interface.TABS = {
    { name = "Farm", build = require("UI.Tabs.Farm") },
    { name = "Stack", build = require("UI.Tabs.Stack") },
    { name = "Farm Other", build = require("UI.Tabs.Other") },
    { name = "Fruit & Raid", build = require("UI.Tabs.Raid") },
    { name = "Items", build = require("UI.Tabs.Items") },
    { name = "Teleport", build = require("UI.Tabs.Teleport") },
    { name = "Shop", build = require("UI.Tabs.Shop") },
    { name = "Player", build = require("UI.Tabs.Player") },
    { name = "PVP", build = require("UI.Tabs.Pvp") },
    { name = "ESP", build = require("UI.Tabs.Esp") },
    { name = "Server", build = require("UI.Tabs.Server") },
    { name = "Webhook", build = require("UI.Tabs.Webhook") },
    { name = "Settings", build = require("UI.Tabs.Settings") },
}

-- Controls whose value must not come back on the next run.
Interface.TRANSIENT = { "JoinJobId" }

local state = {}

-- Every setting change is written to the "autosave" config one second later
-- (changes in between are grouped into one write). The first write also
-- makes it the autoload config, unless the player already chose another.
--
-- Saving only starts once the autoload config has been applied: loading
-- fires every element's callback, and saving then would be pointless at
-- best, and on a slow load could write the defaults over the saved values.
local function startAutosave(saveManager)
    local enabled, pending = false, false
    local autoloadFile = saveManager.Folder .. "/settings/autoload.txt"

    local function save()
        pending = false
        if state.closed then return end
        local ok = pcall(function() saveManager:Save(Interface.AUTOSAVE) end)
        if ok and isfile and writefile and not isfile(autoloadFile) then
            pcall(writefile, autoloadFile, Interface.AUTOSAVE)
        end
    end

    state.stopAutosave = Settings.onChanged(function()
        if not enabled or pending then return end
        pending = true
        task.delay(Interface.SAVE_DELAY, save)
    end)

    local ok, err = pcall(function() saveManager:LoadAutoloadConfig() end)
    if not ok then warn("[Strawberry Hub] autoload failed: " .. tostring(err)) end

    task.delay(Interface.SAVE_DELAY, function() enabled = true end)
end

-- Builds everything. `unload` is what the Unload button calls. Returns the
-- window and the names of the tabs that failed to build.
function Interface.build(library, saveManager, interfaceManager, options)
    options = options or {}
    state = {}

    local window = library:CreateWindow({
        Title = "Strawberry Hub",
        SubTitle = "v" .. tostring(options.version or "?"),
        TabWidth = 160,
        Size = UDim2.fromOffset(580, 460),
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.LeftControl,
    })
    if not window then error("Fluent refused to create the window", 0) end

    if saveManager then
        saveManager:SetLibrary(library)
        saveManager:IgnoreThemeSettings()
        saveManager:SetIgnoreIndexes(Interface.TRANSIENT)
        saveManager:SetFolder(Interface.CONFIG_FOLDER)
    end
    if interfaceManager then
        interfaceManager:SetLibrary(library)
        interfaceManager:SetFolder(Interface.FOLDER)
    end

    local ui = {
        Library = library,
        Window = window,
        SaveManager = saveManager,
        InterfaceManager = interfaceManager,
        unload = options.unload or function() end,
    }

    local failed = {}
    for _, tab in ipairs(Interface.TABS) do
        local ok, err = pcall(tab.build, window, ui)
        if not ok then
            failed[#failed + 1] = tab.name
            warn("[Strawberry Hub] tab " .. tab.name .. " failed: " .. tostring(err))
        end
    end

    window:SelectTab(1)

    local okButton, button = pcall(MobileButton.create, window)
    if okButton then state.mobileButton = button end

    if #failed > 0 then
        library:Notify({
            Title = "Strawberry Hub",
            Content = "Some tabs failed to load: " .. table.concat(failed, ", "),
            SubContent = "Check the console (F9)",
            Duration = 10,
        })
    else
        library:Notify({
            Title = "Strawberry Hub",
            Content = "Loaded. LeftControl shows / hides the window.",
            Duration = 6,
        })
    end

    if saveManager then startAutosave(saveManager) end

    return window, failed
end

function Interface.destroy()
    state.closed = true
    TouchSlider.destroy()
    if state.stopAutosave then state.stopAutosave() end
    if state.mobileButton then pcall(function() state.mobileButton:Destroy() end) end
    state = { closed = true }
end

return Interface
