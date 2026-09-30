--=============================================================================
-- STRAWBERRY DETECTOR — standalone Blox Fruits scanner
--=============================================================================
--  The in-game detection of Strawberry Hub (its webhook profile and server
--  scout), as one script with no dependency:
--    Player    name, level, sea, race and its version (V1-V4), devil fruit
--              (mastery, awakened moves), melees owned, beli, fragments
--    Inventory fruits worth DETECTOR.FruitMinValue+, items of rarity
--              DETECTOR.ItemMinRarity+ (Legendary = 3, Mythical = 4)
--    Server    players, JobId, time of day, moon (full / near full)
--    Islands   Mirage, Kitsune, Prehistoric, Frozen Dimension (Leviathan)
--    Bosses    rare bosses, Elite Hunter, Castle raid (pirates at the castle)
--    World     fruits on the ground, rare berry bushes, the Colors Dealer's
--              legendary haki and the dealer's legendary sword (both only
--              checked: "1" asks, nothing is bought)
--
--  Usage: set the options below (or getgenv().DETECTOR before running) and
--  execute. The report is printed (F9 console) and shown as a notification;
--  with a webhook URL it is also posted there. Detector.scan() returns the
--  whole result as a table for your own scripts.
--=============================================================================

local env = (getgenv and getgenv()) or _G
local defaults = {
    WebhookUrl = "",          -- your own Discord webhook, empty = none
    Loop = false,             -- keep scanning; new events posted once per server
    Every = 30,               -- seconds between scans when Loop is on
    Print = true,             -- report in the F9 console
    Notify = true,            -- short in-game notification
    FruitMinValue = 1000000,  -- fruits listed from this value
    ItemMinRarity = 3,        -- items listed from this rarity
}
local CONFIG = env.DETECTOR or {}
for key, value in pairs(defaults) do
    if CONFIG[key] == nil then CONFIG[key] = value end
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local player = Players.LocalPlayer

local Detector = {}

Detector.SEAS = {
    [2753915549] = 1, [85211729168715] = 1,
    [4442272183] = 2, [79091703265657] = 2,
    [7449423635] = 3, [100117331123089] = 3,
}
Detector.MELEES = {
    "Death Step", "Sharkman Karate", "Electric Claw", "Dragon Talon",
    "Superhuman", "Godhuman", "Sanguine Art",
}
Detector.RARE_BOSSES = {
    "rip_indra True Form", "Dough King", "Cake Prince", "Soul Reaper", "Cursed Captain",
    "Tyrant of the Skies", "Darkbeard", "Order",
}
Detector.ELITES = { "Deandre", "Urban", "Diablo" }
Detector.HAKI = { ["Winter Sky"] = true, ["Pure Red"] = true, ["Snow White"] = true }
Detector.SWORDS = { Saishi = true, Oroshi = true, Shizu = true }
Detector.BERRIES = { ["Red Cherry Berry"] = true, ["White Cloud Berry"] = true, ["Pink Pig Berry"] = true }
Detector.MOON_FULL = "http://www.roblox.com/asset/?id=9709149431"
Detector.MOON_NEXT = "http://www.roblox.com/asset/?id=9709149052"
Detector.CASTLE = Vector3.new(-5000, 350, -3035)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function find(root, path)
    local node = root
    for part in path:gmatch("[^%.]+") do
        if not node then return nil end
        node = node:FindFirstChild(part)
    end
    return node
end

local function invoke(...)
    local remote = find(ReplicatedStorage, "Remotes.CommF_")
    if not remote then return nil end
    local ok, result = pcall(remote.InvokeServer, remote, ...)
    if ok then return result end
    return nil
end

local function data(name)
    local folder = player and player:FindFirstChild("Data")
    local value = folder and folder:FindFirstChild(name)
    return value and value.Value
end

local function tool(name)
    local character = player and player.Character
    local backpack = player and player:FindFirstChild("Backpack")
    return (character and character:FindFirstChild(name)) or (backpack and backpack:FindFirstChild(name))
end

local function alive(model)
    if not model or not model.Parent then return false end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0 and model:FindFirstChild("HumanoidRootPart") ~= nil
end

