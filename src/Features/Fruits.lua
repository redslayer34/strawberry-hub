--=============================================================================
-- FRUITS — gacha roll, storing, fruit sniper, awakening (background loop)
--=============================================================================
--    Random fruit   the Cousin's gacha: rolled when the server says the
--                   player may (level 50, enough money, cooldown over)
--    Store fruit    every fruit tool held goes to the fruit storage (once
--                   per tool), with an optional webhook report by rarity
--    Sniper         buys a wanted fruit when the stock has it on sale and
--                   the current fruit is not already a wanted one
--    Awaken         asks the Awakener to awaken the next move
--=============================================================================

local Common = require("Features.Stack.Common")
local Loop = require("Core.Loop")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local Webhook = require("Features.Webhook")

local Fruits = {}

Fruits.RARITIES = { "Mythical", "Legendary", "Rare", "Uncommon", "Common" }
Fruits.STORE_EVERY = 2   -- seconds between two stores (the reference waits 2 s)

local stored = setmetatable({}, { __mode = "k" })
local kept = {}   -- [storage name] = until (os.clock)

-- Leaves the fruit `storageName` out of the storing for `seconds`: another
-- feature took it out on purpose (Trevor's fruit, a raid chip's payment),
-- and storing it back would undo that every two seconds.
function Fruits.keep(storageName, seconds)
    kept[storageName] = os.clock() + (seconds or 60)
end

local function isKept(name)
    local untilAt = kept[name]
    if not untilAt then return false end
    if os.clock() < untilAt then return true end
    kept[name] = nil
    return false
end

---------------------------------------------------------------------------
-- Random fruit (Cousin)
---------------------------------------------------------------------------

local function bannerBox()
    local banner = Services.module("Controllers.BannerClient")
    if type(banner) == "table" and banner.TryGetBannerItemIfActiveAsync then
        local ok, item = pcall(banner.TryGetBannerItemIfActiveAsync)
        if ok and type(item) == "table" and item.BoxName then return item.BoxName end
    end
    return "DLCBoxData"
end

-- When the next roll is allowed: the Cousin rolls once every ROLL_COOLDOWN.
-- The time of the last roll is kept per account in the workspace (os.time,
-- survives a rejoin); CheckTime answering a number of seconds wins.
Fruits.ROLL_COOLDOWN = 7200
Fruits.ROLL_EVERY = 10        -- seconds between two roll tries
local lastRollAt          -- os.time() of the last roll, or false (unknown)
local serverLeft          -- { seconds, at = os.time() } from CheckTime

local function rollFile()
    local player = Services.player()
    return "StrawberryHub/roll_" .. tostring(player and player.UserId or 0) .. ".txt"
end

local function lastRoll()
    if lastRollAt == nil then
        lastRollAt = false
        pcall(function()
            if isfile and readfile and isfile(rollFile()) then lastRollAt = tonumber(readfile(rollFile())) or false end
        end)
    end
    return lastRollAt or nil
end

local function rolled()
    lastRollAt = os.time()
    serverLeft = nil
    pcall(function()
        if not writefile then return end
        if makefolder and isfolder and not isfolder("StrawberryHub") then makefolder("StrawberryHub") end
        writefile(rollFile(), tostring(lastRollAt))
    end)
end

-- Seconds before the next roll (0: now), or nil when not known yet.
function Fruits.nextRollIn()
    if serverLeft then return math.max(0, serverLeft.seconds - (os.time() - serverLeft.at)) end
    local last = lastRoll()
    if last then return math.max(0, Fruits.ROLL_COOLDOWN - (os.time() - last)) end
    return nil
end

-- Tries a roll. Check / CheckTime only feed the countdown: the roll itself
-- is asked for anyway, as Teddy does (the server refuses one too early or
-- too poor; a gate on their answers kept the roll from ever happening).
-- Returns true when a fruit was rolled.
function Fruits.roll()
    local box = bannerBox()
    local commF = Services.commF()
    if not commF then return false end
    local ok, _, level = pcall(function() return commF:InvokeServer("Cousin", "Check", box) end)
    if not (ok and type(level) == "number") then level = Player.level() end
    if (level or 0) < 50 then return false end
    local time = Services.invoke("Cousin", "CheckTime", box)
    if type(time) == "number" and time > 0 then serverLeft = { seconds = time, at = os.time() } end
    if Services.invoke("Cousin", box) == 1 then
        rolled()
        return true
    end
    return false
