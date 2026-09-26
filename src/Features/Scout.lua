--=============================================================================
-- SERVER SCOUT — reports what is worth joining this server for
--=============================================================================
--  Every CHECK_EVERY seconds, when "Server scout" is on and a webhook URL is
--  typed in the Webhook tab, each event found is sent once per server to
--  that URL, with the JobId and a line to paste to join. The events are the
--  ones of a public notifier script (only its idea is used; nothing is sent
--  anywhere but the user's own webhook):
--    Rare Bosses      rip_indra True Form, Dough King, Cake Prince, Soul
--                     Reaper, Cursed Captain, Tyrant of the Skies
--    Elite Hunter     Diablo, Urban, Deandre
--    Fruit Spawn      a fruit lying in workspace
--    Legendary Haki   the Colors Dealer's colour (ColorsDealer 1: a check,
--                     buying is 2) when it is Winter Sky, Pure Red or Snow White
--    Legendary Sword  the dealer's sword (LegendarySwordDealer 1, a check)
--    Rare Berry       a Red Cherry, White Cloud or Pink Pig berry bush
--    Full Moon        MoonPhase 5, or 4 (the night before)
--    Castle Raid      enemies under level 1500 around the Castle on the Sea
--=============================================================================

local Data = require("Game.Data")
local Enemies = require("Game.Enemies")
local Loop = require("Core.Loop")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local Webhook = require("Features.Webhook")
local World = require("Game.World")

local Scout = {}

Scout.CHECK_EVERY = 30
Scout.EVENTS = {
    "Rare Bosses", "Elite Hunter", "Fruit Spawn", "Legendary Haki", "Legendary Sword",
    "Rare Berry", "Full Moon", "Castle Raid",
}
Scout.RARE_BOSSES = {
    "rip_indra True Form", "Dough King", "Cake Prince", "Soul Reaper", "Cursed Captain", "Tyrant of the Skies",
}
Scout.HAKI = { ["Winter Sky"] = true, ["Pure Red"] = true, ["Snow White"] = true }
Scout.SWORDS = { Saishi = true, Oroshi = true, Shizu = true }
Scout.BERRIES = { ["Red Cherry Berry"] = true, ["White Cloud Berry"] = true, ["Pink Pig Berry"] = true }
Scout.CASTLE = Vector3.new(-5000, 350, -3035)
Scout.CASTLE_RADIUS = 1000
Scout.RAID_MAX_LEVEL = 1500

local sent = {}   -- [JobId .. event .. detail] = true

local function wanted(event)
    local events = Settings.get("WebhookScoutEvents")
    return type(events) ~= "table" or events[event] == true
end

-- A dealer's answer without its price: "Snow White 2500000" -> "Snow White".
local function dealerName(answer)
    if answer == nil then return nil end
    local text = tostring(answer):gsub("%d+", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

function Scout.fruit()
    for _, child in ipairs(workspace:GetChildren()) do
        if child.Name ~= "Fruit" and child.Name:find("Fruit", 1, true) and (child:IsA("Tool") or child:IsA("Model")) then
            return child.Name
        end
    end
    return nil
end

function Scout.berry()
    local ok, bushes = pcall(function() return Services.get("CollectionService"):GetTagged("BerryBush") end)
    for _, bush in ipairs(ok and bushes or {}) do
        for _, value in pairs(bush:GetAttributes()) do
            if Scout.BERRIES[value] then return value end
        end
    end
    return nil
end

function Scout.castleRaid()
    if Player.sea() ~= 3 then return false end
    for _, place in ipairs({ workspace:FindFirstChild("Enemies"), Services.replicated() }) do
        for _, model in ipairs(place and place:GetChildren() or {}) do
            local level = model:GetAttribute("Level")
            if model:IsA("Model") and level and level <= Scout.RAID_MAX_LEVEL then
                local ok, pivot = pcall(function() return model:GetPivot() end)
                if ok and pivot and (pivot.Position - Scout.CASTLE).Magnitude <= Scout.CASTLE_RADIUS then
                    return true
                end
            end
        end
    end
    return false
end

-- Every event found now, as { { event, detail } }.
function Scout.findings()
    local found = {}
    local function add(event, detail) found[#found + 1] = { event = event, detail = detail } end
    if wanted("Rare Bosses") then
        for _, name in ipairs(Scout.RARE_BOSSES) do
            if Enemies.findBoss({ name }) then add("Rare Bosses", name) end
        end
    end
    if wanted("Elite Hunter") then
        local elite = Enemies.findBoss(Data.ELITE_HUNTERS)
        if elite then add("Elite Hunter", elite.Name) end
    end
    if wanted("Fruit Spawn") then
        local fruit = Scout.fruit()
        if fruit then add("Fruit Spawn", fruit) end
    end
    if wanted("Legendary Haki") then
        local colour = dealerName(Services.invoke("ColorsDealer", "1", true))
        if colour and Scout.HAKI[colour] then add("Legendary Haki", colour) end
    end
    if wanted("Legendary Sword") then
        local sword = dealerName(Services.invoke("LegendarySwordDealer", "1"))
        if sword and Scout.SWORDS[sword] then add("Legendary Sword", sword) end
    end
    if wanted("Rare Berry") then
        local berry = Scout.berry()
        if berry then add("Rare Berry", berry) end
    end
    if wanted("Full Moon") then
        local moon = World.moon()
        if moon == "Full Moon" then add("Full Moon", "Full Moon") end
        if moon == "Next Night" then add("Full Moon", "Near Full Moon") end
    end
    if wanted("Castle Raid") and Scout.castleRaid() then add("Castle Raid", "Pirates at the Castle on the Sea") end
    return found
end

-- One check: each new event sent once for this server. Returns how many
-- were sent.
function Scout.step()
    if not Settings.get("WebhookScout") or not Webhook.url() then return 0 end
    local count = 0
    for _, item in ipairs(Scout.findings()) do
        local key = tostring(game.JobId) .. "|" .. item.event .. "|" .. tostring(item.detail)
        if not sent[key] then
            sent[key] = true
            count = count + 1
            task.spawn(function() pcall(Webhook.sendServer, item.event, item.detail) end)
        end
    end
    return count
end

function Scout.start()
    Loop.start("ServerScout", Scout.CHECK_EVERY, Scout.step)
end

-- Test hook.
function Scout.reset()
    sent = {}
end

return Scout
