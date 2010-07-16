-- This is IronMod's standard server plugin. It exports the global variable "server" as an alias to itself.
-- The functionality provided here should make it easier to track game information (players, scores, etc.),
-- and perform common server tasks.
--
-- This MUST be loaded before all other plugins. It should also start out as the first listener for
-- every event. However, other plugins still have the ability to mess up state tracking by forcing
-- themselves to receive events before this plugin, and dropping them immediately. 
module("plugin_sdebug", package.seeall)
require("socket") -- luasocket
require("asok") -- ztact asynchronous socket

-- Required code
info = {
    name = "sdebug",  
    description = "core server plugin (server interface)",    
    author = "iron",
    version = "1.0",
}
registerplugin(package.loaded.plugin_sdebug)
-- End required code

----------------------
-- Global variables --
----------------------
--- Contains a table of the NON-BOT players on the server. Remember, a player can remain in the server through GE_SPAWNENTITIES (ie: people connected will stay connected when the map changes).
-- Key is an internal unique value (do not rely on it for anything). Each value is a player with a table containing the following information:
-- "info",          a table containing the client's userinfo (WARNING: do NOT trust any of this information, it is merely stuff the client is sending to us as a suggestion, it's not what may actually be in use; you can't trust name, skin, or IP information found here)
-- "ent",           an edict_* reference
-- "ingame",        a value that is false until the GE_CLIENTBEGIN call is made
-- "discarded"      a value that is false until the player is removed from the server (usually due to them disconnecting), after which it becomes true, meaning this player information is no longer valid
-- "starttime",     the time yielded by os.time() when the player first connected (GE_CLIENTCONNECT)
-- "plugindata",    a table where plugins can store information (please store your information in a table named after your plugin to avoid collisions)
-- "num",           a client index used by both the server and connected clients to uniquely identify this player (it is the same number that is used for server KICK/STATUS commands)
-- "teamindex",     corresponds to the TEAM_* constants which yield the team the player is currently on
-- "name",          the player's current name as known by the server
-- "skin",          their current player skin as known by the server
-- "flags",         the number of enemy flags this player is currently holding
-- "grabs",         the number of flag grabs this player has made (note: players can jack this number up by dropping the flag and picking it up again)
-- "holds",         the number of actual grabs this player has made and kept (if a player grabs a flag, their flag holds goes up by one, but if they drop it, it goes back down by one)
-- "caps",          the number of successful flag captures this player has made (note that this is the actual number of flag captures, so a player that has 2 flags and captures them gets two flag captures registered here)
-- "alive",         true if this player is alive, false otherwise
-- "kills",         the number of kills the player has this session
-- "deaths",        the number of deaths the player has this session
-- "streak",        the current number of kills the player has made in a row without dying
-- "gblid",         this player's digital paint global login id number (GLS userid). It is nil if the player is not logged in or we have not been able to retrieve it yet. Please be aware that once we find the player's ID, it is never checked again (it is possible that a player can log in to a different account while in the server but you will have the "old" gblid -- this is a very rare case). This is suitable for client identity verification for administration/statistics, etc.
-- "ip",            the ip address of the player
-- "port",          the udp port number of the player
players = {}
--- Holds the current number of NON-BOT players on the server. This is essential, as there is no trivial constant-time way to obtain the player count from the players table.
playercount = 0
--- Holds a copy of the current configstrings that we've seen used so far. This is ONLY the configstrings the game has set with GIDP_CONFIGSTRING, or those set using the function provided here. Unfortunately, it does not have the ones internal to the actual DP server.
configstrings = {} -- TODO: does this need to be reset at any time? same for sounds, models, etc.
--- Holds sound index to sound pathname information. This information is not in our stored configstrings.
sounds = {}
--- Holds model index to model pathname information. This information is not in our stored configstrings.
models = {}
--- Holds event listeners called by this plugin. eventlisteners[eventid][listenerindex].(plugin or handler)
eventlisteners = {}
--- This is used for spoofcommandargs()
local spoofing_commandargs = false
--- The IP address of the global login server. If it is unknown, this value is nil.
GBL_SERVERIP = nil
-- TODO/NOTE: I believe some of the following events can still be caused by a bot, you may want to either revise and put in more warnings and remove some player ~= nil assertions in the event handling code
--- A constant for the event emitted when a player enters the server. Your handler function should take the following parameters:
-- player, a player reference (see 'players')
-- text, a human-friendly text string for this event
SE_ENTER = 1
--- A constant for the event emitted when a player exits the server. Your handler function should take the following parameters:
-- player, a player reference (see 'players') 
-- text, a human-friendly text string for this event
SE_DISCONNECT = 2
--- A constant for the event emitted when a player joins a team (although, this is not called after SE_ENTER, as SE_ENTER itself should have the team set there). Your handler function should take the following parameters:
-- player, a player reference (see 'players')
-- oldteamindex, the team the player was previously on
-- text, a human-friendly text string for this event
SE_JOINTEAM = 3
--- A constant for the event emitted when the round ends. Your handler function should take the following parameters:
-- teamindex, the team that won (remember, it may be TEAM_NONE for ties)
-- text, a human-friendly text string for this event
SE_ROUNDOVER = 4
--- A constant for the event emitted when the game goes into overtime. Your handler function should take the following parameter:
-- text, a human-friendly text string for this event
SE_OVERTIME = 5
--- A constant for the event emitted when the round begins. Your handler function should take the following parameter:
-- text, a human-friendly text string for this event
SE_ROUNDSTART = 6
--- A constant for the event emitted when a player is killed by the admin (slayed). Your handler function should take the following parameters:
-- player, the player reference for the player that was slayed (see 'players')
-- adminplayer, the player reference for the admin that did the slaying, MAY BE NIL IF THE ADMIN IS UNKNOWN (see 'players')
-- text, a human-friendly text string for this event
SE_ADMINKILL = 7
--- A constant for the event emitted when a player kills a member of the opposite team. Your handler function should take the following parameters:
-- killerplayer, the player reference for the player that did the killing (MAY BE NIL IF THIS IS A BOT)
-- killerwepindex, the item index which was used as the killing weapon (see getitem())
-- victimplayer, the player reference for the player that was killed (MAY BE NIL IF THIS IS A BOT)
-- victimwepindex, the item index which was the victim's held weapon (see getitem())
-- text, a human-friendly text string for this event
SE_KILL = 8
--- A constant for the event emitted when a player kills themself (getting hit by their own paint grenade, falling into lava/paint, drowning).
-- Your handler function should take the following parameters:
-- player, the player reference for the player that suicided (MAY BE NIL IF THIS IS A BOT)
-- text, a human-friendly text string for this event
SE_SUICIDE = 9
--- A constant for the event emitted when a player kills their teammate. Your handler function should take the following parameters:
-- killerplayer, the player reference for the player that killed their teammate (MAY BE NIL IF THIS IS A BOT)
-- victimplayer, the player reference for the player that was teamkilled (MAY BE NIL IF THIS IS A BOT)
-- text, a human-friendly text string for this event
SE_FFIRE = 10
-- TODO: is what you say below true?
--- A constant for the event emitted when a player respawns. This only happens for regular respawns, not for the start of the round. Your handler function should take the following parameters:
-- player, the player reference for the player that just respawned (MAY BE NIL IF THIS IS A BOT)
-- text, a human-friendly text string for this event
SE_RESPAWN = 11
--- A constant for the event emitted when a player grabs a flag. Your handler function should take the following parameters:
-- player, the player reference for the player that just grabbed a flag (MAY BE NIL IF THIS IS A BOT)
-- text, a human-friendly text string for this event
SE_FLAGGRAB = 12
--- A constant for the event emitted when a player drops all of their flag(s). Your handler function should take the following parameters:
-- player, the player reference for the player that just dropped a flag (MAY BE NIL IF THIS IS A BOT)
-- text, a human-friendly text string for this event
SE_FLAGDROP = 13 
--- A constant for the event emitted when a player captures the opposing team's flag(s). Your handler function should take the following parameters:
-- player, the player reference for the player that just captured a flag (or multiple flags) (MAY BE NIL IF THIS IS A BOT)
-- text, a human-friendly text string for this event
SE_FLAGCAP = 14
--- A constant for the event emitted when a player chats. Your handler function should take the following parameters:
-- player, the player reference for the player that is trying to chat (MAY BE NIL IF THIS IS A BOT)
-- text, the text they want to send
-- teamchat, true if they are trying to chat to their team, or false if they are chatting to everyone
-- Your handler function can optionally return true to block the chat (or false/nil if you do not want to block the chat).
SE_CHAT = 15
--- A constant for the event emitted when a new map is just about to load. Your handler function should take the following parameter:
-- mapname, the name of the map which is now being played
SE_MAPCHANGE = 16
--- A constant for the event emitted when a player's GBL ID has been found. Note that a player's GBL ID is only resolved once.
-- After the ID has been discovered, it is kept until they disconnect. 
-- Your handler function should take the following parameters:
-- player, the player reference for the player that now has a non-nil "gblid" field (this player is never nil)
SE_RESOLVED_GBLID = 17
--- A constant for the event emitted when a player first connects to the server. It is emitted before a player reference is even made, 
-- and is here solely for you to deny a client entrance to the server. Your handler function should take the following parameters:
-- ent, the player entity pointer
-- ip, the IP address of the connecting player
-- port, the port number of the connecting player
-- userinfo, a table of the key-value pairs found in the client's userinfo they sent
-- Your handler function should return true to block the player (it may include an optional second argument with a string reason), or false/nil to allow the player into the server (note that the first handler function which blocks a player is acted upon, although you'll still get this event after the block, even though your return value would be meaningless)
SE_PRECONNECT = 18
--- A constant for the event emitted when a player successfully changes their name. 
-- player, the player who changed their name successfully
-- oldname, the name the player previously had
SE_NAMECHANGE = 19
-- Note: all these team colors are derived from splat()/cl_scores_get_team_textcolor() in cl_scores.c -- that said, I have expanded on it a bit
--- A constant indicating the red team. 
TEAM_RED = 1
--- A constant with the text color code (as a character for rendering) you can use to get the red team's desired representative color. -- TODO: verify it works
TEAM_RED_COLOR = util.int_to_char(158)
--- A constant indicating the blue team.
TEAM_BLUE = 2
--- A constant with the text color code (as a character for rendering) you can use to get the blue team's desired representative color. 
TEAM_BLUE_COLOR = util.int_to_char(159)
--- A constant indicating the purple team. 
TEAM_PURPLE = 3
--- A constant with the text color code (as a character for rendering) you can use to get the purple team's desired representative color. 
TEAM_PURPLE_COLOR = util.int_to_char(141)
--- A constant indicating the yellow team. 
TEAM_YELLOW = 4
--- A constant with the text color code (as a character for rendering) you can use to get the yellow team's desired representative color. 
TEAM_YELLOW_COLOR = util.int_to_char(140)
--- A constant indicating an absence of a team -- this may be observer (it *should* always be)
TEAM_NONE = -1
--- A constant with the text color code (as a character for rendering) you can use to get the default team color code 
TEAM_NONE_COLOR = qshared.COLOR_CHAT
--- Holds the latest player num we've seen come across the configstrings. The configstring (CS_PLAYERSKINS) comes before the connect and a few times afterward, so this should hopefully be okay). -- TODO: what happens with very concurrent connections? should be fine I think...
local player_num_cache
--- Holds the latest player name we've seen come across the configstrings. 
local player_name_cache
--- Holds the latest player skin we've seen come across the configstrings. 
local player_skin_cache
--- Maps 8-bit characters that DP provides into human-friendly 7-bit ASCII.
-- To do this, access the character location with the character code you want
-- to convert, but use index-1 since Lua bases indexes at 1.
local char_remap = {
    "\0","-", "-", "-", "_", "*", "t", ".", "N", "-", "\n","#", ".", ">", "*", "*",
	"[", "]", "@", "@", "@", "@", "@", "@", "<", ">", ".", "-", "*", "-", "-", "-",
	" ", "!", "\"","#", "$", "%", "&", "\"","(", ")", "*", "+", ",", "-", ".", "/",
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?",
	"@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O",
	"P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\","]", "^", "_",
	"`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o",
	"p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~", "<",
	"(", "=", ")", "^", "!", "O", "U", "I", "C", "C", "R", "#", "?", ">", "*", "*",
	"[", "]", "@", "@", "@", "@", "@", "@", "<", ">", "*", "X", "*", "-", "-", "-",
	" ", "!", "\"","#", "$", "%", "&", "\"","(", ")", "*", "+", ",", "-", ".", "/",
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?",
	"@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O",
	"P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\","]", "^", "_",
	"`", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O",
	"P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "{", "|", "}", "~", "<"
}
--- Used as the return value for doing SE_PRECONNECT.
local ptr_preconnect_returnval_blockplayer = util.allocate_qboolean(0) -- WARN: This is never deallocated, but there is currently no reason why this plugin should ever be unloaded
--- Used for SE_CHAT to catch people chatting via the console
local chatprintflistener = nil
--- Used to store a player ent which is likely to be getting all EVENT_s,
-- used by getarbitraryplayerent()
local eventplayerent = nil

-- Export ourself as global variable 'server'
_G.server = package.loaded.plugin_sdebug
assert(server ~= nil, "it looks like you changed the server's plugin name without fixing this code!")

----------------------
-- Helper functions --
----------------------
--- Takes a userinfo string and parses it, returning a table of the key-value pairs from the string.
-- @param userinfo the string to parse
-- @return a table of the userinfo key-value pairs
function parseuserinfo(userinfo)
    assert(userinfo~=nil, "userinfo must not be nil")
    local t = {}
    for key, val in string.gmatch(userinfo, "\\(%w+)\\([^\\]*)") do
       t[key] = val
    end
    return t
end
--- Translates a table of key-value pairs into a userinfo string.
-- @param userinfo the table to build userinfo from
-- @return a string encoded with userinfo
function createuserinfo(userinfo)
    assert(userinfo~=nil, "userinfo must not be nil")
    local t = {}
    local str = ""
    for key, val in pairs(userinfo) do
        str = "\\" .. key .. "\\" .. val
    end
    return str
end
--- Returns a unique hash for a player ent pointer.
-- @param ent the entity pointer for the player
-- @return a unique hash string for this player
local function hashplayerent(ent)
    assert(ent ~= nil, "ent must not be nil")
    local num = util.get_ptr_as_int(ent) -- use the memory location of the ent
    return "X" .. num