-- A mob alive in workspace.Enemies, or parked in ReplicatedStorage (the
-- game keeps far bosses there).
local function mob(name)
    local enemies = workspace:FindFirstChild("Enemies")
    local found = enemies and enemies:FindFirstChild(name)
    if alive(found) then return found end
    found = ReplicatedStorage:FindFirstChild(name)
    if alive(found) then return found end
    return nil
end

local function map(name)
    local root = workspace:FindFirstChild("Map")
    return root and root:FindFirstChild(name)
end

-- "Snow White 2500000" -> "Snow White".
local function dealerName(answer)
    if answer == nil then return nil end
    local text = tostring(answer):gsub("%d+", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function number(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

---------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------

function Detector.sea()
    local known = Detector.SEAS[game.PlaceId]
    if known then return known end
    local ok, attribute = pcall(function() return workspace:GetAttribute("MAP") end)
    return ok and tonumber(tostring(attribute or ""):match("(%d)")) or nil
end

function Detector.raceVersion()
    local character = player and player.Character
    if character and character:FindFirstChild("RaceTransformed") then return "V4" end
    if invoke("Wenlocktoad", "1") == -2 then return "V3" end
    if invoke("Alchemist", "1") == -2 then return "V2" end
    return "V1"
end

function Detector.fruit()
    local fruit = data("DevilFruit")
    if not fruit or fruit == "" then return { name = "None" } end
    local short = tostring(fruit):match("^[^%-]+") or tostring(fruit)
    local held = tool(short .. " Fruit") or tool(tostring(fruit))
    local level = held and held:FindFirstChild("Level")
    local awakened = {}
    if invoke("AwakeningChanger", "Check") then
        local abilities = invoke("getAwakenedAbilities")
        for key, ability in pairs(type(abilities) == "table" and abilities or {}) do
            if type(ability) == "table" and ability.Awakened then awakened[#awakened + 1] = tostring(key) end
        end
    end
    table.sort(awakened)
    return { name = short, mastery = level and tonumber(level.Value) or nil, awakened = awakened }
end

-- BuySharkmanKarate(true) answers 1 when the style is owned.
function Detector.melees()
    local owned = {}
    for _, style in ipairs(Detector.MELEES) do
        if invoke("Buy" .. style:gsub(" ", ""), true) == 1 then owned[#owned + 1] = style end
    end
    return owned
end

function Detector.player()
    return {
        name = player and player.Name or "?",
        level = data("Level") or 0,
        sea = Detector.sea(),
        race = data("Race") or "?",
        raceVersion = Detector.raceVersion(),
        fruit = Detector.fruit(),
        melees = Detector.melees(),
        beli = data("Beli") or 0,
        fragments = data("Fragments") or 0,
    }
end

---------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------

function Detector.inventory()
    local fruits, items = {}, {}
    local list = invoke("getInventory")
    for _, item in ipairs(type(list) == "table" and list or {}) do
        if type(item) == "table" and item.Name then
            local name = tostring(item.Name):match("^[^%-]+") or tostring(item.Name)
            local value, rarity = tonumber(item.Value), tonumber(item.Rarity)
            if item.Type == "Blox Fruit" then
                if not value or value >= CONFIG.FruitMinValue then fruits[#fruits + 1] = name end
            elseif rarity and rarity >= CONFIG.ItemMinRarity then
                items[#items + 1] = name
            end
        end
    end
    table.sort(fruits)
    table.sort(items)
    return { fruits = fruits, items = items }
end

---------------------------------------------------------------------------
-- Server, islands, bosses, world
---------------------------------------------------------------------------

-- "Full Moon", "Near Full Moon" or "Normal": the MoonPhase attribute
-- first (5 = full, 4 = the night before), the sky's moon texture otherwise.
function Detector.moon()
    local phase = tonumber(Lighting:GetAttribute("MoonPhase"))
    if phase == 5 then return "Full Moon" end
    if phase == 4 then return "Near Full Moon" end
    if phase then return "Normal" end
    local sky = Lighting:FindFirstChild("Sky") or Lighting:FindFirstChild("FantasySky")
    if Detector.sea() == 2 then sky = Lighting:FindFirstChild("FantasySky") or sky end
    local texture = sky and sky.MoonTextureId
    if texture == Detector.MOON_FULL then return "Full Moon" end
    if texture == Detector.MOON_NEXT then return "Near Full Moon" end
    return "Normal"
end

function Detector.server()
    local time = Lighting.ClockTime or 0
    return {
        players = #Players:GetPlayers() .. "/" .. tostring(Players.MaxPlayers),
        jobId = tostring(game.JobId),
        placeId = game.PlaceId,
        time = string.format("%02d:%02d", math.floor(time), math.floor((time % 1) * 60)),
        moon = Detector.moon(),
    }
end

function Detector.islands()
    local locations = find(workspace, "_WorldOrigin.Locations")
    return {
        mirage = map("MysticIsland") ~= nil,
        kitsune = map("KitsuneIsland") ~= nil,
        prehistoric = map("PrehistoricIsland") ~= nil,
        frozenDimension = locations ~= nil and locations:FindFirstChild("Frozen Dimension") ~= nil,
    }
end

-- Pirates under level 1500 around the Castle on the Sea (Sea 3).
function Detector.castleRaid()
    if Detector.sea() ~= 3 then return false end
    for _, place in ipairs({ workspace:FindFirstChild("Enemies"), ReplicatedStorage }) do
        for _, model in ipairs(place and place:GetChildren() or {}) do
            local level = model:GetAttribute("Level")
            if model:IsA("Model") and level and level <= 1500 then
                local ok, pivot = pcall(function() return model:GetPivot() end)
                if ok and pivot and (pivot.Position - Detector.CASTLE).Magnitude <= 1000 then return true end
            end
        end
    end
    return false
end

function Detector.bosses()
    local rare, elite = {}, nil
    for _, name in ipairs(Detector.RARE_BOSSES) do
        if mob(name) then rare[#rare + 1] = name end
    end
    for _, name in ipairs(Detector.ELITES) do
        if mob(name) then elite = name break end
    end
    return { rare = rare, elite = elite, castleRaid = Detector.castleRaid() }
end

function Detector.world()
    local fruits = {}
    for _, child in ipairs(workspace:GetChildren()) do
        if child.Name ~= "Fruit" and child.Name:find("Fruit", 1, true) and (child:IsA("Tool") or child:IsA("Model")) then
            fruits[#fruits + 1] = child.Name
        end
    end
    local berries = {}
    local ok, bushes = pcall(function() return CollectionService:GetTagged("BerryBush") end)
    for _, bush in ipairs(ok and bushes or {}) do
        for _, value in pairs(bush:GetAttributes()) do
            if Detector.BERRIES[value] then berries[#berries + 1] = value end
        end
    end
    local haki = dealerName(invoke("ColorsDealer", "1", true))
    local sword = dealerName(invoke("LegendarySwordDealer", "1"))
    return {
        fruits = fruits,
        berries = berries,
        legendaryHaki = haki and Detector.HAKI[haki] and haki or nil,
        legendarySword = sword and Detector.SWORDS[sword] and sword or nil,
    }
end

-- Everything at once.
function Detector.scan()
    return {
        player = Detector.player(),
        inventory = Detector.inventory(),
        server = Detector.server(),
        islands = Detector.islands(),
        bosses = Detector.bosses(),
        world = Detector.world(),
    }
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------

local function list(items)
    return #items > 0 and table.concat(items, ", ") or "none"
end

local function yes(value) return value and "yes" or "no" end

function Detector.report(result)
    result = result or Detector.scan()
    local p, s, i, b, w = result.player, result.server, result.islands, result.bosses, result.world
    local fruit = p.fruit.name
    if p.fruit.mastery then fruit = fruit .. " [" .. p.fruit.mastery .. "]" end
    if p.fruit.awakened and #p.fruit.awakened > 0 then fruit = fruit .. " awakened " .. table.concat(p.fruit.awakened, " ") end
    return table.concat({
        "== Player ==",
        string.format("%s | level %s | sea %s", p.name, tostring(p.level), tostring(p.sea or "?")),
        string.format("Race: %s %s", tostring(p.race), p.raceVersion),
        "Fruit: " .. fruit,
        "Melees: " .. list(p.melees),
        string.format("Beli: %s | Fragments: %s", number(p.beli), number(p.fragments)),
        "== Inventory ==",
        "Fruits: " .. list(result.inventory.fruits),
        "Rare items: " .. list(result.inventory.items),
        "== Server ==",
        string.format("Players %s | time %s | moon: %s", s.players, s.time, s.moon),
        "JobId: " .. s.jobId,
        "== Islands ==",
        string.format("Mirage: %s | Kitsune: %s | Prehistoric: %s | Frozen Dimension: %s",
            yes(i.mirage), yes(i.kitsune), yes(i.prehistoric), yes(i.frozenDimension)),
        "== Bosses ==",
        "Rare bosses: " .. list(b.rare),
        "Elite Hunter: " .. tostring(b.elite or "none"),
        "Castle raid: " .. yes(b.castleRaid),
        "== World ==",
        "Fruits on the ground: " .. list(w.fruits),
        "Rare berries: " .. list(w.berries),
        "Legendary haki at the dealer: " .. tostring(w.legendaryHaki or "no"),
        "Legendary sword at the dealer: " .. tostring(w.legendarySword or "no"),
    }, "\n")
end

-- The events worth joining this server for, as { "Mirage Island", ... }.
function Detector.events(result)
    local events = {}
    local function add(text) events[#events + 1] = text end
    for _, name in ipairs(result.bosses.rare) do add("Rare boss: " .. name) end
    if result.bosses.elite then add("Elite Hunter: " .. result.bosses.elite) end
    if result.bosses.castleRaid then add("Castle raid") end
    if result.islands.mirage then add("Mirage Island") end
    if result.islands.kitsune then add("Kitsune Island") end
    if result.islands.prehistoric then add("Prehistoric Island") end
    if result.islands.frozenDimension then add("Frozen Dimension") end
    if result.server.moon ~= "Normal" then add(result.server.moon) end
    for _, name in ipairs(result.world.fruits) do add("Fruit spawned: " .. name) end
    for _, name in ipairs(result.world.berries) do add("Rare berry: " .. name) end
    if result.world.legendaryHaki then add("Legendary haki: " .. result.world.legendaryHaki) end
    if result.world.legendarySword then add("Legendary sword: " .. result.world.legendarySword) end
    return events
end

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------

local function httpRequest()
    return (syn and syn.request) or request or http_request or (http and http.request) or (fluxus and fluxus.request)
end

-- Posts `text` to the webhook URL of the options. Returns true when sent.
function Detector.post(title, text)
    local url, send = tostring(CONFIG.WebhookUrl or ""), httpRequest()
    if url == "" or not send then return false end
    local join = string.format("game:GetService('TeleportService'):TeleportToPlaceInstance(%s, '%s', "
        .. "game.Players.LocalPlayer)", tostring(game.PlaceId), tostring(game.JobId))
    local body = HttpService:JSONEncode({
        username = "Strawberry Detector",
        embeds = { {
            title = title,
            description = "```\n" .. text:sub(1, 3800) .. "\n```",
            color = 16733525,
            fields = { { name = "Join", value = "```lua\n" .. join .. "\n```" } },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        } },
    })
    return pcall(send, { Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
end

local function notify(text)
    if not CONFIG.Notify then return end
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Strawberry Detector", Text = text, Duration = 8 })
    end)
end

-- One scan: printed, notified, posted.
function Detector.run()
    local result = Detector.scan()
    local text = Detector.report(result)
    if CONFIG.Print then print("\n" .. text) end
    local events = Detector.events(result)
    notify(#events > 0 and table.concat(events, ", ") or "Scan done (F9 for the report)")
    Detector.post("Scan of " .. (player and player.Name or "?"), text)
    return result
end

-- Loop mode: every CONFIG.Every seconds, each new event posted once per server.
function Detector.loop()
    local sent = {}
    while env.DETECTOR_RUNNING do
        local ok, result = pcall(Detector.scan)
        if ok then
            for _, event in ipairs(Detector.events(result)) do
                local key = tostring(game.JobId) .. "|" .. event
                if not sent[key] then
                    sent[key] = true
                    notify(event)
                    if CONFIG.Print then print("[Strawberry Detector] " .. event) end
                    Detector.post(event, Detector.report(result))
                end
            end
        end
        task.wait(CONFIG.Every)
    end
end

env.StrawberryDetector = Detector
Detector.run()
if CONFIG.Loop then
    env.DETECTOR_RUNNING = true
    task.spawn(Detector.loop)
end
return Detector
