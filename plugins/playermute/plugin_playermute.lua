module("plugin_playermute", package.seeall)

-- Required code
info = {
    name = "playermute",  
    description = "Allows server administrators to mute players",    
    author = "iron",
    version = "1.0",
    this = package.loaded.plugin_playermute
}
registerplugin(info.this)
addserverlistener = server.geteventlistenerfunc(info.this)
addcommand = administration.getcommandregisterfunc(info.this)
-- End required code

-----------------------------
-- Local utility functions --
-----------------------------
--- Returns the informational table for a player.
-- The table has the following fields:
--   "muted" - Set to true if this player is muted
-- @param player a player reference
-- @return the player's mute information table
local function getplayermutetable(player)
    local mutetable = player.plugindata.playermute
    if(mutetable == nil) then 
        mutetable = {}
        mutetable.muted = false
    end
    player.plugindata.playermute = mutetable
    return mutetable
end

---------------
-- LISTENERS --
---------------
addserverlistener(server.SE_CHAT, function(player, text, teamchat)
    -- Is this player muted?
    local mutetable = getplayermutetable(player)
    if(mutetable.muted) then
        server.printlineclient(1, player, "%s", "You are muted.")
        return true -- Block their chat
    end
end)

-- Handles both muting and unmuting a player
local mutecommandlistener = function(text, sourcelevel, player, replyfunc, cmdinfo)
    local playernum = string.match(text, "^([0-9]+)$")
    if(playernum == nil) then
        replyfunc("You must enter a valid player number to mute.")
    else
        playernum = tonumber(playernum)
        local targetplayer = server.getplayerbynum(playernum)
        if(targetplayer ~= nil) then
            -- Verify that the targetplayer doesn't have as much or more access than the user muting them
            if(cmdinfo.name == "mute" and player ~= nil and administration.getplayeraccess(targetplayer) >= administration.getplayeraccess(player)) then
                -- Don't let them mute
                replyfunc("Player has equal or greater access level; you cannot mute "..targetplayer.name)
                return
            end
            
            local mutetable = getplayermutetable(targetplayer)
            if(cmdinfo.name == "mute") then
                if(mutetable.muted) then
                    replyfunc("That player is already muted.")
                else
                    mutetable.muted = true
                    server.printlineclient(1, targetplayer, "%s", "You have been muted by the administrator.")
                    replyfunc("Successfully muted player "..targetplayer.name)
                end
            else
                if(not mutetable.muted) then
                    replyfunc("That player is already unmuted.")
                else
                    server.printlineclient(1, targetplayer, "%s", "You have been unmuted by the administrator.")
                    mutetable.muted = false
                    replyfunc("Successfully unmuted player "..targetplayer.name)
                end
            end
        else
            replyfunc("No client exists for player number '"..playernum.."'")
        end
    end
end
addcommand("mute", 200, administration.CMDTYPE_SILENT, true, "<playernum>", "Mutes a player.", mutecommandlistener)
addcommand("unmute", 200, administration.CMDTYPE_SILENT, true, "<playernum>", "Unmutes a player.", mutecommandlistener)

