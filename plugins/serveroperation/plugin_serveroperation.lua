module("plugin_serveroperation", package.seeall)

-- Required code
info = {
    name = "serveroperation",  
    description = "A general server operation interface for common server duties (addresses the exposure of standard DP server commands)",    
    author = "iron",
    version = "1.0",
    this = package.loaded.plugin_serveroperation
}
registerplugin(info.this)
addserverlistener = server.geteventlistenerfunc(info.this)
addcommand = administration.getcommandregisterfunc(info.this)
-- End required code

------------------------
-- Internal variables --
------------------------
-- This is basically config.CVAR_ACCESSLEVELS, but the keys are all forced to
-- lower-case for fast lookups.
local cvar_accesslevels = {}

---------------
-- Functions --
---------------
--- Strips semicolons from a string and puts it in the console.
local function safeputconsole(str)
    str = str:gsub(";", "");
    server.putconsole(str);
end


---------------
-- Listeners --
---------------
addcommand("cvar", 1, administration.CMDTYPE_SILENT, true, "<cvar> [new value]", "Changes a server console variable (cvar).", function(text, sourcelevel, player, replyfunc)
    -- Note: this command is access level 1 since we check access level only
    -- for specific cvars. Access level 1 will also mean it gets logged by
    -- default.
    
    -- Parse input and verify it is safe
    local cvar,newval = string.match(text, "^(.-) (.*)$")
    if(cvar == nil) then cvar = string.match(text, "^(.+)%s*$") end
    if(cvar == nil) then
        replyfunc("You must at least specify a cvar.")
    elseif(string.match(cvar, ";") or (newval ~= nil and string.match(newval, ";"))) then
        replyfunc("Your cvar or its new value may not contain a semicolon.")  
    else
        -- Get this cvar's information
        local requiredaccesslevel = cvar_accesslevels[cvar]
        if(requiredaccesslevel == nil) then requiredaccesslevel = config.DEFAULT_CVAR_ACCESS end
        if(sourcelevel >= requiredaccesslevel) then
            -- User has necessary access
            if(newval == nil) then
                -- User wants to see the value of the cvar
                -- TODO: add doc to getcvar if nil was fine here
                local val = server.getcvar(cvar)
                if(val ~= nil) then
                    replyfunc("cvar '"..cvar.."' is set to '"..val.."'")
                else
                    replyfunc("cvar '"..cvar.."' is not set.")
                end
            else
                -- User wants to set a new value for the cvar
                server.setcvar(cvar, newval)
                replyfunc("Successfully set cvar '"..cvar.."' to value '"..newval.."'")
                if(config.SHOW_CVAR_CHANGED) then
                    -- Notify other players if necessary
                    if(requiredaccesslevel < config.SHOW_CVAR_MAXLEVEL) then
                        local showval = true
                        for i,exempt in ipairs(config.SHOW_CVAR_EXEMPT) do
                            if(exempt:lower() == cvar) then
                                showval = false
                                break
                            end
                        end
                        local changer = "An administrator"
                        if(player ~= nil) then
                            changer = player.name
                        end
                        local valuechange = " to a new value (hidden)"
                        if(showval) then
                            valuechange = " to '"..newval.."'"
                        end
                        server.printlineall(1, "%s has changed '%s'%s", changer, cvar, valuechange)
                    end
                end
            end
        else
            -- User lacks necessary access
            replyfunc("You need access level " .. requiredaccesslevel .. " to view or modify this cvar.")
        end
    end    
end)
addcommand("map", 100, administration.CMDTYPE_SILENT, true, "<map name>", "Immediately changes to a new map.", function(text, sourcelevel, player, replyfunc, cmdinfo)
    -- TODO: if you ever setup a proper changemap() implementation in server, use it here...
    print("Processing map change request for map '" .. text .. "'")
    safeputconsole("sv newmap " .. text);
    replyfunc("Your map change request has been processed for map '"..text.."'. If the map is not changing now, then you probably misspelled it or it is not on the server.")
end)
addcommand("kick", 200, administration.CMDTYPE_SILENT, true, "<playernum> [reason]", "Kicks a player by their number", function(text, sourcelevel, player, replyfunc, cmdinfo)
    local playernum,reason = text:match("^%s*([0-9]+)%s*(.-)%s*$")
    if(playernum ~= nil and reason ~= nil) then
        local playernum = tonumber(playernum)
        local targetplayer = server.getplayerbynum(playernum)
        if(#reason == 0) then reason = nil end
        if(targetplayer ~= nil) then   
            -- Don't kick the target if they have as much or more access
            if(player ~= nil and administration.getplayeraccess(targetplayer) >= administration.getplayeraccess(player)) then
                replyfunc("You cannot kick a player with an access level equal to or greater than yours.")
            else
                server.kick(targetplayer, reason)
                replyfunc("Kicked " .. targetplayer.name)
            end
        else
            replyfunc("No such player with number '"..playernum.."'")
        end
    else
        replyfunc("Wrong arguments. Usage: " .. cmdinfo.usage)
    end 
end)
administration.addcommandalias("k", "kick")
addcommand("warn", 200, administration.CMDTYPE_SILENT, true, "<playernum> [reason]", "Warns a player", function(text, sourcelevel, player, replyfunc, cmdinfo)
    local playernum,reason = text:match("^%s*([0-9]+)%s*(.-)%s*$")
    if(playernum ~= nil and reason ~= nil) then
        local playernum = tonumber(playernum)
        local targetplayer = server.getplayerbynum(playernum)
        if(#reason == 0) then reason = nil end
        if(targetplayer ~= nil) then  
            local extrainfo = ""
            if(reason ~= nil) then extrainfo = ": "..reason end 
            server.printlineall(1, "%s has received a warning from the administrator.", targetplayer.name)            
            server.printcenter(targetplayer, "WARNING FROM ADMINISTRATOR"..extrainfo)
            server.printlineclient(1, targetplayer, "****************")
            if(player ~= nil) then
                server.printlineclient(2, targetplayer, "The administrator (%s) has warned you%s", player.name, extrainfo)
            else
                server.printlineclient(2, targetplayer, "The administrator has warned you%s", extrainfo)
            end
            server.printlineclient(1, targetplayer, "****************")
            replyfunc("Warning issued to player "..targetplayer.name)
        else
            replyfunc("No such player with number '"..playernum.."'")
        end
    else
        replyfunc("Wrong arguments. Usage: " .. cmdinfo.usage)
    end 
end)
administration.addcommandalias("w", "warn")

-- Configure the cvar access levels
for key,val in pairs(config.CVAR_ACCESSLEVELS) do
    cvar_accesslevels[key:lower()] = tonumber(val)
end
