module("plugin_adminsay", package.seeall)

-- Required code
info = {
    name = "adminsay",  
    description = "Marks chatting players as administrators and allows them to talk even when dead",    
    author = "iron",
    version = "1.0",
    this = package.loaded.plugin_adminsay
}
registerplugin(info.this)
addserverlistener = server.geteventlistenerfunc(info.this)
addcommand = administration.getcommandregisterfunc(info.this)
tempban = administration.gettempbanfunc(info.this)
-- End required code

-- Don't let people pretend to be admins
function checkname(player)
    local name = server.stripgarbage(player.name)
    if(name:upper():match("^%s*%[ADMIN%].*$")) then
        print("Player " .. name .. " tried to use admin tag, tempbanning for 1m.")
        tempban(player.ip, administration.parsetimeperiod("1m"), "[ADMIN] in name", player.name)
    end
end

---------------
-- Listeners --
---------------
addserverlistener(server.SE_CHAT, function(player, text, teamchat)
    if(administration.getplayeraccess(player) >= config.ACCESS_REQUIRED) then
        if(not teamchat) then
            server.printall(PRINT_CHAT, server.safestringf(CHAR_COLOR .. string.char(63) .. "[ADMIN] %s:"..CHAR_COLOR..COLOR_CHAT.." %s\n", player.name, text))
        else
            -- TODO: uhhh.. you need to make this actually only go to their teammates...
            server.printall(PRINT_CHAT, server.safestringf(CHAR_COLOR .. string.char(63) .. "[ADMIN] (%s):"..CHAR_COLOR..COLOR_CHAT.." %s\n", player.name, text))
        end
        return true
    end
end)

addserverlistener(server.SE_NAMECHANGE, function(player, oldname)
    checkname(player)
end)
addserverlistener(server.SE_ENTER, function(player)
    checkname(player)
end)


