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
--
--  Local panel (PanelUrl): every PanelEvery seconds the scan is POSTed as
--  JSON { username, userId, player, inventory, server, islands, bosses,
--  world, events, time }. The heavy parts are cached (player + inventory
--  PlayerEvery, dealers DealerEvery). 429 = wait longer, 404 = the account
--  is unknown to the panel: sending stops for this session.
--=============================================================================

local env = (getgenv and getgenv()) or _G
local defaults = {
    WebhookUrl = "",          -- your own Discord webhook, empty = none
    Loop = false,             -- keep scanning; new events posted once per server
    Every = 30,               -- seconds between scans when Loop is on
    Print = true,             -- report in the F9 console
    Notify = true,            -- short in-game notification
    FruitMinValue = 0,        -- stored fruits listed from this price (0 = all)
    Avatar = true,            -- your Roblox headshot in the webhook
    PanelUrl = "",            -- URL de ton panel local, ex. "http://10.0.2.2:8000/api/scan" (vide = désactivé)
    PanelEvery = 30,          -- secondes entre deux envois au panel
    PlayerEvery = 300,        -- secondes entre deux relectures du joueur + inventaire (lourd : ~15 appels au jeu)
    DealerEvery = 120,        -- secondes entre deux questions aux marchands (Haki / épée légendaires)
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
--  The old getInventory call now often answers nothing, so every source
--  still around is read and merged by name:
--    getInventory          name, type, value, rarity (older servers)
--    getInventoryWeapons   swords and guns with their rarity (Teddy Hub)
--    getInventoryFruits    the stored fruits
--    ItemReplicationService + ItemConfig   the game's own item list (Banana)

Detector.RARITY = { common = 0, uncommon = 1, rare = 2, legendary = 3, mythical = 4 }
Detector.RARITY_NAMES = { [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Legendary", [4] = "Mythical" }
-- The game's rarity colours: grey, blue, purple, pink, red.
Detector.RARITY_ICONS = { [0] = "⚪", [1] = "🔵", [2] = "🟣", [3] = "💗", [4] = "🔴" }

-- Devil fruits: rarity and dealer price, for stored fruits whose source
-- gives neither (a fruit missing here is listed under "Other").
local function fruitData(rarity, names)
    local out = {}
    for name, price in pairs(names) do out[name] = { rarity = rarity, price = price } end
    return out
end
Detector.FRUITS = {}
for _, group in ipairs({
    fruitData(0, { Rocket = 5000, Spin = 7500, Blade = 30000, Spring = 60000, Bomb = 80000, Smoke = 100000,
        Spike = 180000 }),
    fruitData(1, { Flame = 250000, Ice = 350000, Sand = 420000, Dark = 500000, Eagle = 550000, Diamond = 600000 }),
    fruitData(2, { Light = 650000, Rubber = 750000, Ghost = 940000, Magma = 960000 }),
    fruitData(3, { Quake = 1000000, Buddha = 1200000, Love = 1300000, Creation = 1400000, Spider = 1500000,
        Sound = 1700000, Phoenix = 1800000, Portal = 1900000, Lightning = 2100000, Pain = 2300000,
        Blizzard = 2400000 }),
    fruitData(4, { Gravity = 2500000, Mammoth = 2700000, ["T-Rex"] = 2700000, Dough = 2800000, Shadow = 2900000,
        Venom = 3000000, Control = 3200000, Gas = 3200000, Spirit = 3400000, Tiger = 5000000, Leopard = 5000000,
        Yeti = 5000000, Kitsune = 8000000, Dragon = 15000000 }),
}) do
    for name, info in pairs(group) do Detector.FRUITS[name] = info end
end

-- "Kitsune-Kitsune" -> "Kitsune", "T-Rex-T-Rex" -> "T-Rex".
local function baseName(name)
    name = tostring(name)
    return name:match("^(.-)%-%1$") or name
end

local function rarityOf(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) or Detector.RARITY[value:lower()] end
    if type(value) == "table" then
        return rarityOf(value.Name) or rarityOf(value.Value) or rarityOf(value.Order) or rarityOf(value.Index)
    end
    return nil
end

local function module(name)
    local node = ReplicatedStorage:FindFirstChild(name)
    if not node then return nil end
    local ok, result = pcall(require, node)
    return ok and result or nil
end

local function itemService()
    local list = {}
    pcall(function()
        local service, config = module("ItemReplicationService"), module("ItemConfig")
        if type(service) ~= "table" or type(config) ~= "table" then return end
        for _, item in ipairs(service:GetItems(service.KEYS.QUANTITY)) do
            if item.Value and item.Value > 0 then
                local found, info = pcall(function() return config.match(item.ItemId):unwrap() end)
                if found and type(info) == "table" and info.Display then
                    local kind = info.Display.Category
                    local key = info.Index and info.Index.StorageKey
                    list[#list + 1] = {
                        Name = kind == "Blox Fruit" and (key or info.Display.Name) or (info.Display.Name or key),
                        Type = kind,
                        Rarity = info.Rarity or info.Display.Rarity,
                        Count = item.Value,
                    }
                end
            end
        end
    end)
    return list
end

function Detector.inventory()
    local merged, order, sources = {}, {}, {}
    local function add(source, entries, forcedType)
        local used = false
        for _, item in ipairs(type(entries) == "table" and entries or {}) do
            if type(item) == "table" and item.Name then
                used = true
                local name = baseName(item.Name)
                local entry = merged[name]
                if not entry then
                    entry = { name = name }
                    merged[name] = entry
                    order[#order + 1] = name
                end
                entry.type = entry.type or forcedType or item.Type
                local value = tonumber(item.Value or item.Price)
                if value and value > (entry.value or -1) then entry.value = value end
                local rarity = rarityOf(item.Rarity)
                if rarity and rarity > (entry.rarity or -1) then entry.rarity = rarity end
            end
        end
        if used then sources[#sources + 1] = source end
    end
    add("getInventory", invoke("getInventory"))
    add("getInventoryWeapons", invoke("getInventoryWeapons"))
    add("getInventoryFruits", invoke("getInventoryFruits"), "Blox Fruit")
    add("item service", itemService())

    local fruits, items = {}, {}
    for _, name in ipairs(order) do
        local entry = merged[name]
        if entry.type == "Blox Fruit" then
            local known = Detector.FRUITS[name]
            if known then
                entry.rarity = entry.rarity or known.rarity
                entry.value = entry.value or known.price
            end
            if not entry.value or entry.value >= CONFIG.FruitMinValue then fruits[#fruits + 1] = entry end
        elseif entry.rarity and entry.rarity >= CONFIG.ItemMinRarity then
            items[#items + 1] = entry
        end
    end
    local function byRarity(a, b)
        if (a.rarity or 0) ~= (b.rarity or 0) then return (a.rarity or 0) > (b.rarity or 0) end
        if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
        return a.name < b.name
    end
    table.sort(fruits, byRarity)
    table.sort(items, byRarity)
    return { fruits = fruits, items = items, sources = sources }
end

-- "Cursed Dual Katana (Mythical)".
function Detector.itemLabel(entry)
    local rarity = entry.rarity and Detector.RARITY_NAMES[entry.rarity]
    return rarity and (entry.name .. " (" .. rarity .. ")") or entry.name
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

function Detector.world(dealers)
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
    dealers = dealers or Detector.dealers()
    return {
        fruits = fruits,
        berries = berries,
        legendaryHaki = dealers.legendaryHaki,
        legendarySword = dealers.legendarySword,
    }
end

-- The Colors Dealer's and the sword dealer's legendary stock ("1" only
-- asks, nothing is bought).
function Detector.dealers()
    local haki = dealerName(invoke("ColorsDealer", "1", true))
    local sword = dealerName(invoke("LegendarySwordDealer", "1"))
    return {
        legendaryHaki = haki and Detector.HAKI[haki] and haki or nil,
        legendarySword = sword and Detector.SWORDS[sword] and sword or nil,
    }
end

local cache = {}

-- Everything at once (and the cache refreshed).
function Detector.scan()
    local now = os.clock()
    cache.player, cache.inventory, cache.playerAt = Detector.player(), Detector.inventory(), now
    cache.dealers, cache.dealersAt = Detector.dealers(), now
    return {
        player = cache.player,
        inventory = cache.inventory,
        server = Detector.server(),
        islands = Detector.islands(),
        bosses = Detector.bosses(),
        world = Detector.world(cache.dealers),
    }
end

-- The same, with the heavy parts reused: player and inventory for
-- PlayerEvery seconds, the dealers for DealerEvery seconds. For the loops.
function Detector.scanCached()
    local now = os.clock()
    if not cache.playerAt or now - cache.playerAt >= CONFIG.PlayerEvery then
        cache.player, cache.inventory, cache.playerAt = Detector.player(), Detector.inventory(), now
    end
    if not cache.dealersAt or now - cache.dealersAt >= CONFIG.DealerEvery then
        cache.dealers, cache.dealersAt = Detector.dealers(), now
    end
    return {
        player = cache.player,
        inventory = cache.inventory,
        server = Detector.server(),
        islands = Detector.islands(),
        bosses = Detector.bosses(),
        world = Detector.world(cache.dealers),
    }
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------

local function list(items)
    return #items > 0 and table.concat(items, ", ") or "none"
end

local function yes(value) return value and "yes" or "no" end

local function labels(entries)
    local out = {}
    for _, entry in ipairs(entries) do out[#out + 1] = Detector.itemLabel(entry) end
    return out
end

-- Entries grouped by rarity, rarest first: { { rarity, names = {...} } }.
function Detector.groups(entries)
    local byRarity, order = {}, {}
    for _, entry in ipairs(entries) do
        local key = entry.rarity or -1
        if not byRarity[key] then
            byRarity[key] = { rarity = entry.rarity, names = {} }
            order[#order + 1] = key
        end
        table.insert(byRarity[key].names, entry.name)
    end
    table.sort(order, function(a, b) return a > b end)
    local out = {}
    for _, key in ipairs(order) do
        table.sort(byRarity[key].names)
        out[#out + 1] = byRarity[key]
    end
    return out
end

-- "🔴 **Mythical** (8)\nA · B · C" paragraphs, one per rarity.
local function groupedText(entries, bold)
    local parts = {}
    for _, group in ipairs(Detector.groups(entries)) do
        local rarity = group.rarity and Detector.RARITY_NAMES[group.rarity] or "Other"
        local icon = group.rarity and Detector.RARITY_ICONS[group.rarity] or "❔"
        local title = bold and ("**" .. rarity .. "**") or rarity
        parts[#parts + 1] = string.format("%s %s (%d)\n%s", icon, title, #group.names, table.concat(group.names, " · "))
    end
    return parts
end

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
        "Stored fruits (" .. #result.inventory.fruits .. "):",
        #result.inventory.fruits > 0 and table.concat(groupedText(result.inventory.fruits), "\n") or "none",
        "Rare items (" .. #result.inventory.items .. "):",
        #result.inventory.items > 0 and table.concat(groupedText(result.inventory.items), "\n") or "none",
        "(read from: " .. list(result.inventory.sources) .. ")",
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

Detector.COLOUR = 15087942   -- strawberry red
Detector.EVENT_COLOUR = 3066993  -- green: something worth joining for

local function clip(text, size)
    text = tostring(text)
    if #text > size then text = text:sub(1, size - 3) .. "..." end
    return text
end

local function lines(items, empty)
    if #items == 0 then return empty or "—" end
    return clip(table.concat(items, "\n"), 1000)
end

local function mark(on, name)
    return (on and "✅ " or "❌ ") .. name
end

-- Fields for a long grouped list: paragraphs packed into fields of at
-- most 1024 characters, the first named `title`, the next "… (more)".
local function listFields(title, entries, empty)
    local fields = {}
    local parts = groupedText(entries, true)
    if #parts == 0 then return { { name = title, value = empty, inline = false } } end
    local current = ""
    local function flush()
        if current == "" then return end
        fields[#fields + 1] = { name = #fields == 0 and title or (title .. " (more)"), value = current, inline = false }
        current = ""
    end
    for _, part in ipairs(parts) do
        part = clip(part, 1000)
        if #current + #part + 2 > 1000 then flush() end
        current = current == "" and part or (current .. "\n\n" .. part)
    end
    flush()
    return fields
end

-- The player's headshot, from Roblox's thumbnail API (nil when it fails).
function Detector.avatarUrl()
    if not CONFIG.Avatar or not player then return nil end
    local send = httpRequest()
    if not send then return nil end
    local ok, url = pcall(function()
        local answer = send({ Method = "GET", Url = "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds="
            .. tostring(player.UserId) .. "&size=150x150&format=Png&isCircular=false" })
        local decoded = HttpService:JSONDecode(answer.Body)
        return decoded.data[1].imageUrl
    end)
    return ok and type(url) == "string" and url or nil
end

-- The Discord embed of a scan: the player on top, short facts in three
-- columns, long lists (inventory) full width grouped by rarity, the join
-- line last.
function Detector.embed(result, title, colour)
    local p, s, i, b, w = result.player, result.server, result.islands, result.bosses, result.world
    local fruit = "🍎 **" .. tostring(p.fruit.name) .. "**"
    if p.fruit.mastery then fruit = fruit .. " · mastery " .. p.fruit.mastery end
    if p.fruit.awakened and #p.fruit.awakened > 0 then
        fruit = fruit .. " · awakened " .. table.concat(p.fruit.awakened, " ")
    end
    local description = table.concat({
        string.format("⭐ Level **%s** · 🌊 Sea **%s** · 🧬 **%s %s**", tostring(p.level), tostring(p.sea or "?"),
            tostring(p.race), p.raceVersion),
        fruit,
        string.format("💰 **%s** Beli · 🔷 **%s** Fragments", number(p.beli), number(p.fragments)),
    }, "\n")

    local melees
    if #p.melees == #Detector.MELEES then
        melees = "✅ **All " .. #p.melees .. "**"
    else
        local missing, owned = {}, {}
        for _, style in ipairs(p.melees) do owned[style] = true end
        for _, style in ipairs(Detector.MELEES) do
            if not owned[style] then missing[#missing + 1] = style end
        end
        melees = "**" .. #p.melees .. "/" .. #Detector.MELEES .. "**\nMissing: " .. table.concat(missing, ", ")
    end

    local hunt = {}
    for _, name in ipairs(b.rare) do hunt[#hunt + 1] = "👹 " .. name end
    hunt[#hunt + 1] = "🎯 Elite: " .. (b.elite and ("**" .. b.elite .. "**") or "none")
    hunt[#hunt + 1] = mark(b.castleRaid, "Castle raid")

    local world = {
        "🌈 Haki: " .. (w.legendaryHaki and ("**" .. w.legendaryHaki .. "**") or "none"),
        "🗡️ Sword: " .. (w.legendarySword and ("**" .. w.legendarySword .. "**") or "none"),
        "🍏 On the ground: " .. (#w.fruits > 0 and table.concat(w.fruits, ", ") or "none"),
        "🍒 Rare berries: " .. (#w.berries > 0 and table.concat(w.berries, ", ") or "none"),
    }

    local moon = s.moon == "Normal" and "🌑 Normal moon" or ("🌕 **" .. s.moon .. "**")
    local events = Detector.events(result)
    local join = string.format("game:GetService('TeleportService'):TeleportToPlaceInstance(%s, '%s', "
        .. "game.Players.LocalPlayer)", tostring(s.placeId), s.jobId)

    local fields = {
        { name = "🥋 Melees", value = melees, inline = true },
        { name = "🌐 Server", value = "👥 " .. s.players .. " players\n🕑 " .. s.time .. "\n" .. moon, inline = true },
        { name = "🔔 Events", value = #events > 0 and clip(table.concat(events, "\n"), 1000) or "Nothing special",
            inline = true },
        { name = "🏝️ Islands", value = table.concat({ mark(i.mirage, "Mirage"), mark(i.kitsune, "Kitsune"),
            mark(i.prehistoric, "Prehistoric"), mark(i.frozenDimension, "Frozen Dimension") }, "\n"), inline = true },
        { name = "🎯 Bosses", value = lines(hunt), inline = true },
        { name = "🌍 Dealers & world", value = lines(world), inline = true },
    }
    for _, field in ipairs(listFields("⚔️ Rare items · " .. #result.inventory.items, result.inventory.items,
        "None of rarity " .. tostring(Detector.RARITY_NAMES[CONFIG.ItemMinRarity] or CONFIG.ItemMinRarity) .. "+")) do
        fields[#fields + 1] = field
    end
    for _, field in ipairs(listFields("🎒 Stored fruits · " .. #result.inventory.fruits, result.inventory.fruits,
        "No stored fruit")) do
        fields[#fields + 1] = field
    end
    fields[#fields + 1] = { name = "🔗 Join this server", value = "```lua\n" .. join .. "\n```", inline = false }

    local avatar = Detector.avatarUrl()
    return {
        author = { name = "🍓 Strawberry Detector" },
        title = title,
        description = description,
        color = colour or Detector.COLOUR,
        thumbnail = avatar and { url = avatar } or nil,
        fields = fields,
        footer = { text = "Strawberry Detector" },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
end

-- Posts a scan to the webhook URL of the options. Returns true when sent.
function Detector.post(result, title, colour)
    local url, send = tostring(CONFIG.WebhookUrl or ""), httpRequest()
    if url == "" or not send then return false end
    local body = HttpService:JSONEncode({
        username = "Strawberry Detector",
        embeds = { Detector.embed(result, title, colour) },
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
    Detector.post(result, player and player.Name or "?", #events > 0 and Detector.EVENT_COLOUR or nil)
    return result
end

-- Each run of the script gets its own session: the loops of an older run
-- stop as soon as a newer one starts (or DETECTOR_RUNNING is set to false).
local session = {}
env.DETECTOR_SESSION = session
local function running()
    return env.DETECTOR_SESSION == session and env.DETECTOR_RUNNING ~= false
end

-- Loop mode: every CONFIG.Every seconds, each new event posted once per server.
function Detector.loop()
    local sent = {}
    while running() do
        local ok, result = pcall(Detector.scanCached)
        if ok then
            for _, event in ipairs(Detector.events(result)) do
                local key = tostring(game.JobId) .. "|" .. event
                if not sent[key] then
                    sent[key] = true
                    notify(event)
                    if CONFIG.Print then print("[Strawberry Detector] " .. event) end
                    pcall(Detector.post, result, "🔔 " .. event, Detector.EVENT_COLOUR)
                end
            end
        end
        task.wait(CONFIG.Every)
    end
end

---------------------------------------------------------------------------
-- Local panel
---------------------------------------------------------------------------

Detector.PANEL_MAX_WAIT = 300   -- seconds: the longest wait after 429s

-- POSTs a scan to CONFIG.PanelUrl. Returns the HTTP status (or nil).
function Detector.postPanel(result)
    local url, send = tostring(CONFIG.PanelUrl or ""), httpRequest()
    if url == "" or not send then return nil end
    local ok, response = pcall(function()
        local body = HttpService:JSONEncode({
            username = player and player.Name or "?",
            userId = player and player.UserId or 0,
            player = result.player,
            inventory = result.inventory,
            server = result.server,
            islands = result.islands,
            bosses = result.bosses,
            world = result.world,
            events = Detector.events(result),
            time = os.time(),
        })
        return send({ Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
    end)
    if not ok or type(response) ~= "table" then return nil end
    return tonumber(response.StatusCode)
end

-- Every PanelEvery seconds: a cached scan to the panel. 429 doubles the
-- wait (up to PANEL_MAX_WAIT), a success brings it back; 404 stops. The
-- console gets one line at the first success and one at the first failure
-- (an unreachable 10.0.2.2 would otherwise go unnoticed), nothing more.
function Detector.panelLoop()
    local wait = CONFIG.PanelEvery
    local saidOk, saidFailed = false, false
    while running() do
        local ok, result = pcall(Detector.scanCached)
        if ok then
            local status = Detector.postPanel(result)
            if status == 404 then
                print("[Strawberry Detector] panel: account " .. tostring(player and player.Name)
                    .. " unknown to the panel (404), sending stopped")
                return
            elseif status == 429 then
                wait = math.min(wait * 2, Detector.PANEL_MAX_WAIT)
            elseif status and status >= 200 and status < 300 then
                wait = CONFIG.PanelEvery
                if not saidOk then
                    saidOk = true
                    print("[Strawberry Detector] panel OK (" .. tostring(CONFIG.PanelUrl) .. ")")
                end
            elseif not saidFailed then
                saidFailed = true
                print(string.format("[Strawberry Detector] panel unreachable (%s, %s), retrying silently",
                    tostring(CONFIG.PanelUrl), status and ("HTTP " .. status) or "no answer"))
            end
        end
        task.wait(wait)
    end
end

env.StrawberryDetector = Detector
pcall(Detector.run)
if CONFIG.Loop then
    env.DETECTOR_RUNNING = true
    task.spawn(Detector.loop)
end
if tostring(CONFIG.PanelUrl or "") ~= "" then
    task.spawn(Detector.panelLoop)
end
return Detector
