--=============================================================================
-- STACK: RIP INDRA SUMMON — the Boat Castle haki pads, then God's Chalice
--=============================================================================
--  Rip Indra is summoned at the Castle on the Sea: every pad of the
--  summoner's circle must be lit (lime green) by standing on it with the
--  haki colour it asks for, then God's Chalice is brought to the summoner.
--  Pad colour -> haki colour, from the reference:
--
--    Hot pink -> Winter Sky    Really red -> Pure Red    Oyster -> Snow White
--
--  The colours must be unlocked (bought from the Barista); the ones still
--  locked are shown in the Stack tab.
--=============================================================================

local Common = require("Features.Stack.Common")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Summons = { name = "Rip Indra summon" }

Summons.CASTLE = Vector3.new(-5500, 314, -2855)
Summons.PAD_COLOURS = {
    ["Hot pink"] = "Winter Sky",
    ["Really red"] = "Pure Red",
    ["Oyster"] = "Snow White",
}
Summons.HAKI_COLOURS = { "Winter Sky", "Pure Red", "Snow White" }
Summons.STAND_TIME = 2     -- seconds on a pad
Summons.RECHECK = 300      -- seconds before checking finished pads again

local padsDoneAt, pad, padSince

local function summoner()
    return Services.find(workspace, "Map.Boat Castle.Summoner")
end

local function loaded()
    local root = summoner()
    local circle = root and root:FindFirstChild("Circle")
    return circle ~= nil and circle:FindFirstChildOfClass("Part") ~= nil
end

-- The first pad not lit yet, or nil.
function Summons.pendingPad()
    local root = summoner()
    local circle = root and root:FindFirstChild("Circle")
    if not circle then return nil end
    for _, child in ipairs(circle:GetChildren()) do
        local light = child:IsA("Part") and child:FindFirstChild("Part")
        if light and Common.colorName(light) ~= "Lime green" then return child end
    end
    return nil
end

-- The haki colour a pad asks for.
function Summons.colourFor(padPart)
    return Summons.PAD_COLOURS[Common.colorName(padPart)]
end

-- Haki colours the player has not unlocked yet.
function Summons.missingColours()
    local colours = Common.invoke("getColors")
    local missing = {}
    if type(colours) ~= "table" then return missing end
    for _, colour in pairs(colours) do
        if type(colour) == "table" and table.find(Summons.HAKI_COLOURS, colour.HiddenName) and not colour.Unlocked then
            missing[#missing + 1] = colour.HiddenName
        end
    end
    return missing
end

local function wearColour(colour)
    local net = Services.find(Services.replicated(), "Modules.Net")
    local customizer = net and net:FindFirstChild("RF/FruitCustomizerRF")
    if customizer then
        pcall(function()
            customizer:InvokeServer({ StorageName = colour, Type = "AuraSkin", Context = "Equip" })
        end)
    end
    if colour ~= "Winter Sky" then Services.invoke("activateColor", colour) end
end

function Summons.enabled()
    return (Settings.get("StackHakiPads") == true or Settings.get("StackSummonRipIndra") == true)
        and Player.sea() == 3
end

function Summons.want()
    if Settings.get("StackSummonRipIndra") and Common.has("God's Chalice") then return true end
    if not Settings.get("StackHakiPads") then return false end
    if loaded() then return Summons.pendingPad() ~= nil end
    return not padsDoneAt or os.clock() - padsDoneAt >= Summons.RECHECK
end

-- One step: light the pads (when `usePads`), then bring God's Chalice to
-- the summoner (when `useSummon`).
function Summons.run(mode, usePads, useSummon)
    mode.target = nil
    if not loaded() then
        Common.goTo(Summons.CASTLE)
        return "Going to the Boat Castle summoner"
    end

    local pending = usePads and Summons.pendingPad()
    if pending then
        local colour = Summons.colourFor(pending)
        if pending ~= pad then
            pad, padSince = pending, nil
            if colour then wearColour(colour) end
        end
        Common.goTo(pending.CFrame)
        if Common.near(pending.Position, 5) then
            Common.touch(pending)
            padSince = padSince or os.clock()
            if os.clock() - padSince >= Summons.STAND_TIME then pad = nil end
        end
        return "Haki pad (" .. tostring(colour or Common.colorName(pending)) .. ")"
    end
    padsDoneAt = os.clock()

    if useSummon and Common.has("God's Chalice") then
        local detection = summoner():FindFirstChild("Detection")
        if not detection then return "Summoner not loaded" end
        local chalice = Common.equip("God's Chalice")
        Common.goTo(detection.CFrame)
        if Common.near(detection.Position, 5) then Common.touch(detection, chalice) end
        return "Summoning rip_indra"
    end
    return "Pads lit"
end

function Summons.tick(mode)
    return Summons.run(mode, Settings.get("StackHakiPads") == true, Settings.get("StackSummonRipIndra") == true)
end

function Summons.reset()
    padsDoneAt, pad, padSince = nil, nil, nil
end

return Summons
