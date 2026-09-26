--=============================================================================
-- SERVER TAB — server status, hop, rejoin, JobId
--=============================================================================

local Bind = require("UI.Bind")
local Loop = require("Core.Loop")
local Player = require("Core.Player")
local Server = require("Game.Server")
local Services = require("Core.Services")
local World = require("Game.World")

local function statusText()
    local players = Services.get("Players")
    local count = #players:GetPlayers()
    local max = players.MaxPlayers or "?"
    return table.concat({
        "Players " .. count .. "/" .. tostring(max) .. "  |  Sea " .. tostring(Player.sea() or "?"),
        "Moon: " .. World.moon() .. "  |  Time " .. World.clock(),
        "Elite Hunter: " .. (World.eliteHunter() or "none"),
        "JobId: " .. tostring(game.JobId),
    }, "\n")
end

return function(Window, ui)
    local tab = Window:AddTab({ Title = "Server", Icon = "server" })

    local function notify(text)
        ui.Library:Notify({ Title = "Server", Content = text, Duration = 5 })
    end

    local status = tab:AddSection("Status")
    local panel = status:AddParagraph({ Title = "Server", Content = statusText() })
    Loop.start("ServerPanel", 1, function() panel:SetDesc(statusText()) end)

    local hop = tab:AddSection("Hop")
    Bind.toggle(hop, "AutoExecute", "Reload after teleport",
        "Starts Strawberry Hub again by itself in the next server.")
    Bind.toggle(hop, "ScreenAutoRejoin", "Auto Rejoin On Disconnect",
        "Rejoins the game when Roblox shows a disconnection message.")

    hop:AddButton({ Title = "Hop server", Callback = function()
        notify("Looking for a server...")
        task.spawn(function()
            if not Server.hop() then notify("No other server found") end
        end)
    end })
    hop:AddButton({ Title = "Hop to a low player server", Callback = function()
        notify("Looking for a quiet server...")
        task.spawn(function()
            if not Server.hopLow() then notify("No low player server found") end
        end)
    end })
    hop:AddButton({ Title = "Rejoin", Callback = function() Server.rejoin() end })

    local job = tab:AddSection("JobId")
    job:AddButton({ Title = "Copy JobId", Callback = function()
        if setclipboard then
            setclipboard(tostring(game.JobId))
            notify("JobId copied")
        else
            notify("Your executor cannot copy to the clipboard")
        end
    end })
    local input = job:AddInput("JoinJobId", { Title = "JobId to join", Default = "", Placeholder = "Paste a JobId" })
    Bind.toggle(job, "JoinSpam", "Spam Join",
        "Join JobId keeps asking every 0.5 s (for a full server) until you turn this off.")
    job:AddButton({ Title = "Join JobId", Callback = function()
        if not Server.join(input.Value) then
            notify("Enter a JobId first")
            return
        end
        if Server.spamJoin(input.Value) then notify("Spam join started") end
    end })

    return tab
end