end

-- Test hook.
function Fruits.resetRoll() lastRollAt, serverLeft = nil, nil end

-- Closes the spin animation's window (Teddy: the close button, then
-- hidden). Never holds the next roll back.
local function closeSpinner()
    local player = Services.player()
    local window = player and Services.find(player, "PlayerGui.SpinnerWindow")
    if not window then return end
    local close = Services.find(window, "AboveSpinner.Navigation.CloseButton")
    if close and close.Visible then
        local spinner = Services.module("Controllers.UI.Spinner")
        if type(spinner) == "table" and spinner.Close then pcall(spinner.Close, spinner) end
        pcall(function()
            if firesignal and close.Activated then firesignal(close.Activated) end
        end)
        pcall(function() window.Visible = false end)
    end
end

---------------------------------------------------------------------------
-- Store
---------------------------------------------------------------------------

function Fruits.storageName(tool)
    local original = tool:GetAttribute("OriginalName")
    if original then return original end
    local short = tool.Name:gsub(" Fruit$", "")
    return short .. "-" .. short
end

function Fruits.rarity(storageName)
    local info = Services.module("FruitInfo")
    local entry = type(info) == "table" and type(info.List) == "table" and info.List[storageName]
    local rarity = type(entry) == "table" and entry.Rarity
    return type(rarity) == "table" and rarity.Name or nil
end

local function heldFruits()
    local found, player = {}, Services.player()
    for _, container in ipairs({ player and player:FindFirstChild("Backpack"), Player.character() }) do
        for _, tool in ipairs(container and container:GetChildren() or {}) do
            if tool:IsA("Tool") and tool.Name:find("Fruit", 1, true) and not stored[tool]
                and not isKept(Fruits.storageName(tool)) then
                found[#found + 1] = tool
            end
        end
    end
    return found
end

-- Stores the next fruit held. Returns the tool stored, or nil.
function Fruits.storeNext()
    local tool = heldFruits()[1]
    if not tool then return nil end
    stored[tool] = true
    local name = Fruits.storageName(tool)
    Services.invoke("StoreFruit", name, tool)
    if Settings.get("WebhookStoreFruit") then
        local wanted = Settings.get("WebhookFruitRarities") or {}
        local rarity = Fruits.rarity(name)
        if rarity and wanted[rarity] then Webhook.send("Store Fruit", tool.Name .. " (" .. rarity .. ")") end
    end
    return tool
end

---------------------------------------------------------------------------
-- Sniper
---------------------------------------------------------------------------

function Fruits.stockNames()
    local list = Common.invoke("GetFruits", false)
    local names = {}
    for _, fruit in ipairs(type(list) == "table" and list or {}) do
        if type(fruit) == "table" and fruit.Name then names[#names + 1] = fruit.Name end
    end
    table.sort(names)
    return names
end

-- The wanted fruit on sale, or nil.
function Fruits.snipeTarget()
    local wanted = Settings.get("FruitSniperList") or {}
    if next(wanted) == nil or wanted[Player.data("DevilFruit") or ""] then return nil end
    local list = Common.invoke("GetFruits", false)
    for _, fruit in ipairs(type(list) == "table" and list or {}) do
        if type(fruit) == "table" and wanted[fruit.Name] and fruit.OnSale then return fruit.Name end
    end
    return nil
end

---------------------------------------------------------------------------

function Fruits.step()
    if Settings.get("FruitRandom") then
        closeSpinner()
        if Common.every("FruitRoll", Fruits.ROLL_EVERY) then Fruits.roll() end
    end
    if Settings.get("FruitStore") and Common.every("FruitStore", Fruits.STORE_EVERY) then
        Fruits.storeNext()
    end
    if Settings.get("FruitSniper") and Common.every("FruitSnipe", 5) then
        local target = Fruits.snipeTarget()
        if target then
            Services.invoke("PurchaseRawFruit", target)
            Common.forget()
        end
    end
    if Settings.get("FruitAwaken") and Common.every("FruitAwaken", 5) then
        Services.invoke("Awakener", "Check")
        Services.invoke("Awakener", "Awaken")
    end
end

function Fruits.start()
    Loop.start("Fruits", 0.5, Fruits.step)
end

-- Test hook.
function Fruits.reset()
    stored = setmetatable({}, { __mode = "k" })
    kept = {}
end

return Fruits
