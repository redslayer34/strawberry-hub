--=============================================================================
-- WEBHOOK — Discord notifications
--=============================================================================
--  Posts an embed to the Discord webhook URL typed in the Webhook tab:
--    Webhook.send(event, detail)  one event (used by the features that
--                                 report something, and the Test button)
--    profile                      every PROFILE_EVERY seconds when on: level,
--                                 race and version, fruit, melees owned,
--                                 valuable fruits and rare items in stock
--  The ping (<@id> or @everyone) is added when "Ping" is on.
--=============================================================================

local Common = require("Features.Stack.Common")
local Loop = require("Core.Loop")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Webhook = {}

Webhook.NAME = "Strawberry Hub"
Webhook.COLOUR = 16733525
Webhook.PROFILE_EVERY = 300
Webhook.FRUIT_MIN_VALUE = 1000000
Webhook.ITEM_MIN_RARITY = 3
Webhook.MAX_FIELD = 1000
Webhook.MELEES = {
    "Death Step", "Sharkman Karate", "Electric Claw", "Dragon Talon",
    "Superhuman", "Godhuman", "Sanguine Art",
}

local lastProfile

local function httpRequest()
    return (syn and syn.request) or request or http_request or (http and http.request)
        or (fluxus and fluxus.request)
end

function Webhook.url()
    local url = tostring(Settings.get("WebhookUrl") or "")
    return url ~= "" and url or nil
end

function Webhook.ping()
    if not Settings.get("WebhookPing") then return "" end
    local id = tostring(Settings.get("WebhookPingId") or "")
    if tonumber(id) then return "<@" .. id .. ">" end
    return "@everyone"
end

local function clip(text)
    text = tostring(text)
    if #text > Webhook.MAX_FIELD then text = text:sub(1, Webhook.MAX_FIELD - 3) .. "..." end
    return text
end

local function block(text)
    return "```\n" .. clip(text ~= "" and text or "None") .. "\n```"
end

-- Builds and posts one message. Returns true when it was sent.
function Webhook.post(description, fields)
    local url, send = Webhook.url(), httpRequest()
    if not url or not send then return false end
    local player = Services.player()
    local body = {
        content = Webhook.ping(),
        username = Webhook.NAME,
        embeds = { {
            title = Webhook.NAME,
            description = description,
            color = Webhook.COLOUR,
            fields = fields,
            footer = { text = "User: " .. (player and player.Name or "?") },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        } },
    }
    local ok = pcall(function()
        send({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = Services.get("HttpService"):JSONEncode(body),
        })
    end)
    return ok
end

function Webhook.send(event, detail)
    local player = Services.player()
    return Webhook.post("**" .. tostring(event) .. "**", {
        { name = "Event", value = "`" .. tostring(event) .. "`", inline = true },
        { name = "Detail", value = "`" .. tostring(detail) .. "`", inline = true },
        { name = "Username", value = "||" .. (player and player.Name or "?") .. "||", inline = true },
        { name = "PlaceId", value = "`" .. tostring(game.PlaceId) .. "`", inline = true },
        { name = "JobId", value = "`" .. tostring(game.JobId) .. "`", inline = true },
    })
end

-- Sends `event` when the toggle `key` is on, without holding up the caller
-- (the farm loop). Returns true when a message was queued.
function Webhook.notify(key, event, detail)
    if not Settings.get(key) or not Webhook.url() then return false end
    task.spawn(function() pcall(Webhook.send, event, detail) end)
    return true
end

---------------------------------------------------------------------------
-- Profile
---------------------------------------------------------------------------

function Webhook.raceVersion()
    local character = Player.character()
    if character and character:FindFirstChild("RaceTransformed") then return "V4" end
    if Services.invoke("Wenlocktoad", "1") == -2 then return "V3" end
    if Services.invoke("Alchemist", "1") == -2 then return "V2" end
    return "V1"
end

local function fruitText()
    local fruit = Player.data("DevilFruit")
    if not fruit or fruit == "" then return "None" end
    local short = tostring(fruit):match("^[^%-]+") or tostring(fruit)
    local tool = Common.tool(short .. " Fruit") or Common.tool(tostring(fruit))
    local level = tool and tool:FindFirstChild("Level")
    local awakened = {}
    if Services.invoke("AwakeningChanger", "Check") then
        local abilities = Services.invoke("getAwakenedAbilities")
        if type(abilities) == "table" then
            for key, ability in pairs(abilities) do
                if type(ability) == "table" and ability.Awakened then awakened[#awakened + 1] = tostring(key) end
            end
        end
    end
    table.sort(awakened)
    local text = short .. " [" .. tostring(level and level.Value or 0)
    if #awakened > 0 then text = text .. " " .. table.concat(awakened, " ") end
    return text .. "]"
end

function Webhook.melees()
    local owned = {}
    for _, style in ipairs(Webhook.MELEES) do
        if Services.invoke("Buy" .. style:gsub(" ", ""), true) == 1 then owned[#owned + 1] = style end
    end
    return owned
end

local function stock()
    local fruits, items = {}, {}
    local list = Services.invoke("getInventory")
    for _, item in ipairs(type(list) == "table" and list or {}) do
        if type(item) == "table" and item.Name then
            local name = tostring(item.Name):match("^[^%-]+") or tostring(item.Name)
            local value, rarity = tonumber(item.Value), tonumber(item.Rarity)
            if item.Type == "Blox Fruit" and (not value or value >= Webhook.FRUIT_MIN_VALUE) then
                fruits[#fruits + 1] = name
            elseif item.Type ~= "Blox Fruit" and rarity and rarity >= Webhook.ITEM_MIN_RARITY then
                items[#items + 1] = name
            end
        end
    end
    return fruits, items
end

function Webhook.profileText()
    local player = Services.player()
    return string.format("Username: %s\nLevel: %s\nRace: %s [%s]\nFruit: %s",
        player and player.Name or "?", tostring(Player.level()), tostring(Player.data("Race") or "?"),
        Webhook.raceVersion(), fruitText())
end

function Webhook.profile()
    local fruits, items = stock()
    return Webhook.post(block(Webhook.profileText()), {
        { name = "Melee", value = block(table.concat(Webhook.melees(), ",\n")), inline = true },
        { name = "Inventory fruits", value = block(table.concat(fruits, ",\n")), inline = true },
        { name = "Inventory", value = block(table.concat(items, ",\n")), inline = false },
    })
end

local function step()
    if not Settings.get("WebhookProfile") then return end
    local now = os.clock()
    if lastProfile and now - lastProfile < Webhook.PROFILE_EVERY then return end
    lastProfile = now
    Webhook.profile()
end

function Webhook.start()
    Loop.start("WebhookProfile", 5, step)
end

-- Test hook.
function Webhook.reset()
    lastProfile = nil
end

return Webhook
