module("plugin_namenotifier", package.seeall)

-- Required code
info = {
    name = "playermute",  
    description = "Notifies players of name changes taking place",    
    author = "iron",
    version = "1.0",
    this = package.loaded.plugin_namenotifier
}
registerplugin(info.this)
addserverlistener = server.geteventlistenerfunc(info.this)
addcommand = administration.getcommandregisterfunc(info.this)
-- End required code

---------------
-- LISTENERS --
---------------
addserverlistener(server.SE_NAMECHANGE, function(player, oldname)
    server.printlineall(1, "%s has changed their name to %s", oldname, player.name)
end)