end
--- Removes a player by ent. See getplayerbyent()
function removeplayerbyent(ent) 
    assert(ent ~= nil, "ent must not be nil")
    local uid = hashplayerent(ent)
    -- Mark the player as discarded
    players[uid].discarded = true
    -- See if this is our event-handling player -- if so, we need to get a new
    -- player (TODO: WARN: if the event-handling player disconnects, but another player is there, does the event-handling player get their own disconnect? if not, you need to work on that...)
    if(ent == eventplayerent) then
        eventplayerent = nil
        -- Find a player in the game
        for i,player in pairs(players) do
            if(player.ingame) then 
                eventplayerent = player.ent 
                break
            end
        end
        if(eventplayerent == nil) then
            -- No players in the game, so pick the one that has been here longest
            local mintime = nil
            local minplayer = nil
            for i,player in pairs(players) do
                if(mintime == nil or player.starttime < mintime) then
                    minplayer = player
                    mintime = player.starttime
                end
            end
            eventplayerent = minplayer.ent
            -- Note: if eventplayerent is still nil, it just means there were no players in the game
        end
    end
           
    -- Handle net stuff
    local netsettings = net_getplayertable(players[uid])
    -- TODO/WARN: If this ever fails to execute for a player that leaves, I believe the player message queues will get polled way more often than they should
    net_remainingmessages = net_remainingmessages - #netsettings.msgqueue
    
    players[uid] = nil
    playercount = playercount - 1
end
--- Returns an arbitrary human player entity for situations where we
-- might need it, such as for playing sound. This ensures that the
-- client is in the game (has entered). Connecting clients won't be returned.
-- @return a player's entity pointer or nil if no players for use on the server
local function getarbitraryplayerent()
    return eventplayerent
end
--- Handles a plugin being unregistered for which we are currently serving events.
-- @param plugin the plugin being unregistered
local function pluginunregisterhandler(plugin)
    unregisterlisteners(plugin)
end
--- Propagates an event.
-- @param eventid the event ID (see SE_ constants) to propagate
-- @param propfunc a function which will receive each event handler as its only parameter so that it may invoke the event on that handler function
local function emitevent(eventid, propfunc) 
    if(eventlisteners[eventid] ~= nil) then
        for i,listener in ipairs(eventlisteners[eventid]) do
            propfunc(listener.handler)
        end
    end
end
--- Tests two edict_t to see if they are the same (in same memory location).
-- @param ent1 the first edict
-- @param ent2 the second edict
-- @return true if the entities are the same
local function sameedicts(ent1, ent2) 
    assert(ent1 ~= nil, "ent1 cannot be nil")
    assert(ent2 ~= nil, "ent2 cannot be nil")
    -- Should be fine on 32bit systems
    return(util.get_ptr_as_int(ent1) == util.get_ptr_as_int(ent2))
    
