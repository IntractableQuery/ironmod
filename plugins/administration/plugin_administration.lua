-- This is IronMod's standard administration plugin. It allows other plugins
-- to make their own administrative commands, in addition to checking user
-- access levels.

module("plugin_administration", package.seeall)

-- Required code
info = {
    name = "administration",  
    description = "core server plugin (command and administration interface)",    
    author = "iron",
    version = "1.0",
}
registerplugin(package.loaded.plugin_administration)
addserverlistener = server.geteventlistenerfunc(package.loaded.plugin_administration)
-- End required code

----------------------
-- Public variables --
----------------------
--- This indicates that after a person enters the given command, that other 
-- players will be able to see it. That is, it is forwarded to regular chat.
CMDTYPE_SEEALL = 0
--- This indicates that after a person enters the given command, that it is
-- not forwarded to regular chat, so other people will not see it. You
-- should do this for commands that contain sensitive information that other
-- players should not see you entering, or simply commands that need to be
-- executed silently.
CMDTYPE_SILENT = 1
--- The highest amount of access a person can have.
MAX_ACCESS = 500
--- The log file to write to
loghandle = nul

---------------------
-- Local variables --
---------------------
--- This table maps a lowercase case-insensitive command name to a table with 
-- the following fields:
--       "plugin" - a reference to the plugin that registered this command
--       "handler" - a function that takes the player and arguments after the command every time it is used
--       "accesslevel" - the minimum (inclusive, of course) access level needed to use this command
--       "cmdtype" - a TYPE_ constant value
--       "name" - the name of the command, for convenience
--       "infotext" - a short one-sentence description
--       "aliases" - a list of alternate names for this command, which are also stored in the commandaliases table
--       "usage" - a string indicating how this command should be used
--       "consoleusable" - a boolean value that is true if this command can be used from the console
local commands = {}
--- This is an auxillary table that maps plugin.info.names to their list
-- of commands.
local plugincommands = {}
--- This is a list of aliases that map to a real command.
local commandaliases = {}
--- This is a table that maps lowercase user handles (short little names) to
-- that user's settings table. Anything can modify these settings,
-- but the standard settings that the administration plugin uses are:
--       "access" - this user's server access level
--       "gblid" - a global login ID to recognize this user with
--       "cloak" - a value that is true if the user is to be hidden from most informational output
local users
--- An array of temporary bans. Each ban contains the following informational
-- fields:
--       "name" - The name of the person who was banned. May be nil if no
--                name was ever given.
--       "ipmask" - The IP address of the user to ban. Can contain IRC-style
--                 * and ? wildcards. Prefixing the ban IP with "^" will mark
--                 it for pattern processing, meaning that the entire IP
--                 (including the starting ^) will be treated as a Lua pattern.
--       "expires" - The time when this ban expires, expressed in absolute seconds
--                that must be met with os.time()
--       "length" - The original time period of the ban.
--       "reason" - An optional ban reason. May be nil.
--       "source" - The originator of the ban. It is a string formatted as "plug:pluginname" or "user:username". This is considered somewhat private, and it is best to show who banned the user in the reason instead.
tempbans = {}
--- These are settings that we will allow to be set on users. The purpose of
-- this is so we can enforce "type safety" for the user entries.
local VALIDSETTINGS = { "access", "gblid", "cloak" }
--- A pattern character set that constitutes valid user handle characters.
local PATTERNHANDLE = "0-9a-z_"

-----------------------------
-- Local utility functions --
-----------------------------
--- Given a non-nil player, this will return their information table used for
-- administration purposes.
-- @param player the player to retrieve the table for
-- @return a table with the following fields:
--           handle - this person's user handle, or nil if they are not logged in as a user
function getplayerauthtable(player)
    assert(player ~= nil, "player cannot be nil")
    local t = player.plugindata.administration
    if(t == nil) then
        t = {}
        t.access = 0 -- Default to no access
        player.plugindata.administration = t
    end
    return t
end
--- Logs a line of text to the log file, assuming it is open.
-- @param txt the text to log
local function log(txt)
    if(loghandle ~= nil) then
        local curtime = os.date("%b %e %T")
        loghandle:write(string.format("%-20s %s", "["..curtime.."]", txt.."\n"))
        loghandle:flush()
    end
