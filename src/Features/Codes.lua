--=============================================================================
-- CODES — redeems every known code (most give 2x experience for a while)
--=============================================================================
--  ReplicatedStorage.Remotes.Redeem:InvokeServer(code), one code every
--  EVERY seconds, in the background. The Teddy Kaitun does it at start
--  (OneClick.RedeemCode). Codes already tried on this account are kept in a
--  file, so the reload after each server hop does not ask them all again.
--=============================================================================

local Data = require("Game.Data")
local Services = require("Core.Services")

local Codes = {}

Codes.EVERY = 0.5
Codes.FOLDER = "StrawberryHub"

local busy = false

local function fileName()
    local player = Services.player()
    return Codes.FOLDER .. "/codes_" .. tostring(player and player.UserId or 0) .. ".json"
end

local function loadTried()
    local ok, tried = pcall(function()
        if not (isfile and readfile and isfile(fileName())) then return nil end
        return Services.get("HttpService"):JSONDecode(readfile(fileName()))
    end)
    return ok and type(tried) == "table" and tried or {}
end

local function saveTried(tried)
    pcall(function()
        if not writefile then return end
        if makefolder and isfolder and not isfolder(Codes.FOLDER) then makefolder(Codes.FOLDER) end
        writefile(fileName(), Services.get("HttpService"):JSONEncode(tried))
    end)
end

-- Redeems the codes not tried yet on this account (all of them with
-- `force`). Returns how many were sent, or nil when already running or the
-- remote is missing. Blocking: call it in task.spawn.
function Codes.redeemAll(force)
    if busy then return nil end
    local remote = Services.find(Services.replicated(), "Remotes.Redeem")
    if not remote then return nil end
    busy = true
    local tried = force and {} or loadTried()
    local sent = 0
    for _, code in ipairs(Data.CODES) do
        if not tried[code] then
            pcall(remote.InvokeServer, remote, code)
            tried[code] = true
            sent = sent + 1
            task.wait(Codes.EVERY)
        end
    end
    saveTried(tried)
    busy = false
    return sent
end

-- Test hook.
function Codes.reset()
    busy = false
end

return Codes
