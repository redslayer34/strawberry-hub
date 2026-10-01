--=============================================================================
-- ENTRANCES — the Temple of Time map
--=============================================================================
--  The Temple of Time map lives in ReplicatedStorage.MapStash until the
--  client loads it; the temple teleport only works once it is in
--  workspace.Map. As in the references (Banana, Vxeze), it is borrowed
--  first and goes back to the stash unless the player reaches it within
--  BORROW_STEPS x 0.25 s. (The portal doors are in Game/Pads.)
--=============================================================================

local Player = require("Core.Player")
local Services = require("Core.Services")

local Entrances = {}

Entrances.TEMPLE = Vector3.new(28282.5703125, 14896.8505859375, 105.1042709350586)
Entrances.BORROW_STEPS = 120
Entrances.AT_TEMPLE = 1000

function Entrances.borrowTemple()
    local stash = Services.replicated():FindFirstChild("MapStash")
    local temple = stash and stash:FindFirstChild("Temple of Time")
    local map = workspace:FindFirstChild("Map")
    if not temple or not map then return false end
    temple:SetAttribute("ClientBorrowed", true)
    temple.Parent = map
    task.spawn(function()
        for _ = 1, Entrances.BORROW_STEPS do
            task.wait(0.25)
            if temple.Parent ~= map or Player.distanceTo(Entrances.TEMPLE) < Entrances.AT_TEMPLE then break end
        end
        pcall(function()
            temple:SetAttribute("ClientBorrowed", nil)
            if temple.Parent == map and Player.distanceTo(Entrances.TEMPLE) >= Entrances.AT_TEMPLE then
                temple.Parent = stash
            end
        end)
    end)
    return true
end

return Entrances
