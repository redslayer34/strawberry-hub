--=============================================================================
-- LOGO — the strawberry image, from the repo to the executor's workspace
--=============================================================================
--  Roblox only shows uploaded assets, so the image is downloaded once from
--  the repo (assets/strawberry.png), saved in the workspace and handed to
--  the executor's getcustomasset. Without those functions the caller keeps
--  its text fallback (the 🍓 emoji).
--=============================================================================

local Logo = {}

Logo.URL = "https://raw.githubusercontent.com/redslayer34/strawberry-hub/claude/repo-exploration-ez26bn/assets/strawberry.png"
Logo.FILE = "StrawberryHub/strawberry.png"

local cached

-- The asset id to put in an ImageLabel, or nil.
function Logo.asset()
    if cached ~= nil then return cached or nil end
    cached = false
    local load = getcustomasset or (syn and syn.getasset) or getsynasset
    if not (load and writefile and isfile) then return nil end
    local ok, asset = pcall(function()
        if not isfile(Logo.FILE) then
            local data = game:HttpGet(Logo.URL)
            if type(data) ~= "string" or data:sub(2, 4) ~= "PNG" then error("not a PNG") end
            if makefolder and isfolder and not isfolder("StrawberryHub") then makefolder("StrawberryHub") end
            writefile(Logo.FILE, data)
        end
        return load(Logo.FILE)
    end)
    if ok and type(asset) == "string" and asset ~= "" then cached = asset end
    return cached or nil
end

-- Test hook.
function Logo.reset()
    cached = nil
end

return Logo
