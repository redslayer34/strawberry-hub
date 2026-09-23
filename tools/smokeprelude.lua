--=============================================================================
-- SMOKE PRELUDE — a loaded game for main.lua to start in
--=============================================================================
--  Runs before the bundle in the smoke suite: a player whose data has
--  loaded, a team already chosen, and a fake Fluent served by game:HttpGet
--  exactly where main.lua downloads the real one.
--=============================================================================

local genv = {}
getgenv = function() return genv end

local players = game:GetService("Players")
local player = newInstance("Player", "Tester", players)
players.LocalPlayer = player
newInstance("BoolValue", "DataLoaded", player)
local data = newInstance("Folder", "Data", player)
local level = newInstance("IntValue", "Level", data)
level.Value = 1

local gui = newInstance("PlayerGui", "PlayerGui", player)
local main = newInstance("ScreenGui", "Main", gui)
local chooseTeam = newInstance("Frame", "ChooseTeam", main)
chooseTeam.Visible = false
local questPanel = newInstance("Frame", "Quest", main)
questPanel.Visible = false

newInstance("Folder", "Enemies", workspace)
newInstance("Folder", "Characters", workspace)

local library, saveManager, interfaceManager, record = newFakeFluent()
FAKE = {
    library = library,
    saveManager = saveManager,
    interfaceManager = interfaceManager,
    record = record,
    urls = {},
}

game.HttpGet = function(_, url)
    FAKE.urls[#FAKE.urls + 1] = url
    if url:find("SaveManager", 1, true) then return "return FAKE.saveManager" end
    if url:find("InterfaceManager", 1, true) then return "return FAKE.interfaceManager" end
    return "return FAKE.library"
end

isfile = function() return false end
writefile = function() end
readfile = function() return nil end
