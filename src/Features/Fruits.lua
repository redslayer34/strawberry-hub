--=============================================================================
-- FRUITS — gacha roll, storing, fruit sniper, awakening (background loop)
--=============================================================================
--    Random fruit   the Cousin's gacha (v30: Net RF/GachaNetworkRF), once
--                   every 2 h from level 50
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

-- The box to buy: the event banner's when one is on, else the Cousin's
-- own gacha (v30: "ZiolesGacha", seen with a remote spy on a hand spin).
Fruits.GACHA_BOX = "ZiolesGacha"
Fruits.GACHA_REMOTE = "RF/GachaNetworkRF"

local function bannerBox()
    local banner = Services.module("Controllers.BannerClient")
    if type(banner) == "table" and banner.TryGetBannerItemIfActiveAsync then
        local ok, item = pcall(banner.TryGetBannerItemIfActiveAsync)
        if ok and type(item) == "table" and item.BoxName then return item.BoxName end
    end
    return nil
end

-- The time of the last roll is kept per account in the workspace (os.time,
-- survives a rejoin). After a roll nothing is bought for ROLL_COOLDOWN (the
-- Cousin's 2 h; the spin costs Beli and must never be bought in a loop).
-- A refused one is tried again after RETRY_EVERY.
Fruits.ROLL_COOLDOWN = 7200
Fruits.ROLL_EVERY = 10        -- seconds between two looks at the roll
Fruits.RETRY_EVERY = 60       -- seconds after a refused roll
local lastRollAt          -- os.time() of the last roll, or false (unknown)
local serverLeft          -- { seconds, at = os.time() } from CheckTime (old remote)
local lastTry             -- os.clock() of the last refused try
local boxTurn = 0         -- which box is tried (banner, then the Cousin's)

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
    serverLeft, lastTry = nil, nil
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

-- A server answer, short (tables as key=value).
local function describe(value)
    if type(value) ~= "table" then return tostring(value) end
    local parts = {}
    for key, inner in pairs(value) do
        parts[#parts + 1] = tostring(key) .. "=" .. (type(inner) == "table" and "{..}" or tostring(inner))
        if #parts >= 4 then break end
    end
    table.sort(parts)
    return "{" .. table.concat(parts, " ") .. "}"
end

local function fruitCount()
    local count, player = 0, Services.player()
    for _, container in ipairs({ player and player:FindFirstChild("Backpack"), Player.character() }) do
        for _, tool in ipairs(container and container:GetChildren() or {}) do
            if tool:IsA("Tool") and tool.Name:find("Fruit", 1, true) then count = count + 1 end
        end
    end
    return count
end

local function spinnerOpen()
    local player = Services.player()
    local window = player and Services.find(player, "PlayerGui.SpinnerWindow")
    if not window then return false end
    local ok, shown = pcall(function()
        if window:IsA("ScreenGui") then return window.Enabled end
        return window.Visible
    end)
    return ok and shown == true
end

-- An answer that says no by itself.
local function refused(result)
    if result == nil or result == false or type(result) == "string" then return true end
    if type(result) == "number" then return result ~= 1 end
    if type(result) == "table" then
        return result.Success == false or result.success == false or result.Error ~= nil or result.error ~= nil
    end
    return false
end

-- The new gacha (v30): Net RF/GachaNetworkRF { Context = "Purchase",
-- BoxName = box }. A roll is taken as done when the Beli went down, a
-- fruit came in, or the spin window opened; or the answer says so.
local function purchase(remote, box)
    local beli, fruits, spinner = Player.data("Beli") or 0, fruitCount(), spinnerOpen()
    local ok, result = pcall(function()
        return remote:InvokeServer({ Context = "Purchase", BoxName = box })
    end)
    if not ok then result = nil end
    Fruits.answers = { box = box, result = describe(result) }
    for _ = 1, 6 do
        if (Player.data("Beli") or 0) < beli or fruitCount() > fruits or (spinnerOpen() and not spinner) then
            return true
        end
        task.wait(0.5)
    end
    return result == true or result == 1 or (type(result) == "table" and (result.Success == true or result.success == true))
        or (result ~= nil and not refused(result))
end

-- The old Cousin remote (before v30), for a game that still has it.
local function cousin(box)
    local time = Services.invoke("Cousin", "CheckTime", box)
    if type(time) == "number" and time > 0 then serverLeft = { seconds = time, at = os.time() } end
    local result = Services.invoke("Cousin", box)
    Fruits.answers = { box = box, result = describe(result), time = time }
    return result == 1
end

-- Tries a roll when one may be due. Returns true when a fruit was rolled.
function Fruits.roll()
    if (Player.level() or 0) < 50 then
        Fruits.answers = { result = "level < 50" }
        return false
    end
    local last = lastRoll()
    if last and os.time() - last < Fruits.ROLL_COOLDOWN then return false end
    if lastTry and os.clock() - lastTry < Fruits.RETRY_EVERY then return false end
    local banner = bannerBox()
    local boxes = { Fruits.GACHA_BOX }
    if banner and banner ~= "DLCBoxData" and banner ~= Fruits.GACHA_BOX then table.insert(boxes, 1, banner) end
    boxTurn = boxTurn % #boxes + 1
    local box = boxes[boxTurn]
    local remote = Common.net(Fruits.GACHA_REMOTE)
    local done
    if remote then
        done = purchase(remote, box)
    else
        done = cousin(banner or "DLCBoxData")
    end
    if done then
        rolled()
        return true
    end
    lastTry = os.clock()
    return false
end

-- The last answers, short, for the screen: why no spin happens.
function Fruits.rollInfo()
    local a = Fruits.answers
    if not a then return nil end
    local text = "roll " .. tostring(a.result)
    if a.box then text = text .. ", " .. tostring(a.box) end
    if a.time ~= nil then text = text .. ", time " .. tostring(a.time) end
    return text
end

-- Test hook.
function Fruits.resetRoll()
    lastRollAt, serverLeft, lastTry, boxTurn, Fruits.answers = nil, nil, nil, 0, nil
end

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
