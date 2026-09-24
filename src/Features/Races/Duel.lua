--=============================================================================
-- RACES: DUEL — fighting another player (race V3 quests, after a trial)
--=============================================================================
--  PvP is switched on when the game shows it off, the character stays next
--  to the target, every skill is aimed at it and the attack loop hits it
--  (Combat.strike hits players' characters when they are the target).
--  A duel gives up after GIVE_UP seconds, or when the target reaches a safe
--  zone with most of its health.
--=============================================================================

local Common = require("Features.Stack.Common")
local Mastery = require("Game.Mastery")
local Player = require("Core.Player")
local Services = require("Core.Services")

local Duel = {}

Duel.GIVE_UP = 70
Duel.SAFE_RADIUS = 400

local started = {}   -- [character] = first seen
local done = {}      -- [player name] = true once duelled

local function alive(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") ~= nil
end

function Duel.safe(character)
    local zones = Services.find(workspace, "_WorldOrigin.SafeZones")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    for _, zone in ipairs(zones and zones:GetChildren() or {}) do
        if zone:IsA("Part") and (zone.Position - character.HumanoidRootPart.Position).Magnitude <= Duel.SAFE_RADIUS
            and humanoid and humanoid.Health / math.max(humanoid.MaxHealth or 1, 1) >= 0.9 then
            return true
        end
    end
    return false
end

-- The next player to duel: `accept(player)` filters, players already
-- duelled are skipped.
function Duel.pick(accept)
    local me = Services.player()
    for _, player in ipairs(Services.get("Players"):GetPlayers()) do
        if player ~= me and not done[player.Name] and alive(player.Character) and (not accept or accept(player)) then
            return player
        end
    end
    return nil
end

-- One step against `player`. Returns the status, or nil when the duel is over.
-- `useSkills` (default true) also fires the weapons' skills at the target.
function Duel.fight(mode, player, weapon, useSkills)
    local character = player.Character
    if not alive(character) or Duel.safe(character) then
        done[player.Name] = true
        return nil
    end
    started[character] = started[character] or os.clock()
    if os.clock() - started[character] >= Duel.GIVE_UP then
        done[player.Name] = true
        return nil
    end
    local me = Services.player()
    local disabled = me and Services.find(me, "PlayerGui.Main.BottomHUDList.PvpDisabled")
    if disabled and disabled.Visible and Common.every("EnablePvp", 5) then Services.invoke("EnablePvp") end
    local root = character.HumanoidRootPart
    Common.goTo(root.CFrame * CFrame.new(0, 0, 3))
    if weapon then Player.equip(weapon) end
    if useSkills ~= false and Player.distanceTo(root.Position) < 50 then Mastery.fireAt(root.CFrame) end
    mode.target = character
    return "Fighting " .. player.Name
end

function Duel.reset()
    started, done = {}, {}
end

return Duel
