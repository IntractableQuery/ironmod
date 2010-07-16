module("plugin_joinsound", package.seeall)

-- Required code
info = {
    name = "joinsound",  
    description = "Plays a sound to a player when they enter the game",    
    author = "iron",
    version = "1.0",
    this = package.loaded.plugin_joinsound
}
registerplugin(info.this)
addserverlistener = server.geteventlistenerfunc(info.this)
addcommand = administration.getcommandregisterfunc(info.this)
-- End required code

if(config.JOINSOUND == nil) then 
    error("You must set JOINSOUND in the configuration!")
end

---------------
-- Listeners --
---------------
listen.game.postcall(GE_SPAWNENTITIES, function(data)
    -- register sound
    server.getsoundindex(config.JOINSOUND)
end)
addserverlistener(server.SE_ENTER, function(player)
    -- Play sound to this client
    -- TODO: this still plays to everyone in the game...figure out how the hell playsound_* is supposed to play to a single client
    server.playsound_ent(player.ent, nil, server.getsoundindex(config.JOINSOUND), 1.0, 4.0, 0, true)
end)