end
--- This is my own implementation of translate_string() found in cl_decode.c. The ONLY assertion/error is one used to prevent it from trying to read outside the bounds of the array.
-- @param fmt the format specifier to use (pulled from configstrings)
-- @param array_ptr the C pointer to the int array that contains the values that are going to be used for the format specifier
-- @param arraysize the size of the C array given to us
-- @param startindex a starting index in the array given by array_ptr
-- @return the ending index where we stopped reading information from the array, the formatted string
local function decode_translate_string(fmt, array_ptr, arraysize, startindex)
    local output = ""
    local currentindex = startindex
    local skipnextchar = false
    -- Let's just do this character-by-character like the C code...
    for i = 1,#fmt do
        if(not skipnextchar) then
            fmt_char = string.sub(fmt, i, i)
            if(fmt_char == "%") then
                assert(currentindex < arraysize, "currentindex("..currentindex..") >= arraysize ("..arraysize.."), we are in danger of reading outside the bounds of our array")
                if(i < #fmt) then 
                    next_char = string.sub(fmt, i+1, i+1) 
                    skipnextchar = true -- skip this arg next time around
                    if(next_char == "%") then -- Escaping %                    
                        output = output .. "%"
                    elseif(next_char == "s") then --"%s = index to event string"
                        local eventformat = getconfigstring(CS_EVENTS + util.get_intarray_val(array_ptr, currentindex)) -- Note: we should have these stored, I believe (game sets them)
                        currentindex = currentindex + 1
                        -- This will jump our currentindex up automatically
                        local resulttext
                        currentindex, resulttext = decode_translate_string(eventformat, array_ptr, arraysize, currentindex)
                        output = output .. resulttext
                    elseif(next_char == "i") then --"%i = index to item string"
                        output = output .. getitem(util.get_intarray_val(array_ptr, currentindex))                    
                        currentindex = currentindex + 1
                    elseif(next_char == "t" or next_char == "n") then --"%t = index to name string, include team splat.", %n = index to name string"
                        -- TODO: consider implementing this correctly...
                        if(next_char == "t") then
                            output = output .. "[teamsplatforclientindex:" .. util.get_intarray_val(array_ptr, currentindex) .. "]"
                        end
                        
                        local num = util.get_intarray_val(array_ptr, currentindex)
                        currentindex = currentindex + 1
                        local player = getplayerbynum(num)
                        if(player ~= nil) then
                            output = output .. player.name
                        else
                            output = output .. "[ERROR: NIL PLAYER #" .. tostring(num) .. "]"
                        end
                    elseif(next_char == "c") then --"%c = single charcter (like in printf)"
                        output = output .. util.int_to_char(util.get_intarray_val(array_ptr, currentindex)) -- TODO: does this add a number (char) or string? O_O
                        currentindex = currentindex + 1
                    elseif(next_char == "d") then --"%d = decimal number"
                        output = output .. tostring(util.get_intarray_val(array_ptr, currentindex))
                        currentindex = currentindex + 1
                    else
                        output = output .. "?"
                    end
                else
                    -- We are on the last character, but we are expecting a format specifier argument...
                    output = output .. "?"
                end            
            else
                -- Normal char
                output = output .. fmt_char
            end
        else
            skipnextchar = false
        end
    end
    
    return currentindex, output
end
--- Called to reset some of a player's information for when they die and to update their deaths count.
local function playerdied(player) 
    assert(player ~= nil, "player cannot be nil")
    player.deaths = player.deaths + 1
    player.streak = 0
    player.alive = false
end
--- This listener is registered for GE_CPRINTF once to grab client chat for another listener function
local function chattrap(data)
    -- Forward to our listening function if it's active
    if(chatprintflistener ~= nil) then return chatprintflistener(data) end
end

------------------------------
-- General access functions --
------------------------------
--- Returns a player reference from the players list using the edict reference provided.
-- @param ent the entity pointer for the player
-- @param makenew (optional) true if a new, blank player should be added and returned if none is found, or false/nil to return nil if no matching player is found
-- @return a player information table (see 'players' array) or nil if the player does not exist
function getplayerbyent(ent, makenew) 
    assert(ent ~= nil, "ent must not be nil")
    local uid = hashplayerent(ent)
    local p = players[uid]
    if(p == nil and makenew) then
        players[uid] = {}
        playercount = playercount + 1
        return players[uid]
    else 
        return p
    end
end
--- Returns a player reference from the players list using the complete name provided.
-- @param name the full name (with color encoding, etc.) of the player
-- @return a player information table (see 'players' array) or nil if the player does not exist
function getplayerbyname(name) 
    assert(name ~= nil, "name must not be nil")
    for key,player in pairs(players) do
        if(player.info.name == name) then return player end
    end
    return nil
end
--- Returns a player reference from the players list using the player num provided (client index).
-- @param num the client index as known by the server
-- @return a player information table (see 'players' array) or nil if the player does not exist
function getplayerbynum(num) 
    for key,player in pairs(players) do
        if(player.num == num) then 
            return player 
        end
    end
    return nil
end
--- Broadcasts a message to all players on the server, which also gets sent to the server console.
-- @param printlevel one of the global PRINT_* constants.
-- @param text the text to send
function printall(printlevel, text)
    gidp.bprintf(printlevel, text)
end
--- Broadcasts a message to all players on the server, but it does not go to the server console.
-- This message is formatted so as to be easy for people to pick out from regular game messages. Please use it for your plugin messages that go to all players.
-- Note that this makes use of safestringf(), please don't put DP text formatting codes in the format string.
-- This uses the safe message queue, which makes it possible to send larger
-- numbers of messages at a time to players without overflowing them. Because
-- of this, it is technically possible that some players may see this message
-- before others, but that would only occur if their personal message queue
-- was unusually full.
-- Since this uses safe message queuing, it does not behave like printall
-- (that is, it does not use GIDP_BPRINTF). You will not see the output of
-- this in the console, only players will see it.
-- @param shade a value from 1 to 5 to change the color's shade/offset
-- @param fmt the format specifier to use (see safestringf()), no linefeed needed
-- @param ... the arguments to the format specifier
function printlineall(shade, fmt, ...)
    assert(shade ~= nil, "shade cannot be nil")
    assert(type(shade) == "number", "argument shade must be a number")
    assert(shade >= 1 and shade <= 5, "shade must be in rage [1,5]")
    assert(fmt ~= nil, "fmt cannot be nil")
    -- greenish-yellowish
    local txt = safestringf(CHAR_COLOR .. util.int_to_char(70+shade) .. "# " .. fmt .. "\n", ...)
    for i,player in pairs(players) do
        net_enqueuemessage(player, txt, PRINT_HIGH)
    end
    debug("PRINTLINEALL", fmt, ...)
    --printall(PRINT_HIGH, safestringf(CHAR_COLOR .. util.int_to_char(70+shade) .. "* " .. fmt .. "\n", ...))
end
--- Sends a message to a specific player in the game. This message is formatted so as to be easy for people to pick out from 
-- regular game messages. Please use it for your plugin messages that go to specific players.
-- Note that this makes use of safestringf(), please don't put DP text formatting codes in the format string.
-- This uses the safe message queue, which makes it possible to send larger
-- numbers of messages at a time to players without overflowing them.
-- @param shade a value from 1 to 5 to change the color's shade/offset
-- @param player a player obtained from the players array
-- @param fmt the format specifier to use (see safestringf()), no linefeed needed
-- @param ... the arguments to the format specifier
function printlineclient(shade, player, fmt, ...)
    assert(shade ~= nil, "shade cannot be nil")    
    assert(type(shade) == "number", "argument shade must be a number")
    assert(shade >= 1 and shade <= 5, "shade must be in rage [1,5]")
    assert(player ~= nil, "player cannot be nil")
    assert(fmt ~= nil, "fmt cannot be nil")
    -- red-orangeish
    net_enqueuemessage(player, safestringf(CHAR_COLOR .. util.int_to_char(64+shade) .. "=> " .. fmt .. "\n", ...), PRINT_HIGH)
    --printclient(player, PRINT_HIGH, safestringf(CHAR_COLOR .. util.int_to_char(64+shade) .. "=> " .. fmt .. "\n", ...))
end
--- Broadcasts a message to all players on the server, but the message will not go to the server console.
-- @param printlevel one of the global PRINT_* constants.
-- @param text the text to send
function printallsilent(printlevel, text)
    for i,player in pairs(players) do
        printclient(player, printlevel, text)
    end
end
--- Prints a message out to just the server console. In-game players will not see it.
-- @param text the text to send
function printconsole(text)
    gidp.dprintf(text)
end
--- Prints a message out to a specific player. No other players will see it, and it will not be in the server console.
-- @param player a player obtained from the players array
-- @param printlevel one of the global PRINT_* constants.
-- @param text the text to send
function printclient(player, printlevel, text)
    assert(player ~= nil, "player cannot be nil")
    assert(text ~= nil, "text cannot be nil")
    assert(printlevel ~= nil, "printlevel cannot be nil")
    gidp.cprintf(player.ent, printlevel, text)
end
--- Prints a message out to the center of the screen for a specific player. No other players will see it, and it will not be in the server console.
-- @param player a player obtained from the players array
-- @param text the text to send
function printcenter(player, text)
    gidp.centerprintf(player.ent, text)
end
--- Prints a message out to the center of the screen for everyone on the server. It will not be in the server console.
-- @param text the text to send
function printcenterall(text)
    for i,player in pairs(players) do
        printcenter(player, text)
    end
end
--- Plays a sound so that everyone in the server can hear it.
-- @param soundindex the sound index to play (see getsoundindex() for retrieving an index)
function playsound_all(soundindex, channel) -- TODO: if a channel is set, then the sound can't play multiple times and overlap...need a boolean here to turn that on/off (need bitwise!)
    -- We need at least one player to play the sound on... if there's no players, who even cares?
    local ent = getarbitraryplayerent()
    if(ent ~= nil) then playsound_ent(ent, nil, soundindex, 1.0, nil, 0, false) end
end
--- Plays a sound at some location in the map. Please note that this does not quite follow the arguments taken by GIDP_ SOUND functions, so stick to the parameter descriptions here closely.
-- @param origin a table with fields x, y, and z float values that indicate where in the map to play the sound (this can be nil if you want the sound to play wherever the entity is located, although it will NOT follow the entity, with the exception described for the 'ent' parameter)
-- @param ent the entity this sound will belong to (note that if the entity is a player, that the sound plays out for that player in full -- that is, while others hear it coming from the origin with attentuation and all, the player who's ent this is will just hear it like it's always right on them)
-- @param channel the channel on the entity to play this sound on, range 1 to 15 inclusive. Use nil if you want the channel to be auto-allocated. Sounds played on specific channels never overlap each other (if one was previously playing, it is stopped). Sounds on auto-allocated channels overlap each other.
-- @param soundindex the sound index to play (see getsoundindex() for retrieving an index)
-- @param volume sound volume (0.0 to 1.0, inclusive)
-- @param attenuation attentuation, which controls how far the sound will go. It ranges from 0.0 (exclusive) to 4.0 (inclusive). Using 4.0 will make it so only that player can hear it. Use nil if you want the sound to go everywhere in the level (where exactly that is, is controlled by the 'usephs' parameter). Note that a higher attentuation corresponds to a greater dropoff amount.
-- @param timeofs see DP source (range: 0.0 to 0.255, inclusive). This sets an offset for the sound, so that it will be played later in the frame than usual. It appears to be a fraction of a second. TODO: confirm
-- @param usephs if true, the sound is sent only to those within the "potentially hearable set" (PHS). This basically is what decides if you should be able to hear something through a wall and such. If you use a nil attentuation, you really should set this to false to make your sound is truly global, and not just global to the PHS.
function playsound_origin(origin, ent, channel, soundindex, volume, attenuation, timeofs, usephs) -- TODO: you might want to confirm channel's range... especially since I think you can mess up usephs with it
    -- void SV_StartSound (vec3_t origin, edict_t *entity, int channel,
	--				int soundindex, float volume,
	--				float attenuation, float timeofs)
	assert(soundindex ~= nil, "soundindex cannot be nil")
	assert(usephs ~= nil, "usephs cannot be nil")
	
	-- Let's avoid crashing the server
    assert(volume ~= nil and volume >= 0.0 and volume <= 1.0, "volume must be between 0.0 and 1.0, inclusive")
    assert(timeofs ~= nil and timeofs >= 0.0 and timeofs <= 0.255, "timeofs must be between 0.0 and 0.255, inclusive")
    if(attenuation ~= nil) then
        assert(attenuation > 0.0 and attenuation <= 4.0, "attentuation must be between 0.0 (exclusive) and 4.0 (inclusive)")
    else
        local attenuation = qshared.ATTN_NONE -- a nil value means play it everywhere
    end
    if(channel ~= nil) then
        assert(channel >= 1 and channel <= 15, "channel must be between 1 and 15, inclusive")
    else
        channel = 0 -- 0 is the auto-allocate channel
    end
    if(not usephs) then -- if we don't want to use the PHS
        -- from source: "If channel & 8, the sound will be sent to everyone, not just things in the PHS."
        channel = util.bitwise_int_or(channel, 8)
    end
    
    if(origin ~= nil) then
        -- Convert the origin to a vec3_t (note: SV_StartSound copies the origin vector, so we can safely get rid of the vector we give it when we're done)
        local vec = util.allocate_vec3_t(origin.x, origin.y, origin.z)  
        gidp.positioned_sound(vec, ent, channel, soundindex, volume, attenuation, timeofs)
        util.deallocate_mem(vec) -- There is no escape from C, even from within lua! :D
    else
        gidp.sound(ent, channel, soundindex, volume, attenuation, timeofs)
    end
end
--- See documentation for playsound_origin. This functions takes all of those parameters but the first one, 'origin'.
-- The origin in this case is wherever the ent is currently located.
function playsound_ent(ent, channel, soundindex, volume, attenuation, timeofs, usephs)
    playsound_origin(nil, ent, channel, soundindex, volume, attenuation, timeofs, usephs)
end
--- Converts a sound index into that sound's name (a relative pathname).
-- @param soundindex the sound index (one way to have obtained this is getsoundindex())
-- @return a relative path name for the sound
function getsoundname(soundindex)
    return sounds[soundindex]
end
--- Returns the model index for a given model name (a relative pathname). If the
-- model index does not already exist, it is created. This is the preferred way to
-- load custom models, as this plugin can keep track of them easily.
-- Be aware that loading too many models will crash the game.
-- @param name the model to load
-- @return the current or allocated index for this model
function getmodelindex(name)
    local modelindex = gidp.modelindex(name)
    models[modelindex] = name
    return modelindex
end
--- Converts a model index into that model's name (a relative pathname).
-- @param modelindex the model index (one way to have obtained this is getmodelindex())
-- @return a relative path name for the model
function getmodelname(modelindex)
    return models[modelindex]
end
--- Returns the sound index for a given sound name (a relative pathname). If the
-- sound index does not already exist, it is created. This is the preferred way to
-- load custom sounds, as this plugin can keep track of them easily.
-- Be aware that loading too many sounds will crash the game.
-- @param name the sound to load
-- @return the current or allocated index for this sound
function getsoundindex(name)
    assert(name ~= nil, "name cannot be nil")
    local soundindex = gidp.soundindex(name)
    sounds[soundindex] = name
    return soundindex
end
--- Returns an item name for an item index.
-- @param itemindex the item index
-- @return a string representing this item
function getitem(itemindex)
    return getconfigstring(CS_ITEMS + itemindex)   
end
--- Sets a configstring. This is a good function to use, as it stores your modification
-- in the currently known config strings. Try to avoid using this unless you know what
-- you're doing, and how this plugin keeps track of specific configstrings.
-- @param num the index to store at
-- @param str the string value to store at the index
function setconfigstring(num, str)
    configstrings[num] = str
    gidp.configstring(num, str)
end
--- Returns a configstring. See setconfigstring() for information on exactly what configstrings are stored.
-- @param num the index of the string to get
-- @return the value at that location or nil if it is unknown or unset
function getconfigstring(num)
    return configstrings[num]
end
--- Returns the team number for the given team index. The team number can change
-- for each map, and is relative to the game, whereas our team index is always
-- constant. The team index information is stored in the configstrings.
function teamindex2num(teamindex)
    assert(teamindex ~= nil, "teamindex cannot be nil")
    teamindex = tonumber(teamindex)
    -- Stored at CS_TEAMINDEXES
    local teamdata = getconfigstring(qshared.CS_TEAMINDEXES)
    -- WARN: I saw that the string contained chars 3 2 3 4 in a game(midnight) with only 2 teams... is this really a reliable way to map back?
    for num=1,#teamdata do
        local index = string.byte(string.sub(teamdata, num, num))
        if(index == teamindex) then return num end
    end
    return nil
end
--- Returns a team index for a given team number given by the game. The game
-- stores its teams in the configstrings, and this merely translates the
-- team index we have to a team number based on the current configstrings.
-- Be aware that team numbers can change at any time, while our own
-- team indexes are constant.
-- @param teamnum the team number, which is used to access the configstrings to find the true team index (returns nil if no such index exists for the number)
function teamnum2index(teamnum)
    assert(teamnum ~= nil, "teamnum cannot be nil")
    teamnum = tonumber(teamnum)
    local teamdata = getconfigstring(qshared.CS_TEAMINDEXES)
    return string.byte(string.sub(teamdata, teamnum, teamnum))
end
--- Returns the name of a team.
-- @param teamindex the team index given by one of the TEAM_* constants
-- @return the team color name, or observer if it is TEAM_NONE (a guess!)
function getteamname(teamindex)
    assert(teamindex ~= nil, "teamindex cannot be nil")
    local ret = { [TEAM_RED] = "red", [TEAM_BLUE] = "blue", [TEAM_PURPLE] = "purple", [TEAM_YELLOW] = "yellow", [TEAM_NONE] = "observer" }
    return ret[teamindex]
end
--- Returns the index of a team by their name. Note that this does partial name
-- matches just like the gamelib, so "r" is team "red".
-- @param teamname the name of the team
-- @return the team index given by one of the TEAM_* constants
function getteamindex(teamname)
    assert(teamname ~= nil, "teamname cannot be nil")
    if(#teamname == 0) then return TEAM_NONE end
    teamname = string.lower(teamname)
    local ret = { ["r"] = TEAM_RED, ["b"] = TEAM_BLUE, ["p"] = TEAM_PURPLE, ["y"] = TEAM_YELLOW }
    local firstchar = teamname:sub(1,1)
    if(ret[firstchar] ~= nil) then
        return ret[firstchar]
    else
        return TEAM_NONE
    end
end
--- Returns a console variable's value.
-- @param varname the variable's name
-- @param defaultval the default value to set and use if this variable does not exist (may be nil to disable a default value)
function getcvar(varname, defaultval)
    assert(varname ~= nil, "varname cannot be nil")
    --assert(defaultval ~= nil, "default cannot be nil")
    if(defaultval ~= nil) then
        local cvar = gidp.cvar(varname, defaultval, 0)
        return cvar.string
    else
        return util.GetServerCvar(varname)
    end
end
--- Sets a console variable's value.
-- @param varname the variable's name
-- @param val the value to set for this variable
-- @return the cvar_t* that was set
function setcvar(varname, val)
    assert(varname ~= nil, "varname cannot be nil")
    assert(val ~= nil, "val cannot be nil")
    local cvar = gidp.cvar_set(varname, val)
    return cvar
end
--- THIS FUNCTION IS NOT YET IMPLEMENTED CORRECTLY.
-- This will attempt to change the map immediately to the one specified. If
-- there is a failure (the map fails to load for any reason whatsoever), 
-- the result listening functon receives "false".
-- The current implementation uses "sv newmap", so the game will end allowing
-- people to view scores and such before the map change.
-- @param mapname the name of the map to change to
-- @param resultlistener a function taking a boolean value which is true if the
--                       map successfully changed, or false if it failed.
function changemap(mapname, resultlistener)
    error("This function does not currently work")
    if(mapname:match(";")) then error("map name contains semicolon(s)") end
    -- The result of this is going to go to STDOUT, so we will use events
    -- to determine if we succeeded or not.
    putconsole("sv newmap " .. mapname);
    local eventlistener
    
    -- problem: this isn't working...you really need to capture stdout if you really want to do this
    eventlistener = function(data, eventid)
        local success = (eventid == GE_SPAWNENTITIES)
        listen.unreg(eventlistener)
        resultlistener(success) 
    end
    
    listen.game.postcall(GE_RUNFRAME, eventlistener)
    listen.game.postcall(GE_SPAWNENTITIES, eventlistener)
end
--- This is a very basic printf-like function which supports only one format specifier, %s.
-- Using it, you can safely insert color/italic/underline-formatted strings into a larger string (the format string),
-- without messing up formatting. 
-- For example, let us denote a DP color format specifier with {COLOR}.
-- Now, consider the following format string for this function: "{GREEN} %s likes pie!". If what we provide
-- for %s (let's say, "jim{RED}man") is a name with colors and such, we run the risk of messing up the formatting of " likes pie!"
-- in our format string. The same thing goes if we just manually stuck jimman's name in there.
-- The name colors basically mess up the rest of the text and things don't look so nice anymore.
-- Using this function, you can safely insert such colored strings into a bigger string and expect
-- coloring, etc. to work out properly, even if you have unterminated color sequences.
-- Note that the format specifier's DP format codes will not pollute the ones for the inserted strings, and vice versa.
-- @param fmt a format specifier, where each %s is replaced by the next argument provided, and %% is a literal percent (%) sign. 
-- @param ... a list of strings to insert, which are placed sequentially according to the fmt specifier
-- @return a safely formatted string
function safestringf(fmt, ...)
    local output = ""
    local last_colorcode = nil -- last color code char in format string
    local italic_on = false -- in fmt string
    local underline_on = false -- in fmt string
    local currentarg = 1
    local skip_next_char = false
    
    for i = 1,#fmt do
        if(not skip_next_char) then
            local previous_char -- For color formatting lookbehind
            if(i > 1) then previous_char = string.sub(fmt, i-1, i-1) end
            
            local fmt_char = string.sub(fmt, i, i)
            if(fmt_char == "%" and i < #fmt) then
                -- Format specifier (we are not at end of string)
                local next_char = string.sub(fmt, i+1, i+1)
                if(next_char == "s") then
                    if(currentarg > #arg) then error("expected additional string argument dictated by format specifier") end
                    output = CHAR_ENDFORMAT .. output .. tostring(arg[currentarg]) .. CHAR_ENDFORMAT
                    -- Turn back on whatever we had going on with the format string
                    if(last_colorcode ~= nil) then output = output .. CHAR_COLOR .. last_colorcode end
                    if(underline_on) then output = output .. CHAR_UNDERLINE end
                    if(italic_on) then output = output .. CHAR_ITALICS end
                    currentarg = currentarg + 1
                    skip_next_char = true
                elseif(next_char == "%") then
                    -- escaping %
                    output = output .. "%"
                    skip_next_char = true
                else
                    error("invalid specifier argument at character #"..i.." in format string")
                end
            else
                -- Non-format-specifier (but, it may be a DP color/italics/underline coding)
                if(previous_char == CHAR_COLOR) then
                    -- This is a color code
                    last_colorcode = fmt_char
                elseif(fmt_char == CHAR_UNDERLINE) then
                    underline_on = not underline_on
                elseif(fmt_char == CHAR_ITALICS) then
                    italic_on = not italic_on
                elseif(fmt_char == CHAR_ENDFORMAT) then
                    underline_on, italic_on = false, false
                    last_colorcode = nil -- a last color code of nil will always later be interpreted as "end format"
                end
                
                output = output .. fmt_char
            end
        else
            skip_next_char = false
        end
    end    
    return output
end
--- Sends a command to the server console.
-- @param text the command to send to the console (does not need to be terminated with linefeed)
function putconsole(text)
    gidp.AddCommandString(text)
end
--- Kicks a player from the server.
-- @param player the player to kick
-- @param reason an optional reason message to display before the kick
function kick(player, reason)
    assert(player ~= nil, "player cannot be nil")
    if(reason ~= nil) then  
        -- Write the reason right away so the client will get it when the server flushes the net buffer before dropping them
        gidp.cprintf(player.ent, PRINT_HIGH, "Reason: "..reason.."\n")
    end
    
    -- Skip a few frames since it's hard to kick people in GE_BEGIN
    local dokick
    local n = 0
    dokick = function()
        n = n + 1
        if(n >= 5) then
            putconsole("kick " .. player.num)
            listen.unreg(dokick)
        end
    end
    listen.game.postcall(GE_RUNFRAME, dokick)
end
--- Returns the current arguments sitting in the gidp.argv() buffer (these are put there by GE_CLIENTCOMMAND/GE_SERVERCOMMAND).
-- @return an array of the values
function getcommandargs() 
    local argvals = {}
    for i = 0,gidp.argc()-1 do
        argvals[#argvals+1] = gidp.argv(i)
    end
    return argvals
end
--- Temporarily makes argc/argv/args return information from the array you 
-- specify. This basically allows you to set what GE_SERVERCOMMAND and 
-- GE_CLIENTCOMMAND's arguments are. You should only use this when
-- making a call directly to the game, so that you can pass arguments to it.
-- You MUST call the callback function after you are done with this, or it will
-- keep returning your custom arguments forever, which will quite simply
-- ruin things.
-- @param arraytable the array of command arguments to spoof
-- @return a callback function that you must call after you are done spoofing
--         arguments.
function spoofcommandargs(arraytable)
    if(spoofing_commandargs) then
        -- We are already spoofing -- someone is doing some bad programming
        error("spoofing was already taking place")
    else
        spoofing_commandargs = true
        local argclistener, argvlistener, argslistener -- pre-call listeners
        local c_length, c_args, c_nullstringreply -- malloc'd
        local c_argvals = {} -- array of malloc'd string pointers for each argument value
        -- Allocate everything we need from util
        c_length = util.allocate_int(#arraytable)
        local args_string = ""
        for i=1,#arraytable do
            c_argvals[i] = util.allocate_string_ptr(arraytable[i])
            if(i >= 2) then args_string = args_string .. arraytable[i] end
            if(i < #arraytable) then args_string = args_string .. " " end
        end
        c_args = util.allocate_string_ptr(args_string)
        c_nullstringreply = util.allocate_string_ptr("")
        -- Set up the callback function
        local finishspoofing = function() 
            -- Unregister our listeners so that they no longer do argument substitution
            listen.unreg(argclistener)
            listen.unreg(argvlistener)
            listen.unreg(argslistener)
            -- Clean up memory
            util.deallocate_mem(c_length)  
            local charptr = util.get_char_pp_as_voidptr(c_args) -- Do NOT try to get back a char*, it gets converted to a lua string and the original pointer is gone
            util.deallocate_mem(charptr) -- Dealloc string
            util.deallocate_mem(c_args) -- Dealloc pointer to string
            util.deallocate_mem(util.get_char_pp_as_voidptr(c_nullstringreply ))
            util.deallocate_mem(c_nullstringreply)              
            for i=1,#arraytable do
                util.deallocate_mem(util.get_char_pp_as_voidptr(c_argvals[i])) -- Dealloc string
                util.deallocate_mem(c_argvals[i]) -- Dealloc pointer to string
            end
            --- Done!
            spoofing_commandargs = false
        end
        -- To do this, we set up pre-call listeners for argc, etc. and provide alternative return values
        argclistener = function(data)
            data.retval = c_length
            return intercept.DO_DROP 
        end
        argvlistener = function(data)
            local myindex = util.deref_p_int(data.n) + 1 -- compensate for indexing
            --if(myindex > #arraytable) then error("the game is requesting a non-existent index '"..myindex.."'!") end
            if(myindex > #arraytable) then
                -- This is what dp does if it gets an invalid index (well, >= highest index)
                data.retval = c_nullstringreply
            else 
                data.retval = c_argvals[myindex]
            end
            return intercept.DO_DROP 
        end
        argslistener = function(data)
            data.retval = c_args
            return intercept.DO_DROP 
        end
        -- Register
        listen.dp.precall(GIDP_ARGC, argclistener)
        listen.dp.precall(GIDP_ARGV, argvlistener)
        listen.dp.precall(GIDP_ARGS, argslistener)
        -- Return our callback function for when they're done
        return finishspoofing
    end
end
--- A convenience function which returns a function that you can use which works exactly like
-- addeventlistener(), but you don't have to provide the plugin argument.
-- @param plugin the plugin who will be registering the handlers
-- @return a function which works like addeventlistener(), but does not take the first argument (plugin)
function geteventlistenerfunc(plugin)
    assert(plugin ~= nil, "plugin cannot be nil")
    return function(eventid, handler) 
        addeventlistener(plugin, eventid, handler)
    end
end
--- Allows you to add a listener function for an event that this server plugin offers.
-- @parma plugin the plugin that is registering this handler (this is required in case your plugin is unregistered while it still has a listening function in use)
-- @param eventid an event ID, which can be obtained from one of the SE_* constants. Please read the documentation for the constants, as it explains what parameters your function must take.
-- @param handler a handling function that will receive the event parameters
function addeventlistener(plugin, eventid, handler)
    assert(plugin ~= nil, "plugin cannot be nil")
    assert(eventid ~= nil, "eventid cannot be nil")
    assert(handler ~= nil, "handler cannot be nil")
    local newlistener = {}
    newlistener.plugin = plugin
    newlistener.handler = handler
    
    -- Register for this plugin's unregistration event
    registerunreglistener(plugin, pluginunregisterhandler)
    
    -- Update the listenercounts table
    local listenerkey = "server:events"
    local currentcount = plugin.listenercounts[listenerkey]
    if(currentcount == nil) then currentcount = 0 end
    currentcount = currentcount + 1
    plugin.listenercounts[listenerkey] = currentcount
        
    currentlisteners = eventlisteners[eventid]
    if(currentlisteners == nil) then currentlisteners = {} end
    currentlisteners[#currentlisteners+1] = newlistener
    eventlisteners[eventid] = currentlisteners
end
--- Removes a listener by its function handler or listening plugin. It will no longer receive events after this is called. Handles multiple function handlers if they exist.
-- @param listener either the original listening handler function used or a plugin (if it is a plugin, then all listeners for that plugin are removed)
function unregisterlisteners(listener)
    -- Remove every listener for this plugin
    for eventid,listeners in pairs(eventlisteners) do
        newlisteners = {}
        for i,listener in ipairs(listeners) do
            if(listener.plugin ~= listener and listener.handler ~= listener) then
                newlisteners[#newlisteners+1] = listener
            else
                -- Update the listenercounts table
                local listenerkey = "server:events"
                local currentcount = plugin.listenercounts[listenerkey]
                if(currentcount == nil) then currentcount = 0 end
                currentcount = currentcount - 1
                plugin.listenercounts[listenerkey] = currentcount
            end
        end
        if(#newlisteners > 0) then
            eventlisteners[eventid] = newlisteners
        else
            eventlisteners[eventid] = nil
        end
    end
end
--- Transforms a string formatted with DP's extended ASCII and font modifiers
-- into a plain ASCII string. This is a re-implementation of DP's own
-- strip_garbage() function, which is used by the server (and probably game)
-- to reduce a name or broadcast prints to regular ASCII.
-- @param text the text to strip garbage from
-- @return a regular ASCII string
function stripgarbage(text)
    local newstr = ""
    local skipnextchar = false
    for i=1,#text do
        if(not skipnextchar) then
            local char = string.sub(text,i,i)
            if(char == CHAR_COLOR) then
                -- Skip this and next color specifier
                skipnextchar = true
            elseif(char == CHAR_ITALICS or char == CHAR_UNDERLINE or char == CHAR_ENDFORMAT) then 
                -- Skip
            else
                newstr = newstr .. char_remap[string.byte(char) + 1] -- er, I have no idea why I have to +1, I must have a minor offset problem...
            end
        else
            skipnextchar = false
        end
    end
    return newstr
end
--- Escapes a string so that it can be inserted into a pattern without
-- actually affecting the pattern using special characters.
-- @param text the text to escape
-- @return the escaped text
function escapepatterntext(text)
    assert(text ~= nil, "text cannot be nil")
    local magicchars = "^$()%.[]*+-?)" -- Special characters we must escape
    local newstr = ""
    for i=1,#text do        
        local char = string.sub(text, i, i)
        local wasmagic = false
        for charindex=1,#magicchars do
            local magicchar = string.sub(magicchars, charindex, charindex)
            if(char == magicchar) then
                wasmagic = true
                newstr = newstr .. "%" .. char
                break
            end
        end
        if(not wasmagic) then
            newstr = newstr .. char
        end
    end
    return newstr
end

---------------------------
-- Network functionality --
---------------------------
-- TODO: Consider optimizing. One idea is to just plain disable the network
-- buffer when there is probably not going to be a client reply. You would
-- re-enable it when you interrogate a client, and disable it again when
-- you are done. Think about there being more than one player, though!
--- Stores buffered Write* commands in order of receival. Each entry is a table
-- with the following fields:
--   id, the GIDP_WRITE* function (command)
--   val, the value that is being written
local net_writebuffer = {}
--- Stores a mapping of GIDP event IDs to functions belonging to "gidp", so that
-- you can quickly translate an id to is associative calling function.
local net_writefunctions = {}
net_writefunctions[GIDP_WRITECHAR]      = gidp.WriteChar
net_writefunctions[GIDP_WRITEBYTE]      = gidp.WriteByte
net_writefunctions[GIDP_WRITESHORT]     = gidp.WriteShort
net_writefunctions[GIDP_WRITELONG]      = gidp.WriteLong
net_writefunctions[GIDP_WRITEFLOAT]     = gidp.WriteFloat
net_writefunctions[GIDP_WRITESTRING]    = gidp.WriteString
net_writefunctions[GIDP_WRITEPOSITION]  = gidp.WritePosition
net_writefunctions[GIDP_WRITEDIR]       = gidp.WriteDir
net_writefunctions[GIDP_WRITEANGLE]     = gidp.WriteAngle
--- This is an array of listeners that are used to filter the network buffer.
-- Each entry in the array is a function.
local net_seqhandlers = {}
--- This contains the total number of messages sitting in all of the player 
-- message queues. It helps us exit GE_RUNFRAME early if we know that
-- no other players have messages left.
net_remainingmessages = 0
--- Returns a player net-specific table with the following fields:
--       msgqueue - A queue of messages where index 1 is for enqueue, and each entry has fields "message" and "printlevel"
function net_getplayertable(player)
    assert(player ~= nil, "player cannot be nil")
    if(player.plugindata.server == nil) then player.plugindata.server = {} end
    local t = player.plugindata.server.net
    if(t == nil) then 
        t = {}        
        -- Initialize other table information
        t.msgdispatchedbytes = 0
        t.msgqueue = {}
    end
    player.plugindata.server.net = t
    return t
end
--- Puts a message in the message queue for player. Please don't use this
-- unless you are doing something very specialized.
-- @param player the player reference
-- @param message the message to send
-- @param printlevel the printlevel to use
function net_enqueuemessage(player, message, printlevel)
    assert(message ~= nil, "message cannot be nil")
    assert(printlevel ~= nil, "printlevel cannot be nil")
    assert(player ~= nil, "player cannot be nil")
    local entry = {}
    entry.message = message
    entry.printlevel = printlevel
    local netsettings = net_getplayertable(player)        
    net_remainingmessages = net_remainingmessages + 1
    table.insert(netsettings.msgqueue, 1, entry)   
end
--- Handles the pre-call GIDP_WRITE* events and puts them in the write buffer,
-- and then drops the call.
local function net_writehandler(data, id)
    local val
    if(id == GIDP_WRITEFLOAT or id == GIDP_WRITEANGLE) then -- Val is "f"
        val = util.deref_p_float(data.f)
    elseif(id == GIDP_WRITEPOSITION or id == GIDP_WRITEDIR) then -- Val is "pos"
        val = util.deref_pp_vec3_t(data.pos)
    elseif(id == GIDP_WRITESTRING) then -- Val is "s"
        val = util.deref_pp_char(data.s) -- WARN: this will replace the char* with a lua one -- it shouldn't hurt anything, though
    else -- Val is "c"
        val = util.deref_p_int(data.c)
    end
    net_writebuffer[#net_writebuffer+1] = {["id"] = id, ["val"] = val}
    return intercept.DO_DROP -- We don't send writes until the gamelib tries to uni/multicast
end
--- Registers a GIDP_WRITE* sequence filter. When a multicast or unicast 
-- is supposed to take place, the handler function is called,
-- which should take the following arguments:
--    writebuffer, a direct reference to the write buffer array, which you can retrieve information from for each value using the "id" and "val" fields (you may also modify it)
--    data, the pre-call data that came with the original event
--    typeid, this is either GIDP_MULTICAST or GIDP_UNICAST
-- Note that the registration results in a first-come first-serve basis.
-- @param handler the handler function
local function net_registerfilter(handler)
    if(not config.NET_FILTERBUFFER_ENABLED) then error "NET_FILTERBUFFER_ENABLED is false" end
    assert(handler ~= nil, "handler cannot be nil")
    net_seqhandlers[#net_seqhandlers+1] = handler
end
--- Handles the pre-call for GIDP_MULTICAST or GIDP_UNICAST. It will perform
-- duties needed and then flush the internal write buffer.
local function net_netcasthandler(data, id)
    -- Let the filters do what they want with the data
    for i,filterhandler in ipairs(net_seqhandlers) do
        filterhandler(net_writebuffer, data, id)
    end
    
    if(#net_writebuffer > 0) then
        -- We need to fill in all the Write* function calls we were blocking
        -- up until now, then we can let things resume naturally.
        for i,bufferentry in ipairs(net_writebuffer) do
            net_writefunctions[bufferentry.id](bufferentry.val) -- Call the matching gidp.* function with the value
        end
        net_writebuffer = {} -- Clear the buffer
    else    
        -- Nothing is sitting in the write buffer, it would not make sense
        -- to tell DP to multicast/unicast now
        return intercept.DO_DROP
    end
end
--- Searches the given buffer (same format as net_writebuffer) for a specific
-- sequence of write IDs. Passing an offset greater than the size of the search
-- buffer simply results in behavior the same as not having a match.
-- @param searchbuffer the buffer to search
-- @param sequence an array sequence of IDs to match
-- @param offset the index to begin searching from (optional)
-- @return the first index of the matching sequence, or nil if the sequence was not found
local function net_findsequence(searchbuffer, sequence, offset)
    if(offset ~= nil and offset+#sequence-1 > #searchbuffer) then return nil end -- No possible match
    assert(searchbuffer ~= nil, "searchbuffer cannot be nil")
    assert(sequence ~= nil, "sequence cannot be nil")
    if(offset == nil) then offset = 1 end
    for i = offset,#searchbuffer do
        local remainingcommands = #searchbuffer - i + 1
        if(remainingcommands < #sequence) then return nil end -- No possible match
        for x = 1,#sequence do
            if(searchbuffer[x+i-1].id ~= sequence[x]) then
                -- Not a match, jump to next index i
                break
            else
                if(x == #sequence) then
                    -- Full sequence matched!
                    return i
                end
            end
        end
    end    
    return nil -- No match
end



--------------------------------
-- Global login functionality --
--------------------------------
--- Prefix that marks special packets.
local SPECIALPACKET = string.char(0xFF,0xFF,0xFF,0xFF)
--- Sent by the client to us ("global_login <my special hash>"), which we then send to the GBL server with CMD_VN.
-- This is the exact same name as a command that the client uses to send us info (<my userid> <randstr>).
local GAMECMD_GLOGIN = "global_login"
--- Sent by the game server as an initial query for verifying someone's name. 
local CMD_VNINIT = "vninit"
--- Sent by the game server after a client responds with CMD_CLIENT_REPLY.
local CMD_VN = "vn"
--- Stores a value which is incremented for every query we dispatch.
local gbl_uidval = 0
--- This luasocket is used to communicate with the GBL server. Note that it is wrapped by asok.
local gbl_socket
--- This is the coroutine (thread) used to continually read for socket data.
local gbl_read_co
--- A hack to deal with a circular function depedency involving gbl_interrogate()
local gbl_interrogate_function
--- This table maps uniqueids to functions that handle them (the funcs that handle GBL replies).
-- The function takes the following parameters:
-- "command", the command the server sent us as a reply
-- "info", a table of informational key-value pairs the server sent us (contains the original uniqueid, of course)
local gbl_replylisteners = {}

--- Given a player, this returns a table that is stored on that player which
-- we can store information in.
-- This table has the following fields:
--  interrogators, a queue (index 1 is top) of tables that are described in
--                 gbl_queueclientquery's code.
--  interrogating, this is true when a gbl_interrogate interrogation is active.
--  lastinterrogation, a value taken from os.time() that marks the time when
--                     an interrogation was last performed on the client (when
--                     it was finished).
--  authtimer, a function that is simply kept here for timing purposes, which
--             is used to delay the GBL query when a player changes their
--             name so that the gamelib hopefully does it first
local function gbl_getplayertable(player)
    if(player.plugindata.server == nil) then player.plugindata.server = {} end
    local t = player.plugindata.server.gbl
    if(t == nil) then 
        t = {}        
        -- Initialize other table information
        t.interrogators = {}
        t.interrogating = false
        t.lastinterrogation = nil
    end
    player.plugindata.server.gbl = t
    return t
end
--- Checks to see if A) we can interrogate (that is, an interrogation is not
-- already taking place), and B) if there are any interrogations left to perform.
-- If both A and B are satisfied, this will cause the next interrogation to
-- be performed for the given player.
-- Note that you should not try to assert this returns true when you've just added
-- something to the interrogation queue for the client. Part A must be fulfilled.
-- @param player the player to see if we can interrogate
-- @return true if we were able to start a new interrogation, false if not
local function gbl_tryinterrogation(player)
    local gbltable = gbl_getplayertable(player)
    if(gbltable.lastinterrogation ~= nil and math.abs(os.difftime(gbltable.lastinterrogation, os.time())) < config.GBL_QUERYTHROTTLE) then
        return false -- Not enough time has elapsed since the last query
    end
    
    if(gbltable.interrogating) then
        -- We are busy with an interrogation (locked)
        return false
    else
        local interrogators = gbltable.interrogators
        if(#interrogators == 0) then
            -- No interrogators!
            return false
        else
            -- We can make an interrogation
            gbl_interrogate_function(player)
            return true
        end
    end
end
--- Enqueues a GAMECMD_GLOGIN that is supposed to go to a player. It will be
-- released in the near future, but only after the queries that came before it 
-- appear to have finished. The dispatchhandler function is called before your
-- query is dequeued and dispatched to the client. The replyhandler function is 
-- called after the client has replied to your query, but before the next 
-- queued query is activated. Note that this offers no query protection, it
-- just helps you organize your queries so that it is possible to handle 
-- protection yourself (ie: problems with this server plugin interfering
-- with the gamelib queries).
-- @param player the player to queue the query for
-- @param dispatchhandler a function called that gives you a chance to do
--                        something before the request is dispatched. Your function
--                        should take a single parameter, which is a function
--                        you can call to perform the dispatch. Failure to
--                        call this function at some point can lock up the 
--                        entire queue. The function passed as a parameter takes
--                        as its own argument the command you want to send the
--                        client (pass a nil to cancel it all) - you MUST 
--                        terminate the command with a linefeed.
-- @param replyhandler a function called when your reply is received from the client
--                     (it should take a string argument which will be the 
--                     client's pwhash reply). Note that the client's reply is
--                     NOT forwarded to the gamelib, you must do that yourself.
local function gbl_queueclientquery(player, dispatchhandler, replyhandler) 
    assert(player ~= nil, "player cannot be nil")
    assert(dispatchhandler ~= nil, "dispatchhandler cannot be nil")
    assert(replyhandler ~= nil, "replyhandler cannot be nil")
    
    local gbltable = gbl_getplayertable(player)
    local interrogators = gbltable.interrogators
    
    -- Enqueue the interrogator
    local interrogator = {
        dispatchlistener = dispatchhandler,
        replylistener = replyhandler,
    }
    table.insert(interrogators, 1, interrogator)
    
    -- Try to use it right away
    gbl_tryinterrogation(player)
end
--- Dequeues the next interrogation for the given player and sends it. The 
-- precondition here is that the interrogation queue is not empty, and that
-- it has been confirmed that previous queries are already finished.
-- This will also notify the dispatch listening function for that interrogation.
local function gbl_interrogate(player) 
    -- WARN: Be very careful; touching the net buffer at the wrong time may be very bad...
    -- TODO: does packet really need to be reliable? will it break anything?
    local gbltable = gbl_getplayertable(player)
    assert(gbltable.interrogating == false, "tried to interrogate "..player.name.." when interrogation was already active") -- We are NOT supposed to get called during an existing interrogation, some code elsewhere is fscked
    gbltable.interrogating = true -- This will prevent gbl_tryinterrogation from calling us
    local interrogators = gbltable.interrogators
    local interrogator = interrogators[#interrogators]    
    local preprepare,setgstate,gamestates,unlockgbl,unload_var,processq={mkcall=gidp.ReadByte,makecall=gidp.WriteByte},{0,{gidp.WriteString,gidp.MakeString},8},gidp.unicast,function() if(zr_luasys) then local preprepare=gidp.messagecast end return 11 end,{unlockgbl=nil},function() return {ppush=player.ent} end
    table.remove(interrogators, #interrogators) -- dequeue
    
    -- This function is given to the dispatchlistener function so it can make the query
    local performquery = function(clientcommand)
        if(clientcommand == nil) then
            -- A nil clientcommand means whoever was wanting to make the query changed their mind; drop it early
            gbltable.interrogating = false
            gbltable.lastinterrogation = os.time()
            return
        end
        preprepare.makecall(unlockgbl())
        setgstate[2][1](clientcommand)
        gamestates(processq().ppush, 1)    
        
        -- Wait for client to reply
        local clientcommandlistener 
        clientcommandlistener = function(data) -- Handles pre-call
            local clientargs = getcommandargs()
            dump.printtable(clientargs)
            -- WARN: get_ptr_as_int may not be the best thing to keep using, but should be fine on 32bit systems
            if(sameedicts(player.ent, util.deref_pp_edict_t(data.ent)) and #clientargs == 2 and clientargs[1] == GAMECMD_GLOGIN) then        
                -- Notify the reply listener
                interrogator.replylistener(clientargs[2]) -- arg 2 is pwhash
                -- Cleanup
                listen.unreg(clientcommandlistener)
                -- We are done, unlock
                gbltable.interrogating = false
                -- Mark the time
                gbltable.lastinterrogation = os.time()
                -- Try to make the next interrogation, since we're finished
                gbl_tryinterrogation(player)
                -- The previous function call should return immediately...
                -- Drop this client command
                return intercept.DO_DROP
            end
        end
        listen.game.precall(GE_CLIENTCOMMAND, clientcommandlistener)
    end
    
        
    -- Call the dispatch listener with the callback function
    interrogator.dispatchlistener(performquery)
end
gbl_interrogate_function = gbl_interrogate

--- Sends a properly formatted query packet to the global login server.
-- @param command the command to send
-- @param info a table of information as key-value pairs to send with the query
-- @param listener a function that will be called with the query reply (see gbl_replylisteners for more info)
-- @return the uniqueid that was used to dispatch this query
local function gbl_sendquery(command, info, listener)
    assert(command ~= nil, "command cannot be nil")
    assert(info ~= nil, "info table cannot be nil")
    assert(listener ~= nil, "listener cannot be nil")
    assert(GBL_SERVERIP ~= nil, "GBL_SERVERIP cannot be nil (unresolved)")
    local urldata = nil
    local url = require("socket.url") -- luasocket
    -- Add an identifying key/value to all queries we send; this way jit can easily filter them.
    -- ... after all, we are duplicating queries made per client for name authing.
    info["agent"] = "ironmod"
    -- Add our uniqueid for this query (the GBL server replies with the uniqueid in its response)
    local uniqueid = gbl_uidval .. "x" .. math.random(1000, 50000);
    info["uniqueid"] = uniqueid;
    for key,value in pairs(info) do
        if(urldata ~= nil) then urldata = urldata .. "&" else urldata = "" end
        -- Assume the key is safe
        urldata = urldata .. key .. "=" .. url.escape(value)
    end        
    -- Add listener for the reply
    gbl_replylisteners[uniqueid] = listener    
    -- Dispatch packet
    local packet = SPECIALPACKET .. command .. "\n" .. urldata
    gbl_socket:send(packet)
    gbl_uidval = gbl_uidval + 1
    if(gbl_uidval > 65536) then gbl_uidval = 0 end -- Might as well bound it...
    return uniqueid
end
--- Parses a GBL response from the GBL server. This looks like an HTTP header
-- response. Note that this should NOT take the raw packet, but only packets
-- that are special and have been pulled out manually. This is important, since
-- a GBL response can have multiple replies in one packet.
-- @param packet the packet containing the data
-- @return the command the server sent as a reply (or nil if the packet could not be parsed)
-- @return a table of informational key-value pairs
local function gbl_parsegblresponsepacket(packet)
    local url = require("socket.url") -- luasocket
    -- Match command as early as possible (before \n) and then pull the rest of the data out
    local command, headerdata = string.match(packet, "^(.-)\n\n\nGlobalLoginSystem 1%.0\n\n(.*)$")
    if(command == nil or headerdata == nil) then
        -- Couldn't parse
        return nil, nil
    else
        -- Build info table
        local info = {}
        for key,value in string.gmatch(headerdata, "([^\n]-): ([^\n]*)") do
            info[key] = url.unescape(value)
        end
        -- Done!
        return command, info
    end
end
--- Handles a response from the GBL server and notifies anything that is 
-- waiting for a reply. This assumes that the remote ip/port was at least
-- first validated to see if it really does look like the GBL server.
-- @param packet the packet the GBL server sent us
local function gbl_onspecialpacket(packet) 
    -- The GBL server has some odd bugs where it will send us a literal "\n"
    -- when it should be sending the character itself. This corrects for it hackily...
    packet = packet.gsub(packet, "\\n", "\n")
    -- TODO: remove the above when the GBL server looks like it's fixed
    
    assert(packet ~= nil, "packet cannot be nil")
    local command, info = gbl_parsegblresponsepacket(packet)
   
    if(command ~= nil) then
        -- We parsed it okay
        local uniqueid = info["uniqueid"]
        if(uniqueid ~= nil) then -- If it doesn't have a uniqueid, we don't care
            local listenerfunc = gbl_replylisteners[uniqueid]
            if(listenerfunc ~= nil) then
                listenerfunc(command, info)
            end
        end
    else
        warn("Unparsable " .. #packet .. " byte packet from the GBL server")
    end
end
--- Handles a raw packet from the GBL socket. This is supposed to be one or
-- more special packets. Note that UDP fragmentation can truncate stuff the
-- server sends us, but I don't see how you can get around that.
-- This will try to parse out one or more special packets.
-- @param packet the raw packet we just received
local function gbl_handlepacket(packet) 
    assert(packet ~= nil, "packet cannot be nil")
    -- TODO/WARN: since our socket is "connected", can it receive stuff from other hosts? if so, that's bad -- fix it
    for specialpacket in string.gmatch(packet, "(" .. SPECIALPACKET .. ".*)") do
        -- Forward the packet, but strip off the special chars at the start
        gbl_onspecialpacket(string.sub(specialpacket, #SPECIALPACKET+1))
    end
end
--- This is meant for use inside a coroutine. It continually queries the GBL
-- socket for data, and when it gets it, reports it for parsing.
local function gbl_readsocket()
    while(gbl_socket ~= nil) do -- Don't stop trying to read until it is nil'd
        local packet = gbl_socket:receive() -- This blocks, but the asok wrapping should automagically yield the thread here
        if(packet ~= nil) then
            -- We got data!
            gbl_handlepacket(packet)
        end
        coroutine.yield() -- Just in case... 
    end
end
--- Tries to GBL authenticate a player. If the player owns then name they are
-- playing with, then they will successfully authenticate. If the player either
-- takes a name they do not own, or uses one that is owned by nobody, this
-- will silently ignore it and do nothing. The only purpose of this function
-- is to do the best job possible in getting a global login ID tied to the
-- player you provide, and emit the SE_RESOLVED_GBLID event when that completes.
-- Note that this will not query the GBL server until the dispatch takes place,
-- so any throttling that takes place in the dispatch naturally happens here
-- too. This is an extra safety feature to prevent the gamelib and our 
-- GBL server query from hitting at the same time.
-- @param player the player to authenticate with the global login system
local function gbl_authenticate(player)
    assert(player ~= nil, "player cannot be nil")
    
    local gbltable = gbl_getplayertable(player)
    
    -- The player name
    local player_name = player.name -- TODO: the reason you are doing this is if player.name were to change -- but, if it does change, all this listening stuff should die anyway, SO MAKE SURE IT IS DONE!
    -- The player GBL ID we found in vninit
    local player_id
    -- The string we are using for the challenge
    local player_randstr
    -- The string the player sent back to us as a response to the challenge
    local player_reply
    
    -- TODO: go through and handle failures to clean up resources!
    -- TODO: need a timeout? hrm??? (example: client never replies) - may not matter, since we only do only one of these per client, or SHOULD be doing that
    
    
    -- Handles our query to the client before being dispatched
    local dispatchhandler = function(performdispatch) 
        -- What we now want to do is hold off performing the actual dispatch
        -- until we get the vninit reply.
        
        -- Send a VNINIT to 1) verify a player even exists for this name, 2) get
        -- a random string that we will have the client use to verify their
        -- identity.        
        local initinfo = {username = player_name} -- Another field is port
        local vninit_uniqueid = gbl_sendquery(CMD_VNINIT, initinfo, function(initcmd, initinfo) 
            -- Reply callback
            dump.printtable(initinfo)
            local vninit_userid, vninit_randstr = initinfo["userid"], initinfo["randstr"]
            dump.printtable(initinfo)
            if(initinfo["ERROR"] == nil and vninit_userid ~= nil and vninit_randstr ~= nil) then
                -- No error in reply, userid and randstr was there, we're good
                player_id = tonumber(vninit_userid)
                player_randstr = vninit_randstr
                -- Perform client verification using the performdispatch function we were given
                performdispatch(GAMECMD_GLOGIN .. " " .. player_id .. " " .. player_randstr .. "\n")
            else
                -- We got a reply, but it was not a passing reply, so we'll
                -- now cancel our dispatch. Otherwise, we'd lock up the queue!
                performdispatch(nil)
                
                -- TODO: This should work fine, but what happens if the GBL server never replies? 
                -- Here's what happens: the GBL authentication queue gets stuck for this player!
                -- Now, admittedly, this won't happen very often, and it's only for this player,
                -- but you do need to consider implementing a timeout...
            end
        end) 
    end
    -- Handles the reply the client gives us
    local replyhandler = function(pwhash)
        player_reply = pwhash
        -- Ask GBL server if this is okay
        local verifyinfo = {username = player_name, pwhash = player_reply}
        local vn_uniqueid = gbl_sendquery(CMD_VN, verifyinfo, function(initcmd, initinfo)
            dump.printtable(initinfo)
            
            local status = initinfo["GameLoginStatus"] -- All we care about this passing
            if(status == "PASSED") then
                -- Player verified!
                player.gblid = player_id
                
                emitevent(SE_RESOLVED_GBLID, function(f) 
                    f(player)
                end)
            end
        end)    
    end
    
    -- Make the query, which will eventually call dispatchhandler
    gbl_queueclientquery(player, dispatchhandler, replyhandler)
end
-- This takes a GAMECMD_GLOGIN query that the gamelib tried to send to a client,
-- but we blocked it. It is here that we should process it using our own 
-- "interrogation queue."
-- @param player the player this is for
-- @param command the GAMECMD_GLOGIN command that was used by the gamelib, in its entirety
local function gbl_processgamelibquery(player, command)
    -- Handles the dispatch taking place
    local dispatchhandler = function(performdispatch) 
        -- There's not currently anything we need to do here; the gamelib can't
        -- send a query without getting it queued like usual, so we have
        -- nothing to block or any other duties related to that.
        performdispatch(command .. "\n")
    end
    -- Handles the reply the client gives us
    local replyhandler = function(pwhash)
        -- Pass this back to the gamelib, since it initiated the request
        local finishedcommands = spoofcommandargs({GAMECMD_GLOGIN, pwhash})
        ge.ClientCommand(player.ent) -- Pretend the client just now replied
        finishedcommands()
    end
    -- Queue the query
    gbl_queueclientquery(player, dispatchhandler, replyhandler) 
end
--- This is a function that handles time-related tasks, like resuming the
-- socket monitoring thread.
-- Simply add it as an event listener for event(s) that occur pretty 
-- often (ie: GE_RUNFRAME).
local function gbl_repeatlistener(data) 
    -- Resume our monitoring thread
    local result = coroutine.resume(gbl_read_co)
    if(result == false) then 
        -- The thread failed to resume, report this
        warn("FAILED TO RESUME gbl_read_co THREAD:")
        warn(luadebug.traceback(gbl_read_co))               
        -- TODO: things are pretty messed up now... consider just panicking and killing ironmod...although if you never handle errors, it won't matter...
        error("gbl_read_co failure")
    end
    
    -- Visit all players
    for i,player in pairs(players) do
        -- Check to see if we need to interrogate this player right now (necessary, as it may be time throttled, so we may call it many times)
        -- WARN: Do NOT just skip this if we already know the gblid; the interrogation queue is used for the gamelib's queries as well! 
        gbl_tryinterrogation(player)
    end
end
--- Called when a player joins the game or changes their name. If GBL usage
-- is disabled or we already have the player info we need, this does nothing.
-- @param player the player to check
local function gbl_checkplayer(player)
    if(config.GBL_MODE == "NETWORK") then
        if(config.GBL_ENABLED and player.gblid == nil) then  
            local gbltable = gbl_getplayertable(player)
            -- It is not safe to immediately try to authenticate the player if
            -- they just changed their name; for
            -- one reason or another, the gamelib sends its request just late enough
            -- that it WILL be sent during ours, which subsequently results in the
            -- gamelib kicking the user right after the queue'd up gamelib interrogation
            -- is let loose.   
            -- The solution? Wait a little while. Yeah, this sucks...
            -- TODO: if you ever integrate timers, here's a great candidate for them
            
            local timerfunc
            local stoptime = os.time() + config.GBL_QUERYTHROTTLE -- No particular reason to use GBL_QUERYTHROTTLE, it's just a nice a value...
            timerfunc = function()  
                if(gbltable.authtimer ~= timerfunc) then
                    -- We are no longer the timer in use, we are cancelled!
                    listen.unreg(timerfunc)
                else
                    -- Is the time right?
                    if(os.time() >= stoptime) then
                        -- Let's do it!                               
                        gbl_authenticate(player)
                        gbltable.authtimer = nil
                        listen.unreg(timerfunc)
                    end
                end
            end
            
            -- Store the timer function on the player; this way we can ensure only
            -- only one "timer" is going. No reason to have more than one...
            -- Note that any previous timer functions will notice this change and
            -- immediately stop themselves.
            gbltable.authtimer = timerfunc
            
            -- Just hook the timer function up to something that happens often...
            listen.game.postcall(GE_RUNFRAME, timerfunc)
        end
    elseif(config.GBL_MODE == "LOCAL") then
        -- Nothing to do...
    end
end
--- This function is used only if GBL_MODE is "LOCAL". It is called every so
-- often in order to update player ID information based off the "players"
-- command. "Every so often" is a few seconds or so. 
-- Note that this will emit SE_RESOLVED_GBLID automatically when a player's
-- ID is newly found.
local function gbl_localidupdate()
    -- TODO: make sure this emits any events it needs to
    
    -- Okay, we can't just put "sv players" into the console and intercept the
    -- result. Why? For some reason, the gamelib doesn't use DPRINTF, it just
    -- writes directly to STDOUT. To avoid some magical stream hijackage, we 
    -- will instead issue the "players" command as if it came from a client.
    -- Naturally, the gamelib will send the reply back to the client, but we
    -- will intercept it for our own use. 
    
    -- The player we will use
    local targetplayer = nil
    
    -- Find a player with a non-nil ent (may not need this, just a safety check)
    for i,player in pairs(players) do
        if(player.ent ~= nil) then 
            targetplayer = player
            break
        end
    end
    
    if(targetplayer == nil) then
        return -- No usable target player found, we give up
    end
    
    -- Prepare a listener to catch the results (the results come as a GIDP_CPRINTF)
    -- Note that this listener will block the call so it won't actually get
    -- printed to the random client we grab.
    local printlistener
    printlistener = function(data) -- Pre-call
        local ent = util.deref_pp_edict_t(data.ent)
        if(ent ~= nil and sameedicts(ent, targetplayer.ent)) then
            -- This is our player
            local text = util.deref_pp_char(data.ptr_formatted_string)
            
            -- Format:
            -- "PLAYERID (BOT/GBLID)] * NAME"
            -- examples:  " 0 (5000)] * ironfist" 
            --            " 3 (bot)] * ACEBot_5"
            --            " 0 ] * ironfist"  (ironfist did not have his GBL id confirmed from the login server, vninit was suppressed... same thing happens for names not tied to an account)
            -- Note that the * is a colored team splat
            local player_num, player_gblid = string.match(text, "^%s*([0-9]+)%s+%(([0-9]+)%)%] .*$")
            if(player_num ~= nil) then
                player_num = tonumber(player_num)
                -- Find and set the player's ID
                local referencedplayer = getplayerbynum(player_num)
                if(referencedplayer ~= nil and referencedplayer.gblid == nil) then -- We assume GBL ids never change once one is valid (same as network code)
                    -- We now know their ID!
                    referencedplayer.gblid = player_gblid
                    
                    emitevent(SE_RESOLVED_GBLID, function(f) 
                        f(referencedplayer)
                    end)
                end
            end
            
            -- Don't send this to the client!
            return intercept.DO_DROP
        end
    end
    
    listen.dp.precall(GIDP_CPRINTF, printlistener)
    
    -- Pretend our chosen player just sent "players" command
    local finishspoof = spoofcommandargs({"players"})
    ge.ClientCommand(targetplayer.ent)  

    -- We read in all the players, we're done (any of our CPRINTF events tool place inside ClientCommand)
    listen.unreg(printlistener)  
    finishspoof()
end

---------------
-- Listeners --
---------------
listen.game.precall(GE_CLIENTCONNECT, function(data)
    -- This is to block players from even connecting if we need to
    local blockplayer = false
    local blockreason = nil
    
    local ent = util.deref_pp_edict_t(data.ent)
    local ptr_userinfostring = util.get_char_pp_as_voidptr(data.userinfo) -- Returns a void*, so SWiG won't transform it into a Lua-internal string
    local userinfo = util.deref_pp_char(data.userinfo)
    --debug("(PRE) GE_CLIENTCONNECT: " .. tostring(userinfo))
    local table_userinfo = parseuserinfo(userinfo)
    
    -- Note: We are manipulating userinfo with the qshared Info_ functions
    local clientaddress = table_userinfo.ip
    if(clientaddress ~= nil) then
        local ip,port = string.match(clientaddress, "^(.*):([0-9]+)$") -- A failed match is practically impossible
        if(ip ~= nil) then
            -- See if we need to drop the player (the first func that tells us to do so will have its return data used, but other funcs still get the event after this)
            emitevent(SE_PRECONNECT, function(f) -- Send the event out
                local doblock,reason = f(ent, ip, port, table_userinfo)
                if(not blockplayer and doblock) then
                    -- Act on this handler's instruction
                    blockplayer = true
                    blockreason = reason
                end
            end)
            
            if(blockplayer) then -- TODO: if you ever write proper userinfo handling functions, this could benefit from them...
                -- To block a player, the return value of CLIENTCONNECT must evaluate to false (so, just return 0)
                -- We use only one int pointer for doing this...           
                data.retval = ptr_preconnect_returnval_blockplayer -- Declared for use in the entire session
                
                if(blockreason ~= nil) then
                    -- Do not allow backslashes in the ban reason, and do not allow it to go over the value size limit (64)
                    blockreason = string.gsub(blockreason, "\\", "")
                    if(#blockreason > qshared.MAX_INFO_VALUE-1) then
                        -- Truncate
                        blockreason = string.sub(blockreason, 1, qshared.MAX_INFO_VALUE-1)
                    end                    
                    -- Modify the userinfo to include a "rejmsg", our blockreason
                    table_userinfo.rejmsg = blockreason
                    local newuserinfo = userinfo .. "\\rejmsg\\" -- Add just the key
                    -- Do not allow the string to exceed the maximum size of a userinfo string
                    if(#newuserinfo > qshared.MAX_INFO_STRING - 1) then
                        -- We can't even fit in the key, no use even specifying a reject msg
                        newuserinfo = userinfo
                    else
                        -- Append val
                        newuserinfo = newuserinfo .. blockreason
                        if(#newuserinfo > qshared.MAX_INFO_STRING - 1) then
                            -- Truncate
                            newuserinfo = string.sub(newuserinfo, 1, qshared.MAX_INFO_STRING - 1)
                        end
                    end  
                    assert(#newuserinfo <= qshared.MAX_INFO_STRING - 1, "#newuserinfo not in MAX_INFO_STRING bounds!") -- Just to be sure...
                    -- Copy the new string over 
                    util.copystring(ptr_userinfostring, newuserinfo)
                end
                
                return intercept.DO_DROP -- Drop the call, we already set the return value we want
            end
        end
    else
        -- If the address is missing from userinfo, the gamelib will handle ejecting the player, we don't care
    end
end)
listen.game.postcall(GE_CLIENTCONNECT, function(data) 
    --debug("GE_CLIENTCONNECT", util.get_ptr_as_int(data.ent), util.deref_p_qboolean(data.retval))    
    --debug("data.userinfo", data.userinfo)
    if(util.deref_p_qboolean(data.retval) == 0) then
        debug("GAMELIB DROP")
        -- The gamelib is dropping this client, so let's ignore them
        return
    end
    
    local testp = getplayerbyent(data.ent)
    if(testp ~= nil) then 
        --debug("CONNECT IGNORE; ALREADY HAVE" .. tostring(testp.name))
        -- There is already a player allocated... it is currently possible for
        -- a single client to connect twice. To recreate this, just connect
        -- to the server, and right after that, connect again. Hopefully
        -- ignoring the second connection will work fine.
        
        -- TODO: may want to add an assertion to the "players" monitoring code
        -- that verifies that a player has the num they are supposed to have
        return
    end
        
    if(player_num_cache == nil) then
        error("expected player_name_cache to have a value") 
    elseif(player_num_cache == nil) then
        error("expected player_name_cache to have a value") 
    elseif(player_skin_cache == nil) then
        error("expected player_skin_cache to have a value") 
    end
    
    
    debug("GE_CLIENTCONNECT2", util.get_ptr_as_int(data.ent), util.deref_p_qboolean(data.retval))    
    debug("data.userinfo2", data.userinfo)
    
    -- Add a new player
    local player = getplayerbyent(data.ent, true) -- make new player if none exists (of course, it's always new!)
    player.starttime = os.time()
    player.ingame = false
    player.ent = data.ent
    player.info = parseuserinfo(data.userinfo)
    player.plugindata = {}
    player.alive = true -- TODO: IS THIS RIGHT?
    player.flags = 0
    player.holds = 0
    player.caps = 0
    player.grabs = 0
    player.kills = 0
    player.streak = 0
    player.deaths = 0
    player.access = 0
    player.gblid = nil
    player.discarded = false
    
    if(eventplayerent == nil) then
        -- This player should start getting events we need (the server had no players before this one)
        eventplayerent = player.ent
    end
    
    -- Note: taking data off the "ip" field is only safe here, since it is 
    -- written directly into the userinfo by the server and any existing
    -- "ip" instances are removed from the string. It is not, however, safe to
    -- ever use it again (the client can send a fake "ip" after this).
    -- Note: The gamelib will disconnect a client if they try to overflow the
    -- userinfo string to drop the ip. However, we will still get the overflowed
    -- string (a string so large that "ip" did not fit into it).
    if(player.info.ip ~= nil) then
        local ip,port = string.match(player.info.ip, "^(.+):([0-9]+)$")
        assert(ip ~= nil and port ~= nil, "client connected, but had unparsable 'ip' field: '"..tostring(player.info.ip).."'")
        player.ip = ip
        player.port = port
    else
        -- gamelib will drop the client... but I think it happens just a little bit later from now
    end
    
    --- Set their player num and actual name getting used
    player.num = player_num_cache
    player.name = player_name_cache
    player.skin = player_skin_cache
    player_num_cache = nil
    player_name_cache = nil
    player_skin_cache = nil
    debug(" == > GE_CLIENTCONNECT RESETTING CACHE VALUES")
    
    -- GBL authenticate their name right away
    gbl_checkplayer(player)
end)
listen.game.postcall(GE_CLIENTBEGIN, function(data)
    debug(" == > GE_CLIENTBEGIN", util.get_ptr_as_int(data.ent))
    -- Update the player's status so that they are now in the game
    local player = getplayerbyent(data.ent)
    assert(player ~= nil, "something is wrong, the player should already have been stored")
    player.ingame = true -- TODO: they're not in the game after another map change, so set this to false at map change?
end)
listen.game.postcall(GE_CLIENTUSERINFOCHANGED, function(data) 
    -- Update the player's userinfo
    local player = getplayerbyent(data.ent)
    assert(player ~= nil, "something is wrong, the player should already have been stored")
    player.info = parseuserinfo(data.userinfo)
end)
listen.game.postcall(GE_CLIENTDISCONNECT, function(data) 
    debug(" == > GE_CLIENTDISCONNECT")
    -- Remove the player from our table
    removeplayerbyent(data.ent)
end)
listen.game.precall(GE_SPAWNENTITIES, function(data)
    -- This happens every time a new map is loaded, and we may have clients that are connected.
    -- We need to set their in-game status to false since they are now loading up their own stuff. 
    -- We will get a GE_CLIENTBEGIN when they've joined back up with us.
    for key,player in pairs(players) do
        player.ingame = false
    end
end)
listen.dp.postcall(GIDP_CONFIGSTRING, function(data) 
    -- Store the configstring
    configstrings[data.num] = data.string
        
    -- Handle player name/skin changes that automagically take place
    if(data.num >= CS_PLAYERSKINS and data.num <= CS_PLAYERSKINS_END) then
        if(#data.string == 0) then return end -- We seem to get this set to a blank string when the player disconnects
        local clientindex = data.num - CS_PLAYERSKINS
        -- This is where we identify what "client index" this player has. This is used for the server/client internals and for EVENT_*.
        -- The string itself is in the form "PLAYERNAME\SKINPATH" (ex: "myname\male/pb2b"), where SKINPATH is mostly useless to us.
        -- Find the player we have by that name, and store their client index. Again, this is very useful to tie our own players to those that crop up in EVENTs.
        local player = getplayerbynum(clientindex)
        local playername,playerskin = string.gmatch(data.string, "(.-)\\([^\\]*)")()
        assert(playername ~= nil and playerskin ~= nil, "couldn't parse '"..tostring(data.string).."'")
        if(player == nil) then -- we don't have this player stored yet, so they must be about to connect
            assert(playername ~= nil, "fatal: couldn't find the player name in CS_PLAYERSKINS index " .. tostring(data.num) .. ", value '" .. tostring(data.string) .. "'")
            -- Store them in the cache (this configstring currently comes before the CONNECT event, so we have no player to assign a num to)
            player_num_cache = clientindex
            player_name_cache = playername
            player_skin_cache = playerskin
        else -- We already have the player stored, just change their name
            local oldname = player.name
            player.name = playername
            player.skin = playerskin
            
            -- We are pretty much guaranteed to see this right after a client connects, even though we already have their name...
            if(oldname ~= player.name) then
                gbl_checkplayer(player) -- A name change may require a new auth attempt
                
                -- Emit event
                emitevent(SE_NAMECHANGE, function(f) 
                    f(player, oldname)
                end)
            end
        end
    end
end)
listen.game.precall(GE_CLIENTCOMMAND, function(data)
    local commands = server.getcommandargs()
    local gotchat = false
    local player = getplayerbyent(util.deref_pp_edict_t(data.ent))
    
    -- Handle what could potentially be a command that a plugin might want to catch (like rockthevote, votemap, etc.)
    -- Note: this does not catch people who chat from the console with no "say" cmd, etc.
    if(gidp.argc() >= 2) then
        local cmd = string.upper(commands[1])
        local chatcmd = nil
        local chatargs = ""
        
        -- TODO: when you revise this, also fix the problem where "say bleh args" works fine, but if you do it in the console, it won't work, since it's "say" "bleh" "args"
        if(cmd == "SAY" or cmd == "SAY_TEAM" or cmd == "MESSAGEMODE" or cmd == "MESSAGEMODE2") then
            local teamchat = false
            
            local chatcmd = cmd
            for i=2,#commands do
                chatargs = chatargs .. commands[i]
                if(i < #commands) then chatargs = chatargs .. " " end
            end
            
            if(chatcmd == "SAY_TEAM" or chatcmd == "MESSAGEMODE2") then teamchat = true end            
            local text = chatargs
            gotchat = true
            
            local player = getplayerbyent(util.deref_pp_edict_t(data.ent)) -- dereference the pointer for ent!
            local blockchat = false
            emitevent(SE_CHAT, function(f) -- Send the event out
                if(f(player, text, teamchat)) then blockchat = true end
            end)
            if(blockchat) then
                debug("BLOCK CHAT CMD:", player.name, text)
            end
            debug("BLOCK?", blockchat, text)
            
            if(blockchat == true) then 
                return intercept.DO_DROP 
            else
                return intercept.DO_ALLOW
            end
        end
    end
    
    if(not gotchat and player ~= nil) then
        -- This is used to drop all the rest of the CPRINTFs (we get a broadcast for the chat, then individual client SE-style messages encoded)
        local dropallcprintf = false
        -- In order to capture the chat of players who enter their stuff directly
        -- at the console (so that their chat is quite literally just the commands
        -- send), we must watch for the gamelib trying to CPRINTF a chat message
        -- from the player, block it, and run it through our own mechanism.
        chatprintflistener = function(chatdata)
            if(dropallcprintf) then return intercept.DO_DROP end
            
            local text = util.deref_pp_char(chatdata.ptr_formatted_string)
            local ent = util.deref_pp_edict_t(chatdata.ent)
            if(ent == nil) then -- broadcast (players don't actually see this, they get individual encoded messages, like we generate GE_ events off of)
                -- Build what their chat string would've looked like from the commands they sent earlier
                local chatargs = ""
                for i=1,#commands do
                    chatargs = chatargs .. commands[i]
                    if(i < #commands) then chatargs = chatargs .. " " end
                end
                text = string.gsub(text, "\n", "") -- Take the newline off the end
                
                -- Get their name
                local strippedname = stripgarbage(player.name)
                
                local regularmatch = strippedname .. ": " .. chatargs
                -- Does it match this cprintf? (note: speaking into the console results in what is essentially the same as SAY)
                -- Note: People can be prefixed with [ELIM] and stuff, so let's start matching leniently (should be safe, since we're checking in a very specific circumstance)
                if(string.match(text, "^.-" .. escapepatterntext(regularmatch) .. "$")) then
                    -- Yes!
                    local blockchat = false
                    emitevent(SE_CHAT, function(f) -- Send the event out
                        if(f(player, chatargs, false)) then blockchat = true end
                    end)
                    if(blockchat) then
                        debug("CONSOLE BLOCKCHAT:", player.name, chatargs)
                    end
                    if(blockchat) then 
                        debug("********* DROPPING CPRINTF NEXT ****************")
                        dropallcprintf = true -- Block all messages after this one too
                        return intercept.DO_DROP 
                    end -- Do not print the chat message if we're not supposed to
                end
            end
        end
    end
end)
listen.game.postcall(GE_CLIENTCOMMAND, function(data)
    -- Get rid of our previous chat listener (any CPRINTF for chat takes place between pre/post)
    chatprintflistener = nil
end)
listen.game.precall(GE_SPAWNENTITIES, function(data)    
    -- This is how we identify a map change
    local mapname = util.deref_pp_char(data.mapname)
    emitevent(SE_MAPCHANGE, function(f) -- Send the event out
        f(mapname)
    end)
end)
listen.dp.postcall(GIDP_SOUNDINDEX, function(data) 
    -- Store this sound
    sounds[util.deref_p_int(data.retval)] = data.name
end)
listen.dp.postcall(GIDP_MODELINDEX, function(data) 
    -- Store this model
    models[util.deref_p_int(data.retval)] = data.name
end)
listen.dp.postcall(GIDP_CPRINTF, function(data) 
    -- WARNING: this relies on getarbitraryplayerent() always returning the same player (in this case, the first entry the table hashing has pulled) in order to emit only one event at a time properly
    
    if(data.printlevel == PRINT_SCOREDATA and data.ent ~= nil) then
        if(true) then return end -- TODO: finish implementing this? I don't need it so far...
        -- Note: SCOREDATA is the only way to get a player's team if they just
        -- joined the server, since the EVENT_* stuff reports the wrong team at
        -- first.
        -- Note: Follows all the same rules as PRINT_EVENT
        if(hashplayerent(data.ent) == hashplayerent(getarbitraryplayerent())) then      
            local temp_array = util.allocate_int_array(cl_decode.MAX_DECODE_ARRAY)
            local SCORESIZE = 10 -- A constant pulled from cl_decode
            local numelements = cl_decode.decode_unsigned(util.charptr_to_unsigned(data.formatted_string), util.intptr_to_unsigned(temp_array), cl_decode.MAX_DECODE_ARRAY);
            local numentries = numelements / SCORESIZE
            local j = 0
            -- We read data from the array in the following order:
            -- clientindex,isalive,hasflag,team,ping,kills,deaths,grabs,caps,starttime
            for i=1,numentries do
                local clientindex = util.get_intarray_val(temp_array, j)
                local isalive = util.get_intarray_val(temp_array, j+1)
                local hasflag = util.get_intarray_val(temp_array, j+2)
                local teamnum = util.get_intarray_val(temp_array, j+3)
                local ping = util.get_intarray_val(temp_array, j+4)
                local kills = util.get_intarray_val(temp_array, j+5)
                local deaths = util.get_intarray_val(temp_array, j+6)
                local grabs = util.get_intarray_val(temp_array, j+7)
                local caps = util.get_intarray_val(temp_array, j+8)
                local starttime = util.get_intarray_val(temp_array, j+9)
                j = j + SCORESIZE
            end
            util.deallocate_mem(temp_array)
        end
    elseif(data.printlevel == PRINT_EVENT and data.ent ~= nil) then
        if(hashplayerent(data.ent) == hashplayerent(getarbitraryplayerent())) then
            -- Note: remember that these get sent directly to clients. if all you've got bots in the game, you can't get these. this is one among many of the reasons ironmod is not bot-friendly.
            -- Note: What follows is basically what CL_ParsePrintEvent does
            -- Allocate an array to store the data
            local index_array = util.allocate_int_array(cl_decode.MAX_DECODE_ARRAY)
            -- Decode it
            local numelements = cl_decode.decode_unsigned(util.charptr_to_unsigned(data.formatted_string), util.intptr_to_unsigned(index_array), cl_decode.MAX_DECODE_ARRAY);
            assert(numelements >= 1, "numelements is too low, the EVENT encoding implementation might've changed")
            -- Note: it is necessary to translate the string, as there may be trailing information after the translate that we are to pick up below
            local currentindex = 2
            local eventformat = getconfigstring(CS_EVENTS+util.get_intarray_val(index_array, 1))
            local translatedtext
            currentindex, translatedtext = decode_translate_string(eventformat, index_array, numelements, currentindex)

            --- Event handling begin ---
            -- Note: clientindex corresponds to an index relative to CS_PLAYERSKINS where you can pull player name and skin information from. the game sets this information, so we should have it.
            local eventid = util.int_to_unsigned(util.get_intarray_val(index_array, 0))
        
            -- Handle events which are "global", that is, not sent to just specific clients
            if(eventid == qshared.EVENT_ENTER) then
                -- TODO: MAKE THE PLAYER ALIVE HERE OR IN BEGIN MAYBE? also, may be a good place to reset scores etc., since a client can stay for a new game? hrm?
                assert(numelements > 2)
                local clientindex = util.get_intarray_val(index_array, 2)
                local teamnum -- optional, second-to-last arg
                local starttime -- optional, last arg
                if(currentindex < numelements) then
                    teamnum = util.get_intarray_val(index_array, currentindex)
                    currentindex = currentindex + 1
                    if(currentindex < numelements) then
                        -- This is relative to server start time or something... either way, we keep track of starting time our own way and don't need this
                        starttime = util.get_intarray_val(index_array, currentindex)
                    end
                end                
                local teamindex = TEAM_NONE
                if(teamnum ~= nil and teamnum >= 1 and teamnum <= 4) then teamindex = teamnum2index(teamnum) end
                local p = getplayerbynum(clientindex)
                if(p == nil) then
                    warn(p ~= nil, "no stored player for EVENT_ENTER '" .. tostring(translatedtext) .. "' -- maybe it's just a bot")
                    return
                end
                if(teamindex == nil) then teamindex = TEAM_NONE end -- Player is starting in observer
                p.teamindex = teamindex -- Set the player's team  
                debug("SE_ENTER   ******", p.name, teamindex, getteamname(teamindex), "...", teamnum, teamindex)
                emitevent(SE_ENTER, function(f) -- Send the event out
                    f(p, translatedtext)
                end)            
            elseif(eventid == qshared.EVENT_DISCONNECT) then
                assert(numelements > 2)
                local clientindex = util.get_intarray_val(index_array, 2)
                local p = getplayerbynum(clientindex)
                if(p == nil) then
                    warn("no stored player for EVENT_DISCONNECT '" .. tostring(translatedtext) .. "' -- maybe it is just a bot")    
                    return -- It was a bot, probably
                end     
                emitevent(SE_DISCONNECT, function(f) -- Send the event out
                    f(p, translatedtext)
                end)         
            elseif(eventid == qshared.EVENT_JOIN) then
                assert(numelements > 3)
                local clientindex = util.get_intarray_val(index_array, 2)
                local teamnum = util.get_intarray_val(index_array, 3)
                local p = getplayerbynum(clientindex)
                assert(p ~= nil, "no stored player for EVENT_JOIN '" .. tostring(translatedtext) .. "'")    
                local oldteamindex = p.teamindex
                p.teamindex = teamnum2index(teamnum)
                if(p.teamindex == nil) then p.teamindex = TEAM_NONE end -- Player joined observer
                debug("SE_JOINTEAM", p.name, p.teamindex, getteamname(p.teamindex))
                emitevent(SE_JOINTEAM, function(f) -- Send the event out
                    f(p, oldteamindex, translatedtext)
                end)        
            elseif(eventid == qshared.EVENT_ROUNDOVER) then
                -- Let's basically guess who won, hopefully this string doesn't change much (it's a literal string, not formatted with teamindex, etc.
                local teamindex = TEAM_NONE
                local txt = string.lower(translatedtext)
                if(string.find(txt, "red ")) then
                    teamindex = TEAM_RED
                elseif(string.find(txt, "blue ")) then
                    teamindex = TEAM_BLUE
                elseif(string.find(txt, "yellow ")) then
                    teamindex = TEAM_YELLOW
                elseif(string.find(txt, "purple ")) then
                    teamindex = TEAM_PURPLE
                end
                emitevent(SE_ROUNDOVER, function(f) -- Send the event out
                    f(teamindex, translatedtext)
                end)      
            elseif(eventid == qshared.EVENT_OVERTIME) then
                emitevent(SE_OVERTIME, function(f) -- Send the event out
                    f(translatedtext)
                end)    
            elseif(eventid == qshared.EVENT_ROUNDSTART) then
                -- Make all the players on a team alive and reset their flags count
                for i,player in pairs(players) do
                    if(player.teamindex ~= TEAM_NONE) then 
                        player.alive = true 
                        player.flags = 0
                    end
                end
                emitevent(SE_ROUNDSTART, function(f) -- Send the event out
                    f(translatedtext)
                end) 
            elseif(eventid == qshared.EVENT_KILL) then
                -- remember bots...
                assert(numelements >= 4)
                local killerplayer = getplayerbynum(util.get_intarray_val(index_array, 2))
                local killerwepindex = util.get_intarray_val(index_array, 3)
                local victimplayer =  getplayerbynum(util.get_intarray_val(index_array, 4))
                local victimwepindex =  util.get_intarray_val(index_array, 5)
                if(killerplayer ~= nil) then
                    killerplayer.kills = killerplayer.kills + 1
                    killerplayer.streak = killerplayer.streak + 1
                end
                if(victimplayer ~= nil) then
                    playerdied(victimplayer)
                end
                emitevent(SE_KILL, function(f) -- Send the event out
                    f(killerplayer, killerwepindex, victimplayer, victimwepindex, translatedtext)
                end) 
            elseif(eventid == qshared.EVENT_SUICIDE) then
                assert(numelements > 2)
                -- The format string always specifies one client index (at least for self-paintgren/drowning/lava)
                local clientindex = util.get_intarray_val(index_array, 2)
                local p = getplayerbynum(clientindex)
                if(p ~= nil) then
                    playerdied(p)
                end
                emitevent(SE_SUICIDE, function(f) -- Send the event out
                    f(p, translatedtext)
                end) 
            elseif(eventid == qshared.EVENT_FFIRE) then
                assert(numelements >= 4)
                local killerplayer = getplayerbynum(util.get_intarray_val(index_array, 2))
                local victimplayer = getplayerbynum(util.get_intarray_val(index_array, 3))
                if(victimplayer ~= nil) then
                    playerdied(victimplayer)
                    victimplayer.deaths = victimplayer.deaths - 1 -- the victim does not actually get a death added to their scores, so remove the one that just got added
                end
                emitevent(SE_FFIRE, function(f) -- Send the event out
                    f(killerplayer, victimplayer, translatedtext)
                end) 
            elseif(eventid == qshared.EVENT_RESPAWN) then
                assert(numelements >= 3)
                local player = getplayerbynum(util.get_intarray_val(index_array, 2))
                if(player ~= nil) then
                    player.alive = true
                end
                emitevent(SE_RESPAWN, function(f) -- Send the event out
                    f(player, translatedtext)
                end) 
            elseif(eventid == qshared.EVENT_GRAB) then
                assert(numelements >= 3)
                local player = getplayerbynum(util.get_intarray_val(index_array, 2))
                if(player ~= nil) then
                    -- For each flag you grab, you get one grab event
                    player.flags = player.flags + 1
                    player.grabs = player.grabs + 1
                    player.holds = player.holds + 1
                end
                emitevent(SE_FLAGGRAB, function(f) -- Send the event out
                    f(player, translatedtext)
                end) 
            elseif(eventid == qshared.EVENT_DROPFLAG) then
                assert(numelements >= 3)
                local player = getplayerbynum(util.get_intarray_val(index_array, 2))
                if(player ~= nil) then
                    -- One flag drop event drops all of your flags
                    -- Note that the drop event does NOT take place if you die, so the holds should be fine
                    player.holds = player.holds - player.flags
                    player.flags = 0
                end
                emitevent(SE_FLAGDROP, function(f) -- Send the event out
                    f(player, translatedtext)
                end) 
            elseif(eventid == qshared.EVENT_CAP) then
                assert(numelements >= 3)
                local player = getplayerbynum(util.get_intarray_val(index_array, 2))
                if(player ~= nil) then
                    -- For each flag you hold, you get one cap event         
                    player.caps = player.caps + 1
                    player.flags = player.flags - 1
                end
                emitevent(SE_FLAGCAP, function(f) -- Send the event out
                    f(player, translatedtext)
                end) 
            end
            
        else
            -- Handle events sent to a specific client
            if(eventid == qshared.EVENT_ADMINKILL) then
                -- TODO: "kill" doesn't work, maybe jit removed it from the game? find it later and make sure this parsing code works...
                -- if it's not in the game, remove this event. btw, this will die if you killed a bot I think.s
                if(true) then return end
                
                local p = getplayerbyent(data.ent)
                assert(p ~= nil, "expected to be able to obtain a player for EVENT_ADMINKILL")
                -- TODO: I wonder if I should really be treating this like a normal death...
                playerdied(p)
                p.deaths = p.deaths - 1 -- you don't actually get a death for an admin kill
                -- The parsing is a little crazy for this, but it's marked jitodo...
                if(numelements > 2 and util.get_intarray_val(index_array, 2) == p.num) then
                    if(numelements > 3) then
                        local adminplayer = getplayerbynum(util.get_intarray_val(index_array, 3))
                        assert(adminplayer ~= nil, "expected adminplayer to be non-nil in EVENT_ADMINKILL")
                        local txt = "Admin " .. tostring(adminplayer.name) .. " killed " .. tostring(p.name)
                        emitevent(SE_ADMINKILL, function(f) -- Send the event out
                            f(player, adminplayer, txt)
                        end) 
                    else
                        -- We don't know who did it
                        local txt = "Unknown admin killed " .. tostring(p.name)
                        emitevent(SE_ADMINKILL, function(f) -- Send the event out
                            f(player, nil, txt)
                        end) 
                    end
                end
            end
        end
        --- Event handling end ---
        
        -- Deallocate the storage array
        util.deallocate_mem(index_array)
    end
end)

-----------------------
-- General execution --
-----------------------
-- Initializes the network buffer filtering
if(config.NET_FILTERBUFFER_ENABLED) then
    -- Register listeners
    listen.dp.precall(GIDP_WRITECHAR,       net_writehandler)
    listen.dp.precall(GIDP_WRITEBYTE,       net_writehandler)
    listen.dp.precall(GIDP_WRITESHORT,      net_writehandler)
    listen.dp.precall(GIDP_WRITELONG,       net_writehandler)
    listen.dp.precall(GIDP_WRITEFLOAT,      net_writehandler)
    listen.dp.precall(GIDP_WRITESTRING,     net_writehandler)
    listen.dp.precall(GIDP_WRITEPOSITION,   net_writehandler)
    listen.dp.precall(GIDP_WRITEDIR,        net_writehandler)
    listen.dp.precall(GIDP_WRITEANGLE,      net_writehandler)
    listen.dp.precall(GIDP_UNICAST,         net_netcasthandler)
    listen.dp.precall(GIDP_MULTICAST,       net_netcasthandler)  
end

-- Initializes GBL mode
if(config.GBL_MODE == "NETWORK") then
    -- Initializes networked GBL support
    if(config.GBL_ENABLED) then
        -- Resolve the global login server address
        local extendedinfo
        print("Resolving global login server address " .. config.GBL_SERVERHOST .. " ...");
        GBL_SERVERIP,extendedinfo = socket.dns.toip(config.GBL_SERVERHOST)
        if(GBL_SERVERIP ~= nil) then 
            print("Address resolved to " .. GBL_SERVERIP .. " -- now setting up socket")
            -- Prepare socket for GBL queries
            gbl_socket = asok.wrap(socket.udp()) -- Make sure we get asok's functionality // TODO: this can also take a timeout...do we need it?
            gbl_socket:setpeername(GBL_SERVERIP, config.GBL_SERVERPORT)
            gbl_read_co = coroutine.create(gbl_readsocket) -- Start a thread for our socket monitoring function
        
            -- Add a listener for event(s) which occur pretty often, so that our
            -- gbl code can do stuff time related.
            listen.game.postcall(GE_RUNFRAME, gbl_repeatlistener) -- TODO/WARN: packet forgery attacks (or just taking packets from ANYONE) could fill up the receive buffer and make us unable to process GBL replies... fix this later if we need to
        
            -- Watch for the gamelib trying to send a stuff to a client to verify
            -- them, then block it and put it in our own interrogation queue.
            if(not config.NET_FILTERBUFFER_ENABLED) then error "GBL is enabled, but NET_FILTERBUFFER_ENABLED is not" end
            local loginfilter = function(writebuffer, data, typeid)
                if(typeid == GIDP_UNICAST) then
                    -- This handles multiple stuffs in one flush
                    local index = nil
                    local hasanothermatch = true
                    while(hasanothermatch) do
                        index = net_findsequence(writebuffer, {GIDP_WRITEBYTE,GIDP_WRITESTRING}, index) -- Start from last time
                        if(index ~= nil) then
                            -- Extract values
                            local write_byte = writebuffer[index].val
                            local write_string = writebuffer[index+1].val
                            
                            -- NOTE: More that one command can go in a stuff, but global_login is always by itself (well, for b21 it is)
                            -- Are they a stuff?
                            if(write_byte == 0x0b and string.match(write_string, "^"..GAMECMD_GLOGIN.." %d+ .*$")) then
                                -- This was a stuff, remove it from the buffer
                                table.remove(writebuffer, index) -- Remove byte
                                table.remove(writebuffer, index) -- Remove string
                                -- Now, handle the query (trim off the trailing \n)
                                local clientquery = string.sub(write_string, 1, #write_string-1)
                                gbl_processgamelibquery(getplayerbyent(util.deref_pp_edict_t(data.ent)), clientquery)
                                -- We leave index alone, since it now points to fresh data anyway
                            else
                                -- Not a stuff, move index up past this sequence match
                                index = index + 2
                            end
                        else
                            hasanothermatch = false -- Last match, we're done
                        end
                    end
                end
            end   
            net_registerfilter(loginfilter) -- Register it so it will begin receiving calls when net buffer is flushed
        else
            warn("Unable to resolve GBL address (" .. tostring(extendedinfo) .. ")") -- TODO: write code to handle failures at GBL resolution, and try again later??
        end
    else
        warn("Use of the networked global login system is disabled in the configuration file, no GBL-related services will be available")
    end
elseif(config.GBL_MODE == "LOCAL") then 
    -- Call the gbl_localidupdate every GBL_LOCALUPDATERATE seconds
    local lasttime = os.time()
    listen.game.postcall(GE_RUNFRAME, function()
         if(math.abs(os.difftime(lasttime, os.time())) >= config.GBL_LOCALUPDATERATE) then
            -- Update
            gbl_localidupdate()
            lasttime = os.time()
         end
    end)
else
    error("Unknown value for GBL_MODE:" .. tostring(config.GBL_MODE));
end

-- Initializes the message throttling for our printline* functions
listen.game.postcall(GE_RUNFRAME, function()
     if(net_remainingmessages > 0) then
        -- Reset all player net settings for messaging
        for i,player in pairs(players) do
            if(net_remainingmessages == 0) then
                return -- No reason to continue, no more players have messages
            end
            
            local netsettings = net_getplayertable(player)
            
            -- Player's dispatched bytes for this run
            local msgdispatchedbytes = 0
            
            if(#netsettings.msgqueue >= config.NET_SAFEPRINTLINE_MAXQ) then
                -- This client has way too many messages left, we need
                -- to tell them that and dump their queue.
                gidp.cprintf(player.ent, PRINT_HIGH, "ironmod: NET_SAFEPRINTLINE_MAXQ exceeded, you have too many messages awaiting receival, they have been discarded.")
                net_remainingmessages = net_remainingmessages - #netsettings.msgqueue
                netsettings.msgqueue = {}                    
            end
            
            -- Send as many messages from the player's message queue
            -- as we can.
            local sendmessages = true -- Set to false to stop sending messages to client
            while(sendmessages and #netsettings.msgqueue > 0) do
                -- Peek at the next thing we'd dequeue; if it will overflow our limit, then go to next player (note that if it is the first message of the frame, it is always sent (msgdispatchedbytes==0))
                if(msgdispatchedbytes > 0 and #(netsettings.msgqueue[#netsettings.msgqueue].message) + msgdispatchedbytes > config.NET_SAFEPRINTLINE_MAXBYTES) then
                    sendmessages = false -- Go to the next player
                else
                    -- Next message is okay, dequeue send it
                    net_remainingmessages = net_remainingmessages - 1
                    local entry = table.remove(netsettings.msgqueue, #netsettings.msgqueue)
                    msgdispatchedbytes = msgdispatchedbytes + #entry.message
                    gidp.cprintf(player.ent, entry.printlevel, entry.message)
                end
            end
        end            
     end
end)

-- Register a CPRINTF listener that will be used to trap console message chat
listen.dp.precall(GIDP_CPRINTF, chattrap)

-- Force garbage collection every time a new map loads
addeventlistener(package.loaded.plugin_sdebug, SE_MAPCHANGE, function()
    print("Performing Lua garbage collection for map change")
    collectgarbage("collect")
end)
