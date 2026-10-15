--=============================================================================
-- SCENARIO leviathan_heart — the Leviathan is down, harpoon the Frozen Heart
--=============================================================================
--  Profile: Sea 3, seated in its own Beast Hunter boat (with its Harpoon and
--  the harpoon's Seat), 2500 studs from the Frozen Heart that just rose.
--
--  The fake server (facts from Meyy's Leviathan Kaitun and the hub's own
--  Islands module):
--    FireHarpoon(pitch, yaw, harpoon, serverTime)
--        accepted only from the harpoon seat, with the harpoon folder, the
--        pitch in [-10, 45] degrees and |yaw| <= 65 degrees, and the heart
--        within 600 studs. Then Inside gets Harpooned = true.
--  Expected: the boat brought to the heart, the harpoon taken, one accepted
--  shot, Harpooned set, and no shot refused for a bad angle.
--=============================================================================

local Islands = require("Features.Sea.Islands")
local Players = game:GetService("Players")

local HEART = Vector3.new(-30000, 0, 20000)
local START = HEART + Vector3.new(1500, 0, 2000)

SIM.world({
    sea = 3, level = 2550,
    position = START + Vector3.new(0, 12, 0),
    settings = { SeaLeviathanHeart = true },
})
SIM.enableBoats()

-- The boat, already ours, with the harpoon.
local boat = newInstance("Model", "Beast Hunter", workspace.Boats)
newInstance("ObjectValue", "Owner", boat).Value = Players.LocalPlayer.Name
newInstance("IntValue", "Humanoid", boat).Value = 1000
local seat = SIM.part("VehicleSeat", START + Vector3.new(0, 10, 0), boat, "VehicleSeat")
local harpoon = SIM.folder("Harpoon", boat)
local harpoonSeat = SIM.part("Seat", START + Vector3.new(0, 14, -12), harpoon, "Seat")
SIM.humanoid().SeatPart = seat
SIM.humanoid().Sit = true

-- The harpoon seat rides with the boat (welded in game).
local seatOffset = harpoonSeat.Position - seat.Position

-- The heart.
local heart = SIM.folder("FrozenHeart", workspace.Map)
local inside = SIM.part("Inside", HEART + Vector3.new(0, 20, 0), heart)
SIM.part("Cube", HEART + Vector3.new(0, 20, 0), heart)

local shots, refused = 0, {}
SIM.on("FireHarpoon", function(pitch, yaw, folder, at)
    shots = shots + 1
    local humanoid = SIM.humanoid()
    local why
    if not humanoid or humanoid.SeatPart ~= harpoonSeat then why = "not on the harpoon seat" end
    if folder ~= harpoon then why = "wrong harpoon argument" end
    if type(pitch) ~= "number" or pitch < math.rad(-10) - 1e-6 or pitch > math.rad(45) + 1e-6 then
        why = "pitch out of range: " .. tostring(pitch)
    end
    if type(yaw) ~= "number" or math.abs(yaw) > math.rad(65) + 1e-6 then why = "yaw out of range: " .. tostring(yaw) end
    if (harpoonSeat.Position - inside.Position).Magnitude > 600 then why = "too far from the heart" end
    if type(at) ~= "number" then why = "no server time" end
    if why then
        refused[#refused + 1] = why
        SIM.note("server: harpoon refused (" .. why .. ")")
        return false
    end
    inside:SetAttribute("Harpooned", true)
    SIM.note(string.format("server: heart harpooned (pitch %.3f, yaw %.3f)", pitch, yaw))
    return true
end)

SIM.start()
local done = SIM.run({
    seconds = 300,
    every = function()
        harpoonSeat.Position = seat.Position + seatOffset
        harpoonSeat.CFrame = CFrame.new(harpoonSeat.Position)
    end,
    untilFn = function() return inside:GetAttribute("Harpooned") == true end,
})

SIM.expect("boat brought near the heart", (seat.Position - inside.Position).Magnitude <= 600,
    (seat.Position - inside.Position).Magnitude)
SIM.expect("heart harpooned", done)
SIM.expect("no shot refused", #refused == 0, table.concat(refused, "; "))
SIM.expect("few shots", shots >= 1 and shots <= 3, shots)
SIM.finish("leviathan_heart")