end
--- Handles a plugin being unregistered for which we are currently serving
-- command events.
-- @param plugin the plugin being unregistered
local function pluginunregisterhandler(plugin)
    -- Build a list of commands this plugin owns
    local plugcmds = {}
    
    for command,cmdinfo in pairs(commands) do
        if(cmdinfo.plugin == plugin) then
            plugcmds[#plugcmds+1] = command
        end
    end
    
    -- Unregister all of the commands
    for command in ipairs(plugcmds) do 
        unregistercommand(command)
    end
end
--- This takes a command name and returns the actual command entry for it. It
-- will resolve an alias, too.
-- @param cmd the command
-- @return a command entry, or nil if none was found
local function getcommandinfo(cmd)
    local command = string.lower(cmd)
    local commandinfo = commands[command]
    if(commandinfo == nil) then
        -- Maybe it's an alias?
        local realcmd = commandaliases[command]
        if(realcmd ~= nil) then
            -- It was!
            commandinfo = commands[realcmd]
        end
    end
    return commandinfo
end
--- Processes a command from a player.
-- @param player the player who sent the command
-- @param command the command they used
-- @param cmdargs the arguments to the command (may be an empty string)
-- @return true to block the text from going to chat, false or nil to allow it to
local function processplayercommand(player, command, cmdargs)
    local commandinfo = getcommandinfo(command)
    if(commandinfo ~= nil) then
        -- Valid command entered
        local handle = getplayeruserhandle(player)
        
        -- Do we have enough access to use the command?
        if(userhasaccess(handle, commandinfo.accesslevel)) then
            -- We can use this command...      
            -- Prepare reply function
            local messagessent
            local replyfunc = function(text, shade)
                assert(text ~= nil, "text cannot be nil")
                if(shade == nil) then shade = 1 end
                if(player.discarded) then
                    return false
                else
                    server.printlineclient(shade, player, "%s", text)
                    gidp.unicast(player.ent, 0) -- Force buffer flush (non-reliable)
                    return true
                end
            end               
            if(commandinfo.accesslevel >= config.LOG_MINLEVEL) then log("[PLAYER] "..tostring(handle)..": '" .. command .. "' '" .. cmdargs .. "'") end            
            -- Call the handler / TODO: You REALLY need to xpcall this, since error'd commands will get relayed to chat (sensitive stuff?) and it also never tells the user there was an error           
            commandinfo.handler(cmdargs, getuseraccess(handle), player, replyfunc, commandinfo)          
            if(commandinfo.cmdtype == CMDTYPE_SEEALL) then
                return false
            else
                return true -- Assume CMDTYPE_SILENT
            end
        else
            -- We do not have enough access for this command
            server.printlineclient(1, player, "%s", "Command '"..tostring(command).."' requires at least access level "..commandinfo.accesslevel..", but you only have access level "..getuseraccess(handle))
            return true
        end
     else 
        -- This is an unknown command
        server.printlineclient(1, player, "%s", "Unknown command '"..getcommandprefix()..tostring(command).. "'")
        return true
     end
end
--- Loads the users configuration file into the users table. If it does not
-- exist, it creates it.
local function loadusers() 
    if(config.USERCONFIGFILE == nil) then
        error("USERCONFIGFILE not set in configuration")
    end
    
    users = nil
    local f,err = io.open(plugpath..config.USERCONFIGFILE, "r")
    if(f ~= nil) then
        users = extra.deserialize(f:lines())
        if(type(users) ~= "table") then
            error(config.USERCONFIGFILE.." is not serialized as a table")
        end
        f:close()
    else
        print("Encountered error while trying to read users configuration from "..config.USERCONFIGFILE..": "..tostring(err))
        print("I'll now create a new empty users configuration and save it")
        users = {}
        saveusers()
    end
end

----------------------
-- Global functions --
----------------------
--- Given an access level, this will return a string that represents what type
-- of user is associated with that access level.
-- @param accesslevel the access level to check with
-- @return a non-nil name for this access level
function getaccessname(accesslevel) 
    for i,level in ipairs(config.ACCESSNAMES) do
        if(accesslevel >= level.start and accesslevel <= level.ending) then
            -- Found it!
            return level.name
        end
    end
    -- Never found it...
    return "unknown access level user"
end
--- Returns the prefix used for commands in chat. 
-- @return the command prefix (by default, it is usually "!", but it can be changed in the configuration)
function getcommandprefix() 
    local prefix = config.COMMANDPREFIX
    assert(prefix ~= nil, "COMMANDPREFIX not set in configuration")
    return prefix
end
--- Adds an alias for an existing command. This alias can be used to use that
-- command in the future. The most obvious use for this is shortening commands,
-- such as turning making a command called "tempban" accessible using just "tb".
-- @param aliascommand the alias to use for the command
-- @param command the command that is aliased to
function addcommandalias(aliascommand, command) 
    assert(aliascommand ~= nil, "aliascommand cannot be nil")
    assert(command ~= nil, "command cannot be nil")
    aliascommand = string.lower(aliascommand)
    command = string.lower(command)    
    -- Find the command and add it to its aliases array
    local cmdinfo = commands[command]
    if(cmdinfo == nil) then error ("no such command '"..command.."'") end
    cmdinfo.aliases[#cmdinfo.aliases+1] = aliascommand
    -- Add directly to our lookup table
    commandaliases[aliascommand] = command
end
--- Removes a command alias.
-- @param aliascommand the alias to remove
function removecommandalias(aliascommand) 
    assert(aliascommand ~= nil, "aliascommand cannot be nil")
    aliascommand = string.lower(aliascommand)
    local command = commandaliases[aliascommand]
    if(command == nil) then error("no such alias '"..aliascommand.."'") end
    -- Find the command and remove the alias from it
    local cmdinfo = commands[command]
    if(cmdinfo == nil) then error ("unexpected: no such command '"..command.."' for existing alias '"..aliascommand.."'") end
    local newaliases = {}
    for i,cmdalias in ipairs(cmdinfo.aliases) do
        if(cmdalias ~= aliascommand) then newaliases[#newaliases+1] = cmdalias end
    end
    cmdinfo.aliases = newaliases
end
--- Adds a command to the internal commands list. Note that it does not 
-- necessarily need to be an administration command.
-- @param plugin the plugin that is registering this command.
-- @param command the case-insensitive command that will be added to the commands
--        registry.
-- @param accesslevel the minimum access level required to use this command. 
-- @param commandtype either CMDTYPE_SEEALL or CMDTYPE_SILENT.
-- @param consoleusable true if this command can be used by the console, or false if it cannot (implying player is NEVER nil)
-- @param usagetext text that indicates how your command is to be used -- if your command takes no arguments, this should be nil (denote arguments with pointy brackets and optional arguments with hard brackets, e.g. "<non-optional argument> [optional argument]"
-- @param infotext informational text related to your command -- please keep it short
-- @param handler a function that is called every time this command used.
--                This function takes the following arguments:
--                   cmdargs - The arguments for the command (empty string if no arguments)
--                   accesslevel - The access level of whoever is issuing this command
--                   player - The player that issued to command. If the command was from the console, then this will be nil.
--                   replyfunc - A function that prints your reply to the user of the command, which is the preferred way to do replies. It takes an optional second argument, shade (see printlineclient()). The function returns true if the reply was sent successfully, or false if it was not (you may assume that you can no longer send replies, so here's a good spot to clean up anything you need to handle). You may call this function multiple times, although be careful about creating memory leaks by storing this on anything but a player instance.
--                   cmdinfo - A table containing your command's information, like "aliases" and "usage"
function registercommand(plugin, command, accesslevel, commandtype, consoleusable, usagetext, infotext, handler)
    assert(plugin ~= nil, "plugin cannot be nil")
    assert(command ~= nil, "command cannot be nil")
    assert(accesslevel ~= nil, "accesslevel cannot be nil")
    assert(commandtype ~= nil, "commandtype cannot be nil")
    assert(infotext ~= nil, "infotext cannot be nil")
    assert(handler ~= nil, "handler cannot be nil")
    
    local propercmd = string.lower(command)
    
    local existingcommand = commands[propercmd]
    if(existingcommand ~= nil) then
        -- Warn about this, we appear to have a command collision
        warn("Plugin '" .. plugin.info.name .. "' is overwriting the command '" .. propercmd .. "' that was added earlier by plugin '" .. existingcommand.plugin.info.name .. "'!")
    end
    
    local newcmd = {}
    newcmd.plugin = plugin
    newcmd.accesslevel = accesslevel
    newcmd.consoleusable = consoleusable
    newcmd.infotext = infotext
    newcmd.cmdtype = commandtype
    newcmd.handler = handler
    newcmd.name = propercmd 
    newcmd.aliases = {}   
    newcmd.usage = usagetext
    commands[propercmd] = newcmd 
    -- Add to aux
    local commandslist = plugincommands[plugin.info.name]
    if(commandslist == nil) then commandslist = {} end
    commandslist[#commandslist+1] = propercmd   
    plugincommands[plugin.info.name] = commandslist
    -- Make sure we catch plug unregistration
    registerunreglistener(plugin, pluginunregisterhandler)
    -- Update the listenercounts table
    local listenerkey = "administration:cmds"
    local currentcount = plugin.listenercounts[listenerkey]
    if(currentcount == nil) then currentcount = 0 end
    currentcount = currentcount + 1
    plugin.listenercounts[listenerkey] = currentcount
end
--- Unregisters a command from the commands list.
-- @param command the command (as a string, of course) to remove
function unregistercommand(command)
    assert(command ~= nil, "command cannot be nil")
    command = string.lower(command)
    commands[command] = nil -- That's simple!
    -- Drop it from the aux table
    for pluginname,cmds in pairs(plugincommands) do
        local newcmds = {}
        for cmd in cmds do
            if(cmd ~= command) then 
                newcmds[#newcmds+1] = cmd 
            else
                -- Update the listenercounts table
                local plugin = package.loaded[pluginname]
                local listenerkey = "administration:cmds"
                local currentcount = plugin.listenercounts[listenerkey]
                if(currentcount == nil) then currentcount = 0 end
                currentcount = currentcount - 1
                plugin.listenercounts[listenerkey] = currentcount
            end
        end
        plugincommands[pluginname] = newcmds
    end
end
--- Returns a function that can be used to register your commands. It eliminates
-- the need to constantly keep passing in your own plugin reference. The returned
-- function is exactly the same as registercommand(), but it does not take the
-- first argument, "plugin".
-- @param plugin your plugin
-- @return a function similar to registercommand, but without the first argument
function getcommandregisterfunc(plugin) 
    assert(plugin ~= nil, "plugin cannot be nil")
    return function(...)
        return registercommand(plugin, ...)
    end
end
--- Saves the users configuration file to disk.
function saveusers() 
    local f,err = io.open(plugpath..config.USERCONFIGFILE, "w")
    if(f ~= nil) then
        extra.serialize(f, users)
        f:close()
    else
        warn("Unable to save users configuration to '"..config.USERCONFIGFILE.."': "..tostring(err))
    end
end
--- Adds a user and saves them in the configuration file. Warning: this will
-- overwrite the user handle if they already existed.
-- @param handle a name without spaces for this user
-- @param settings an optional table of settings to immediately associate with this user
-- @param nosave an optional boolean value that if set to true, will force the configuration file to not be saved immediately (only use this in rare circumstances, please)
-- @return true if the user was successfully added, or false if they were not (if false, an error string is also returned)
function adduser(handle, settings, nosave) 
    assert(handle ~= nil, "handle cannot be nil")
    if(settings == nil) then settings = {} end
    if(nosave == nil) then nosave = false end
    handle = string.lower(handle)
    if(string.match(handle, "[^"..PATTERNHANDLE.."]")) then
        return false, "user handles can only use letters, numbers, and the underscore character"
    end
    users[handle] = settings
    if(not nosave) then saveusers() end
    return true
end
--- Removes a user by their handle and saves the change to the configuration file.
-- @param handle the handle of the user to remove
-- @param nosave an optional boolean value that if set to true, will force the configuration file to not be saved immediately (only use this in rare circumstances, please)
-- @return true if the user was successfully removed, or false if they were not (if false, an error string is also returned)
function removeuser(handle, nosave) 
    assert(handle ~= nil, "handle cannot be nil")
    if(nosave == nil) then nosave = false end
    handle = string.lower(handle)
    if(users[handle] == nil) then 
        return false, "no user matching handle '"..handle.."'"
    end
    users[handle] = nil
    if(not nosave) then saveusers() end
    return true
end
--- Sets several settings at once on a user. Note that this is not replacing
-- the user settings, it is merely adding or overriding existing ones. The
-- users configuration file will automatically be saved afterwards.
-- @param handle the handle of the user to modify settings for
-- @param settings a table of settings to apply to this user (existing settings will be overwritten)
-- @param nosave an optional boolean value that if set to true, will force the configuration file to not be saved immediately (only use this in rare circumstances, please)
-- @return true if the user settings were successfully set, or false if they were not (if false, an error string is also returned)
function setusersettings(handle, settings, nosave) 
    assert(handle ~= nil, "handle cannot be nil")
    assert(settings ~= nil, "settings cannot be nil")
    assert(type(settings) == "table", "settings must be table")
    if(nosave == nil) then nosave = false end
    handle = string.lower(handle)
    local usersettings = users[handle]
    if(usersettings == nil) then return false, "no such user for handle '"..handle.."'" end
    for k,v in pairs(settings) do
        usersettings[k] = v
    end
    if(not nosave) then saveusers() end
    return true
end
--- Returns the settings for a given user handle.
-- @param handle the handle of the user to return settings for
-- @return a table of the user's settings, or nil if there was an error during retrieval (an error string will also be returned)
function getusersettings(handle) 
    assert(handle ~= nil, "handle cannot be nil")
    handle = string.lower(handle)
    local usersettings = users[handle]
    if(usersettings == nil) then return nil, "no such user for handle '"..handle.."'" end
    return usersettings
end
--- Determines if a user exists for the given handle.
-- @param handle the handle of the user
-- @return true if the user exists, false otherwise
function userexists(handle) 
    assert(handle ~= nil, "handle cannot be nil")
    handle = string.lower(handle)
    return users[handle] ~= nil
end
--- Returns a user's access level. If their access it not yet assigned or the
-- player handle is invalid, this function returns 0, making it ideal for 
-- checking access in any situation.
-- @param handle the handle of the user (a nil value will result in 0 being returned)
-- @return the user's access level, or nil if there was an error during retrieval (an error string will also be returned)
function getuseraccess(handle)
    if(handle == nil) then return 0 end
    handle = string.lower(handle)
    local settings,err = getusersettings(handle)
    if(settings == nil) then
        -- Error!
        return 0
    else
        if(settings.access ~= nil) then
            return tonumber(settings.access)
        else
            return 0
        end
    end
end
--- Determines if the given user has the required minimum level of access. This
-- function defaults to returning false if any invalid information is supplied 
-- (like a nil handle), although accesslevel MUST be non-nil.
-- @param handle the handle of the user (it may be nil, in which case false is returned)
-- @param accesslevel the minimum level of access this user needs for this to return true (cannot be nil)
-- @return true if the user meets the access level, or false otherwise
function userhasaccess(handle, accesslevel) 
    assert(accesslevel ~= nil, "accesslevel cannot be nil")
    return getuseraccess(handle) >= accesslevel
end
--- Given a player, this will return a non-nil access level for them. 
-- @param player the player to retrieve the access level for
-- @return the player's access level
function getplayeraccess(player)
    local accessinfo = getplayerauthtable(player)
    return getuseraccess(accessinfo.handle)
end
--- Given a player, this will return their user handle if they are logged in.
-- If they are not logged in, nil will be returned.
-- @param player the player reference
-- @return the user's handle as a string or nil if they are not logged in at the moment
function getplayeruserhandle(player)
    local authinfo = getplayerauthtable(player)
    return authinfo.handle
end
--- Parses a string that is meant to express a time period. The string consists
-- of time periods, with the time unit directly after it. A quick example would
-- be: "1d4h30m20s", which represents a time period lasting 1 day, 4 hours, 
-- 30 minutes, and 20 seconds. Note that you may use spaces in the string,
-- like "50h 70m" or "80 h 20 m", etc.
-- This function is not meant for just user input, but as an easy way for
-- plugin authors to express time in their code.
-- The following is a list of characters recognized as time units:
--    "d" - Day (24 hours)
--    "h" - Hour
--    "m" - Minute
--    "s" - Second
-- @param timestring the string to parse time from
-- @return the number of seconds in the time period (faulty input will result in no errors, as it simply reads as much of the time specifier as possible and then returns)
function parsetimeperiod(timestring)
    assert(timestring ~= nil, "timestring cannot be nil")
    local timeperiod = 0
    for period,timeunit in string.gmatch(timestring, "%s*([0-9]+)%s*([dhms])%s*") do
        period = tonumber(period)
        if(timeunit == "d") then
            timeperiod = timeperiod + period * 86400
        elseif(timeunit == "h") then
            timeperiod = timeperiod + period * 3600
        elseif(timeunit == "m") then
            timeperiod = timeperiod + period * 60
        elseif(timeunit == "s") then
            timeperiod = timeperiod + period
        end
    end
    return timeperiod
end
--- Returns a string in the same format that is parsed by parsetimeperiod().
-- @param timesecs the number of seconds in the time period
-- @param small set to true to not put spaces in the output, or false/nil to keep spaces in it
-- @return a string described by parsetimeperiod()
function timeperiod(timesecs, small)
    assert(timesecs ~= nil, "timesecs cannot be nil")
    local suffix = " "
    if(small) then suffix = "" end
    local str = ""
    local days,hours,minutes,seconds = 0,0,0,0    
    days = math.modf(timesecs / 86400)
    timesecs = math.fmod(timesecs, 86400)
    hours = math.modf(timesecs / 3600)
    timesecs = math.fmod(timesecs, 3600)
    minutes = math.modf(timesecs / 60)
    timesecs = math.fmod(timesecs, 60)
    seconds = timesecs
    if(days > 0) then
        str = str .. days .. "d" .. suffix
    end
    if(hours > 0) then
        str = str .. hours .. "h" .. suffix
    end
    if(minutes > 0) then
        str = str .. minutes .. "m" .. suffix
    end
    if(seconds > 0) then
        str = str .. seconds .. "s" .. suffix
    elseif(#str == 0) then
        -- String is empty, we need to at least return something
        str = "0s"    
    end
    return string.match(str, "^(.-)%s*$") -- trim off any trailing space we left
end
--- This returns a function that behaves just like tempban(), but it does
-- not take the first argument, source, as it will automatically be provided
-- as your plugin's name. This is the preferred way for you to issue bans, 
-- unless you have a compelling reason to change the source.
-- @param plugin your plugin instance
function gettempbanfunc(plugin) 
    assert(plugin ~= nil, "plugin cannot be nil")
    return function(ipmask, timeperiod, reason, name)
        return tempban("plug:"..plugin.info.name, ipmask, timeperiod, reason, name)
    end
end
--- Temporarily bans an IP address. If a player or player(s) on the server match
-- that address, they are immediately ejected. If you are using a plugin to
-- do this (and not doing it for a user), please see gettempbanfunc().
-- @param source a string representing the creator of the ban (may indicate a plugin name or player). By convention, please use "plug:PLUGINNAME" or "user:USERNAME" to indicate the source.
-- @param ipmask the absolute IP address to ban, which may include IRC-style wildcards '*' to match any character sequence and '?' to match a single character. Starting the IP with a '^' marks it as a Lua pattern, and it will be evaluated as such (it will include the starting '^' in the pattern).
-- @param timeperiod the number of seconds to ban the ip for
-- @param reason an optional reason for the ban (may be nil if you wish to omit the reason, but plugins should ALWAYS give a reason)
-- @param name the optional name of the person getting banned (it is just for human-friendly reading, can be nil if you wish to omit it)
-- @return true if the ban succeeded, or false if it was blocked from taking place (if this is the case, you also get an error message)
function tempban(source, ipmask, timeperiod, reason, name)
    assert(source ~= nil, "source cannot be nil") 
    assert(ipmask ~= nil, "ipmask cannot be nil")
    assert(timeperiod ~= nil, "timeperiod cannot be nil")
    
    local banentry = {}
    banentry.ipmask = ipmask
    banentry.length = timeperiod
    banentry.expires = timeperiod + os.time()
    banentry.name = name
    banentry.reason = reason
    banentry.source = source
    
    -- Make sure the ipmask does not already exist for another ban
    for i,ban in pairs(tempbans) do
        if(ban.ipmask == ipmask) then
            return false,"Ban for ipmask '"..ipmask.."' already exists"
        end
    end
    
    -- Build a list of matching players
    local kicklist = {}
    for i,player in pairs(server.players) do
        if(ipmaskmatch(player.ip, ipmask)) then
            if(getplayeraccess(player) > config.TEMPBANEXEMPTLEVEL) then
                -- This player is an admin we can't ban; cancel this ban and warn that admin
                if(reason == nil) then reason = "" end
                server.printlineclient(1, player, "%s", "Blocking a tempban for ipmask '"..ipmask.."' which would have affected you. This was from '"..source.."', with reason '"..reason.."'")
                return false,"Ban would affect administrator '"..getplayeruserhandle(player).."'; cancelled"
            else
                -- Candidate for ejection
                kicklist[#kicklist] = player
            end
        end
    end
    
    -- No admins would be banned, we can now commit the ban and perform tempban
    -- checks to kick the users right away.    
    tempbans[#tempbans+1] = banentry
    for i,player in pairs(kicklist) do
        tempbancheck(player)
    end
    
    return true
end
--- Checks a player to see if they are supposed to be temporarily banned. If
-- so, they are immediately ejected from the server.
function tempbancheck(player)
    local ban = gettempbanfor(player.ip)
    if(ban ~= nil) then
        -- Player is banned
        local reasontext = ""
        if(ban.reason ~= nil) then reasontext = " ("..ban.reason..")" end
        local timeleft = ban.expires - os.time()
        -- Kick the player
        server.kick(player, string.format("%s%s, expires in %s", "You are temporarily banned", reasontext, timeperiod(timeleft)))
    end
end
--- Checks an IP to see if it is supposed to be temporarily banned. This 
-- function also prunes bans that have expired each time it is called.
-- @param ip the ip to check to see if banned (can be nil if you just want the bans list to be pruned)
-- @return the matching ban entry for the ip address, or nil if there is no ban for it
function gettempbanfor(ip) 
    local newbans = {}
    local returnban = nil
    
    for i,ban in pairs(tempbans) do
        -- Has this ban expired yet?
        if(ban.expires <= os.time()) then
            -- Ban has expired, skip it
        else
            -- Non-expired ban
            newbans[#newbans+1] = ban   
            if(ip ~= nil and returnban == nil and ipmaskmatch(ip, ban.ipmask)) then
                -- This ip is banned
                returnban = ban
            end 
        end
    end
    
    tempbans = newbans
    return returnban
end
--- Tests an IP address to see if it matches an IP mask, which can be a literal
-- IP address, a mask with IRC-style '*' and '?' wildcards, or a Lua pattern,
-- which starts with '^' (and includes it as part of the following pattern).
-- @param ip the ip address to test
-- @param ipmask the ip mask to test with
-- @return true if there is a match, false otherwise
function ipmaskmatch(ip, ipmask)
    if(string.match(ipmask, "^%^")) then -- Starts with ^
        return string.match(ip, ipmask) ~= nil
    else
        -- Look for */? wildcards
        if(string.match(ipmask, "[%*%?]")) then
            -- IRC-style mask -- turn into lua pattern
            ipmask = string.gsub(ipmask, "%*", ".*")
            ipmask = string.gsub(ipmask, "%?", ".")
            return string.match(ip, ipmask) ~= nil
        else
            -- Literal IP
            return ip == ipmask
        end
    end
end
--- Given an access level, this will print out all of the commands available
-- to a user of that access level in a relatively nice list, where commands
-- are grouped under the plugin they are located in.
-- @param accesslevel the minimum required access level to use for showing commands (example: access level 50 shows all commands requiring access level 50 and below)
-- @param helpprint a function that takes a string argument to print a single line of help as a reponse (it can take an optional second argument that is the shade of the text, see printlineclient())
-- @param helptype this is the string "full" for very verbose information, or "simple" for a basic command+usage list
function docommandhelp(accesslevel, helpprint, helptype)
    assert(accesslevel ~= nil, "accesslevel cannot be nil")
    assert(helpprint ~= nil, "helpprint cannot be nil")
    assert(helptype ~= nil, "helptype")
    assert(helptype == "full" or helptype == "simple", "unknown helptype " .. helptype)
    -- Get all the plugins with commands registered
    local pluginnames = {}
    for pluginname in pairs(plugincommands) do
        pluginnames[#pluginnames+1] = pluginname
    end
    table.sort(pluginnames)
    for i,pluginname in ipairs(pluginnames) do
        helpprint(pluginname .. " commands", 1)
        -- Build sorted list of commands
        local cmds = {}
        for i2,command in ipairs(plugincommands[pluginname]) do
            cmds[#cmds+1] = command
        end
        table.sort(cmds)
        for i2,command in ipairs(cmds) do
            local cmdinfo = commands[command]
            if(accesslevel >= cmdinfo.accesslevel) then 
                local aliases = cmdinfo.aliases    
                local extratext = ""
                if(#aliases > 0) then
                    if(#aliases == 1) then
                        extratext = extratext .. "[alias: "
                    else
                        extratext = extratext .. "[aliases: "
                    end
                    for i3,aliascmd in ipairs(aliases) do
                        extratext = extratext .. aliascmd
                        if(i3 < #aliases) then extratext = extratext .. ", " end
                    end
                    extratext = extratext .. "]"
                end
                if(helptype == "full") then
                    helpprint(string.format(" %s%-10s (%-3s) %s", getcommandprefix(), command, cmdinfo.accesslevel, extratext), 2)
                    if(cmdinfo.usage ~= nil) then
                        helpprint(string.format("  Argument(s): %s", cmdinfo.usage), 3)
                    end
                    helpprint(string.format("  %s", cmdinfo.infotext), 4)
                elseif(helptype == "simple") then
                    local usage = ""
                    if(cmdinfo.usage ~= nil) then usage = " " .. cmdinfo.usage end
                    helpprint(string.format(" %s%s%s", getcommandprefix(), command, usage), 2)
                end
            end
        end
    end
    helpprint("Use the page up and page down keys to scroll.")
end
--- Checks to see if a player is a user. If they are, they are automatically
-- told they are authenticated.
-- @param player the player to check
function checkifplayerisuser(player)
    assert(player ~= nil, "player cannot be nil")
    
    if(getplayeruserhandle(player) ~= nil) then
        return -- Player userhandle is already known
    end
    
    -- See if we can find a user that we know by this GBL ID
    for userhandle,userinfo in pairs(users) do
        if(userinfo.gblid == player.gblid) then
            -- Match!
            local authtable = getplayerauthtable(player)
            authtable.handle = userhandle
            server.printlineclient(1, player, "%s", "You have been recognized as user '"..userhandle.."' (global login ID matches)")
            return
        end
    end    
end
-----------------------
-- General execution --
-----------------------
-- Catch all chat to inspect for potential commands
addserverlistener(server.SE_CHAT, function(player, text, teamchat)
    if(player ~= nil) then
        -- Does this start with the command prefix?
        local prefix = getcommandprefix()
        if(#text >= #prefix+1 and string.sub(text, 1, #prefix) == prefix) then
            -- Extract command line part
            local commandline = string.sub(text, #prefix+1)
            local command,cmdargs = string.match(commandline, "^([^%s]+)(.-)%s*$") -- Discards trailing whitespaces
            if(command ~= nil) then
                local fullargs = string.match(cmdargs, "%s*(.*)$") -- Discards prefixed whitespaces
                
                if(fullargs ~= nil) then
                    -- It's a command!
                    return processplayercommand(player, command, fullargs)   
                end             
            end
        end
    end
end)


---------------
-- Listeners --
---------------
addserverlistener(server.SE_ENTER, function(player)
    -- Greets players
    if(player == nil) then return end
    local p = getcommandprefix()
    local n = 0
    local welcomefunc 
    welcomefunc = function()
        n = n + 1
        if(n >= 75) then -- TODO: if you add a timer system, this should use it
            if(not player.discarded) then
                server.printlineclient(1, player, "%s", "This server is running IronMod, use "..p.."commands or "..p.."help to see available commands")
            end
            listen.unreg(welcomefunc)
        end
    end    
    listen.game.postcall(GE_RUNFRAME, welcomefunc)
end)
listen.game.precall(GE_SERVERCOMMAND, function(data)
    -- Allows commands to be input from console
    local cmdargs = server.getcommandargs()
    if(#cmdargs >= 2) then
        if(cmdargs[2] == "admin") then
            if(#cmdargs >= 3) then
                local admincmd = cmdargs[3]
                local admincommandargs = ""
                for i=4,#cmdargs do -- Concatenate them all together
                    admincommandargs = admincommandargs .. cmdargs[i]
                    if(i < #cmdargs) then admincommandargs = admincommandargs .. " " end
                end
                local commandinfo = getcommandinfo(admincmd)
                if(commandinfo ~= nil) then      
                    if(commandinfo.consoleusable) then
                        -- Prepare reply function
                        local replyfunc = function(text, shade)
                            print(text)
                        end            
                        if(commandinfo.accesslevel >= config.LOG_MINLEVEL) then log("[CONSOLE] '" .. admincmd .. "' '" .. admincommandargs .. "'") end      
                        -- Call the handler            
                        commandinfo.handler(admincommandargs, math.huge, player, replyfunc, commandinfo)  
                    else
                        print("This command is not usable via the console.")
                    end 
                else
                    -- This is an unknown command
                    print("Unknown command '"..tostring(admincmd).. "'")
                    --return true
                 end
            else
                print("You need to include a command to execute. Usage: 'sv admin <command>'")
            end
            return intercept.DO_DROP
        end
    end
end)
addserverlistener(server.SE_PRECONNECT, function(ent, ip, port, userinfo)
    local ban = gettempbanfor(ip)
    if(ban ~= nil) then
        -- IP address is banned, block the user
        local reasontext = ""
        if(ban.reason ~= nil) then reasontext = " ("..ban.reason..")" end
        local timeleft = ban.expires - os.time()
        local blockreason = string.format("%s%s, expires in %s", "Tempbanned", reasontext, timeperiod(timeleft))
        return true, blockreason
    end
end)
addserverlistener(server.SE_RESOLVED_GBLID, function(player)
    checkifplayerisuser(player)
end)

-- Export ourself as global variable 'administration'
_G.administration = package.loaded.plugin_administration
assert(administration ~= nil, "it looks like you changed the administration plugin name without fixing this code!")

-- Load users configuration file
loadusers()

-- Add our own commands
addcommand = administration.getcommandregisterfunc(package.loaded.plugin_administration)
addcommand("help", 0, administration.CMDTYPE_SILENT, true, nil, "Displays this help", function(text, sourcelevel, player, replyfunc, cmdinfo)
    local accesslevel = MAX_ACCESS
    if(player ~= nil) then
        accesslevel = getplayeraccess(player)
    end
    administration.docommandhelp(accesslevel, replyfunc, "full")
end)
addcommand("commands", 0, administration.CMDTYPE_SILENT, true, nil, "Displays simple commands list", function(text, sourcelevel, player, replyfunc, cmdinfo)
    local accesslevel = MAX_ACCESS
    if(player ~= nil) then
        accesslevel = getplayeraccess(player)
    end
    administration.docommandhelp(accesslevel, replyfunc, "simple")
end)
addcommand("access", 0, administration.CMDTYPE_SILENT, false, "[userhandle]", "Shows your access level or another user's access level", function(text, sourcelevel, player, replyfunc, cmdinfo)
    if(#text>0) then -- User handle arg
        local handle = string.lower(text)
        if(userexists(handle)) then
            local useraccess = getuseraccess(handle)
            replyfunc(handle.." has access level "..useraccess.." ("..getaccessname(useraccess)..")")
        else    
            replyfunc("No such user handle '"..handle.."'")
        end
    else -- No args
        local handle = getplayeruserhandle(player)
        local loginstatus = ""
        if(handle ~= nil) then
            loginstatus = "you are recognized as user '" .. handle .. "'"
        else
            loginstatus = "you are not a recognized server user"
        end
        local accesslevel = getplayeraccess(player)
        replyfunc("You have access level "..accesslevel.." ("..getaccessname(accesslevel)..") - "..loginstatus)
    end
end)
addcommandalias("a", "access")
addcommand("version", 0, administration.CMDTYPE_SILENT, true, nil, "Shows ironmod's version", function(text, sourcelevel, player, replyfunc, cmdinfo)
    replyfunc(util.GetIronModVersion())
end)
addcommand("players", 0, administration.CMDTYPE_SILENT, true, nil, "Shows player information", function(text, sourcelevel, player, replyfunc, cmdinfo)
    if(server.playercount == 0) then
        replyfunc("No players.")
        return
    end
    local performerplayer = player
    
    local formatstr = "%-2s\\%-10s\\%-6s\\%-7s\\%s" -- PlayerNum,Name,GBLID,UserHandle,IP
    replyfunc(string.format(formatstr, "#", "Name", "GBLID", "Handle", "IP"), 1)
    for i,player in pairs(server.players) do
        local playeraccess = getplayeraccess(player)
        local playerhandle = getplayeruserhandle(player)
        local playergblid = player.gblid
        if(playerhandle ~= nil and getusersettings(playerhandle).cloak) then
            -- This is a cloaked user, don't show their handle to other players
            playerhandle = "*"
        end
        if(playerhandle == nil) then playerhandle = "*" end
        if(playergblid == nil) then playergblid = "*" end
        debug(performerplayer, player)
        local hideaddress = (performerplayer ~= player) and (playeraccess >= sourcelevel) -- Hides the address of players with as much or more access as the requesting players
        debug(hideaddress)
        if(not hideaddress) then
            replyfunc(string.format(formatstr, player.num, server.stripgarbage(player.name), playergblid, playerhandle, player.ip), 2)
        else
            replyfunc(string.format(formatstr, player.num, server.stripgarbage(player.name), playergblid, playerhandle, "*"), 2)
        end
    end
end)
addcommand("tempban", 200, administration.CMDTYPE_SILENT, true, "<playernum> <length> [reason]", "Temporarily bans a player from the server", function(text, sourcelevel, player, replyfunc, cmdinfo)
    local sourcename = "Console"
    if(player ~= nil) then sourcename = "user:"..getplayeruserhandle(player) end
    
    local playernum,length,reason = string.match(text, "^([0-9]+) ([dhms0-9]+)%s*(.-)%s*$")
    if(playernum ~= nil) then
        -- Parse information and validate it
        local player_num = tonumber(playernum)
        local player_banlength,err = parsetimeperiod(length)
        if(player_banlength == nil) then
            -- Couldn't parse ban length
            replyfunc("failed: unable to parse ban length '"..length.."': "..tostring(err))
            return
        end
        local player_banreason = nil
        if(#reason > 0) then player_banreason = reason end
        
        -- Try to get the player
        local player = server.getplayerbynum(player_num)
        if(player == nil) then
            -- No such player
            replyfunc("failed: no such player with player number "..player_num)
            return
        end        
        local player_banip = player.ip
        local player_name = player.name
        
        -- Try to ban them
        local success,err = tempban(sourcename, player_banip, player_banlength, player_banreason, player.name) 
        if(not success) then
            replyfunc("failed: unable to apply ban: "..tostring(err))
        else
            replyfunc("Successfully tempbanned player '"..server.stripgarbage(player_name).."' ("..player_banip..") for "..timeperiod(player_banlength))
        end
    else
        replyfunc("Wrong arguments. Usage: " .. cmdinfo.usage)
    end 
end)
addcommandalias("tb", "tempban")
addcommand("tempbanip", 200, administration.CMDTYPE_SILENT, true, "<ipmask> <length> [reason]", "Temporarily bans an IP from the server", function(text, sourcelevel, player, replyfunc, cmdinfo)
    local sourcename = "Console"
    if(player ~= nil) then sourcename = "user:"..getplayeruserhandle(player) end
    
    local ipmask,length,reason = string.match(text, "^(.-) ([dhms0-9]+)%s*(.-)%s*$")
    if(ipmask ~= nil) then
        -- Parse information and validate it
        local banlength,err = parsetimeperiod(length)
        if(banlength == nil) then
            -- Couldn't parse ban length
            replyfunc("failed: unable to parse ban length '"..length.."': "..tostring(err))
            return
        end
        local banreason = nil
        if(#reason > 0) then banreason = reason end
        
        -- Try to ban them
        local success,err = tempban(sourcename, ipmask, banlength, banreason, nil) 
        if(not success) then
            replyfunc("failed: unable to apply ban: "..tostring(err))
        else
            replyfunc("Successfully tempbanned IP mask '"..ipmask.."' for "..timeperiod(banlength))
        end
    else
        replyfunc("Wrong arguments. Usage: " .. cmdinfo.usage)
    end 
end)
addcommandalias("tbip", "tempbanip")
addcommand("tempbans", 200, administration.CMDTYPE_SILENT, true, nil, "Displays all tempbans", function(text, sourcelevel, player, replyfunc, cmdinfo)
    if(#tempbans == 0) then
        replyfunc("No temporary bans.")
        return 
    end
    gettempbanfor(nil) -- Forces expired bans to be purged
    for i,ban in ipairs(tempbans) do
        local timelefttxt = timeperiod(ban.expires - os.time())
        replyfunc("IP Mask: " .. ban.ipmask, 1)
        if(ban.name ~= nil) then
            replyfunc("  Name: " .. ban.name, 2)
        end
        replyfunc("  Length: " .. timeperiod(ban.length), 2)
        replyfunc("  Expires in: " .. timelefttxt, 2)
        replyfunc("  Banned by: " .. ban.source, 2)
        if(ban.reason ~= nil) then
            replyfunc("  Reason: " .. ban.reason, 2)
        end
    end
    replyfunc(#tempbans .. " ban(s) listed.", 3)
end)
addcommand("deltempban", 200, administration.CMDTYPE_SILENT, true, "<player name or exact ip mask>", "Removes one or more tempbans", function(text, sourcelevel, player, replyfunc, cmdinfo)
    if(#tempbans == 0) then
        replyfunc("No temporary bans; nothing to remove.")
        return 
    end
    gettempbanfor(nil) -- Forces expired bans to be purged
    
    local searchfor = text
    if(#searchfor > 0) then
        local newbans = {}
        local removedban = false -- Will be set to true if at least one ban is removed
        for i,ban in ipairs(tempbans) do
            if((ban.name ~= nil and ban.name == searchfor) or ban.ipmask == searchfor) then
                -- Found the ban, let it not be re-added to the list
                replyfunc("Removed ban '" .. ban.ipmask .. "'")
                removedban = true
            else
                newbans[#newbans] = ban
            end
        end
        if(not removedban) then
            replyfunc("No bans matching your removal criteria.")
        end
        tempbans = newbans
    else
        replyfunc("Wrong arguments. Usage: " .. cmdinfo.usage)
    end
end)
addcommandalias("dtb", "deltempban")
addcommand("adduser", 300, administration.CMDTYPE_SILENT, true, "<userhandle> <access>", "Adds a server user", function(text, sourcelevel, player, replyfunc, cmdinfo)
    local performeraccess = sourcelevel
    
    local handle,accesslevel = string.match(text, "(.+) ([0-9]+)")
    if(handle ~= nil) then
        handle = string.lower(handle)
        if(not userexists(handle)) then
            accesslevel = tonumber(accesslevel)
            if(performeraccess > accesslevel) then
                -- Performer has access level higher than the one they want to add
                local success,err = adduser(handle, {access=accesslevel})
                if(success) then
                    replyfunc("Successfully added new user '"..handle.."'")
                else
                    replyfunc("Failed to add user: " .. tostring(err))
                end            
            else
                replyfunc("You cannot add a user with as much or more access than you have")
            end
        else
            replyfunc("A user with that handle already exists")
        end
    else
        replyfunc("Wrong arguments. Usage: " .. cmdinfo.usage)
    end
end)
addcommand("deluser", 300, administration.CMDTYPE_SILENT, true, "<userhandle> <access>", "Adds a server user", function(text, sourcelevel, player, replyfunc, cmdinfo)
    local performeraccess = sourcelevel
    
    local handle = text
    if(#handle > 0) then
        handle = string.lower(handle)
        if(userexists(handle)) then
            if(performeraccess > getuseraccess(handle)) then
                -- Performer has access level higher than the one they want to remove
                local success,err = removeuser(handle)
                if(success) then
                    replyfunc("Successfully removed user '"..handle.."'")
                else
                    replyfunc("Failed to remove user: " .. tostring(err))
                end            
            else
                replyfunc("You cannot delete a user with as much or more access than you have")
            end
        else
            replyfunc("No such user for handle '"..handle.."'")
        end
    else
        replyfunc("Wrong arguments. Usage: " .. cmdinfo.usage)
    end
end)
addcommand("users", 0, administration.CMDTYPE_SILENT, true, nil, "Shows server users", function(text, sourcelevel, player, replyfunc, cmdinfo)
    if(not pairs(users)) then
        replyfunc("No users.")
        return 
    end
    replyfunc(string.format("%-15s %s", "User handle", "Access"), 1)
    replyfunc(string.format("%-15s %s", "-----------", "------"), 1)
    for userhandle,userinfo in pairs(users) do
        if(not userinfo.cloak) then
            replyfunc(string.format("%-15s %s", userhandle, userinfo.access), 2)
        end
    end
end)
addcommand("usersettings", 400, administration.CMDTYPE_SILENT, true, nil, "Displays users and their settings", function(text, sourcelevel, player, replyfunc, cmdinfo)
    if(not pairs(users)) then
        replyfunc("No users.")
        return 
    end
    replyfunc(string.format("%-15s %s", "User handle", "Settings"), 1)
    replyfunc(string.format("%-15s %s", "-----------", "--------"), 1)
    for userhandle,userinfo in pairs(users) do
        local settingstext = ""
        for key,val in pairs(userinfo) do
            settingstext = settingstext..key.."='"..tostring(val).."' "            
        end
        replyfunc(string.format("%-15s %s", userhandle, settingstext), 2)
    end
end)
addcommand("clvl", 300, administration.CMDTYPE_SILENT, true, "<user handle> <new access level>", "Changes a user's access level", function(text, sourcelevel, player, replyfunc, cmdinfo)
    local performeraccess = sourcelevel
    local playerhandle = nil
    if(player ~= nil) then
        playerhandle = getplayeruserhandle(player)
    end
    
    local handle,newaccess = string.match(text, "([^%s]+) ([0-9]+)")
    if(handle ~= nil) then
        handle = string.lower(handle)
        newaccess = tonumber(newaccess)
        if(handle == playerhandle) then
            if(performeraccess < config.SELFSETLEVEL) then
                replyfunc("You cannot change your own access level")
                return
            else
                -- Go on, it's fine
            end
        else
            if(performeraccess == newaccess) then
                replyfunc("You cannot change the access of someone with the same access level as you")
                return
            elseif(performeraccess < newaccess) then
                replyfunc("You cannot change the access of someone with an access level higher than yours")
                return
            end
        end
        
        -- We're good
        local success,err = setusersettings(handle, {access=newaccess})
        if(success) then
            replyfunc("Changed access level for '"..handle.."' to "..newaccess)
            if(newaccess > MAX_ACCESS) then replyfunc("warning: the maximum access level is supposed to be "..MAX_ACCESS.."...") end
        else
            replyfunc("failure: "..tostring(err))
        end
    else
        replyfunc("Wrong arguments. Usage: " .. cmdinfo.usage)
    end
end)
addcommand("userset", 300, administration.CMDTYPE_SILENT, true, "<user handle> <setting> [value]", "Sets a user setting", function(text, sourcelevel, player, replyfunc, cmdinfo)
    local performeraccess = sourcelevel
    local playerhandle = nil
    if(player ~= nil) then
        playerhandle = getplayeruserhandle(player)
    end
    
    local handle,setting,value = string.match(text, "([^%s]+) ([^%s]+)(.*)")
    if(handle ~= nil) then
        handle = string.lower(handle)
        if(#value > 1) then
            value = string.sub(value, 2)
        else
            value = nil
        end
        if(userexists(handle)) then
            if(playerhandle == handle) then
                -- Trying to change own settings
                if(performeraccess < config.SELFSETLEVEL) then
                    replyfunc("You cannot change your own settings unless you have access level "..config.SELFSETLEVEL)
                    return
                else
                    -- Go on, it's fine
                end
            else 
                if(performeraccess == getuseraccess(handle)) then
                    replyfunc("You cannot change user settings for someone with the same access as you")
                    return
                elseif(performeraccess < getuseraccess(handle)) then
                    replyfunc("You cannot change user settings for someone with more access than you")
                    return
                end
            end
            setting = string.lower(setting)
            local validsettings = ""
            local isvalid = false
            for i,validsetting in ipairs(VALIDSETTINGS) do
                if(validsetting == setting) then
                    isvalid = true
                    break
                end
                validsettings = validsettings .. validsetting
                if(i < #VALIDSETTINGS) then validsettings = validsettings .. ", " end
            end
            
            if(isvalid) then
                local usersettings = getusersettings(handle)
                if(value ~= nil) then
                    -- User wants to set a setting
                    if(setting == "gblid") then -- string
                        usersettings[setting] = value
                    elseif(setting == "access") then -- number
                        local numval = string.match(value, "%s*([0-9]+)%s*")
                        if(numval == nil) then
                            replyfunc("failure: value '"..value.."' is not a number")
                            return
                        end
                        usersettings[setting] = tonumber(numval)
                    elseif(setting == "cloak") then -- boolean
                        if(value == "true") then
                            usersettings[setting] = true
                        elseif(value == "false") then
                            usersettings[setting] = false
                        else
                            replyfunc("failure: value should be 'true' or 'false'")
                            return
                        end
                    else -- unknown
                        replyfunc("fatal error: VALIDSETTINGS handling mismatch -- please report this error!")
                        return
                    end
                    -- If we got this far, it was successfully set
                    saveusers()
                    -- The setting may have made someone currently in the server into a user...
                    for i,player in pairs(server.players) do
                        checkifplayerisuser(player)
                    end
                    replyfunc("Setting '"..setting.."' saved for user.")
                else
                    -- User wants to remove a setting
                    if(usersettings[setting] ~= nil) then
                        usersettings[setting] = nil
                        saveusers()
                        replyfunc("Setting '"..setting.."' removed from user.")
                    else
                        replyfunc("The setting '"..setting.."' has no value for this user. Cannot unset it.")
                    end
                end
            else
                replyfunc("Invalid setting '"..setting.."'. Valid settings are: "..validsettings)
            end
        else
            replyfunc("No such user handle '"..handle.."'")
        end
    else
        replyfunc("Wrong arguments. Usage: " .. cmdinfo.usage)
    end
end)
addcommand("luastats", 400, administration.CMDTYPE_SILENT, true, nil, "Displays Lua stats for this session", function(text, sourcelevel, player, replyfunc, cmdinfo)
    local usedmem_kb = collectgarbage("count")
    local usedmem_mb = usedmem_kb / 1024
    replyfunc(string.format("%.2fKiB (%.2fMiB) of memory in use by Lua", usedmem_kb, usedmem_mb))
    local plugs = {}
    for name,module in pairs(package.loaded) do
        if(name:match("^plugin_.*$")) then 
            plugs[#plugs+1] = module
        end
    end
    replyfunc(#plugs .. " plugins loaded:")
    for i,plugin in ipairs(plugs) do
        replyfunc("  "..plugin.info.name..", listener counts:", 2)
        for listentype,listencount in pairs(plugin.listenercounts) do
            replyfunc("    "..listentype.."="..listencount, 3)
        end
        
    end
end)
addcommand("luagc", 400, administration.CMDTYPE_SILENT, true, nil, "Forces a Lua garbage-collection cycle", function(text, sourcelevel, player, replyfunc, cmdinfo)
    collectgarbage("collect")
    replyfunc("Garbage collection complete")
end)
addcommand("luaplugins", 400, administration.CMDTYPE_SILENT, true, nil, "Shows all loaded plugins", function(text, sourcelevel, player, replyfunc, cmdinfo)
    for name,module in pairs(package.loaded) do
        if(name:match("^plugin_.*$")) then 
            local plugin = module
            replyfunc(tostring(plugin.info.name)..", by '"..tostring(plugin.info.author).."', version '"..tostring(plugin.info.version).."'")
            replyfunc(plugin.info.description, 2)
        end
    end
end)

-- Set up logging
if(config.LOG_ENABLED) then
    local logfile = plugpath..config.LOG_FILE
    loghandle,errmsg = io.open(logfile, "a+b")
    if(loghandle ~= nil) then
        print("Successfully opened log file: " .. logfile)
        log("[START] *********************************")
        log("[START] Session start at " .. os.date())
    else
        error("Could not open log file '"..logfile.."': " .. errmsg)
    end
end
