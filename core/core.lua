------------------------------------------------------
--                                                  -- 
-- This is IronMod's core library, which is largely --
-- tasked with interfacing the C code.              --
-- Do not modify.                                   --
--                                                  --
------------------------------------------------------
-- Don't start until essential tables are ready (this can result from an error in the C lua loading code)
assert(geinterceptcontrol~=nil,      "table 'geinterceptcontrol' is not loaded")
assert(gidpinterceptcontrol~=nil,    "table 'gidpinterceptcontrol' is not loaded")
assert(geeventdata~=nil,             "table 'geeventdata' is not loaded")
assert(gidpeventdata~=nil,           "table 'gidpeventdata' is not loaded")
assert(geproxy~=nil,                 "table 'geproxy' is not loaded")
assert(gidpproxy~=nil,               "table 'gidpproxy' is not loaded")
assert(ge~=nil,                      "table 'ge' is not loaded")
assert(gidp~=nil,                    "table 'gidp' is not loaded")
assert(qshared~=nil,                 "table 'qshared' is not loaded")
assert(game~=nil,                    "table 'game' is not loaded")
assert(cl_decode~=nil,               "table 'cl_decode' is not loaded")
             
             
-- Used for serialization
local url = require("socket.url")

--- Array of all loaded plugins. All of these should be loaded as modules, too. 
plugins = {}

--- A reference to the lua standard debugging library.
luadebug = debug

-- Redirect global print so as to make it explode
printstdout = print; -- save a reference in case we want it later...
function print() 
    error("Global print is not allowed, please use a proper printing function or initialize your plugin properly.")
end

--- Prints text out to the console.
 -- @param section a short one-word tag for this text
 -- @param text the informational text to display
function printconsole(section, text)
    util.Print("=->IronMod Lua [" .. section .. "] " .. text .. "\n")
end

--- Formats multiple arguments to fit in one line,
 -- sort of like the default print() function.
 -- @param ... multiple arguments to format
function formatforprint(...) 
    return dump.formatarray("\t ", arg)
end

--- A printing function for plugins to use
 -- @param plugname a short plugin name
 -- @param text the text to print
function pluginprint(plugname, text) 
    printconsole("PLUG:" .. plugname, text)
end

-- Our own print functions
local function print(...)
    printconsole("CORE", formatforprint(...))
end
local function warn(...)
    printconsole("CORE", "WARNING: " .. formatforprint(...))
end
local function debug(...)
    printconsole("CORE", "Debug: " .. formatforprint(...))
end

--******************************
-- Dump functions for debugging.
--******************************
--- Contains specialized functions for debugging, which can dump out information
-- for various data structures.
dump = {}
--- Dumps a table recursively. Does not output "private/internal" underscore (_) keys.
 -- @param table the table to dump
 -- @param depth an optional depth to display at
 -- @param maxdepth the maximum literal depth to go to (may be nil)
function dump.printtable(table, depth, maxdepth) 
    if(maxdepth == 0) then return end
    if(depth == nil) then depth = 0 end
    if(maxdepth == nil) then maxdepth = 99999 end
    assert(type(table) == "table", "argument 'table' is not of type table")
    for k,v in pairs(table) do
        if(not string.find(tostring(k), "^_")) then -- Don't print keys starting with _
            debug(string.format("%" .. depth .. "s %-15s = %s", "", tostring(k), tostring(v)))
            if(type(v) == "table") then dump.printtable(v, depth + 4, maxdepth - 1) end
        end
    end
end
--- Dumps an entity (edict_*).
-- @param e the entity to print out
-- @param depth an optional depth
function dump.printent(e, depth) 
    local prefix, depth = dump.formatdepth(depth)
    if(e == nil) then
        debug(prefix.."ENTITY IS NULL")
    else
        debug(prefix.."Entity dump for:", e)
        debug(prefix.."inuse:" .. e.inuse)
        debug(prefix.."linkcount:" .. e.linkcount)
        debug(prefix.."svflags:" .. e.svflags)
        debug(prefix.."mins:" .. extra.vec3tostring(e.mins), "maxs:" .. extra.vec3tostring(e.maxs)) 
        debug(prefix.."absmin:" .. extra.vec3tostring(e.absmin), "absmax:" .. extra.vec3tostring(e.absmax), "size:" .. extra.vec3tostring(e.size))
        debug(prefix.."solid:" .. e.solid, "clipmask:" .. e.clipmask) 
        debug(prefix.."s (entity_state_t):") 
        dump.printentstate(e.s, depth + 4)    
        debug(prefix.."client (gclient_s):") 
        dump.printclient(e.client, depth + 4)  
        debug(prefix.."owner (edict_t):") 
        dump.printent(e.owner, depth + 4) 
    end 
end
--- Dumps an entity state (entity_state_t).
-- @param s the entity state to print out
-- @param depth an optional depth
function dump.printentstate(s, depth) 
    local prefix, depth = dump.formatdepth(depth)
    debug(prefix.."Entity state dump for:", s)
    debug(prefix.."number:" .. s.number)
    debug(prefix.."origin:" .. extra.vec3tostring(s.origin), "old_origin:" .. extra.vec3tostring(s.old_origin))
    debug(prefix.."angles:", extra.vec3tostring(s.angles))
    debug(prefix.."modelindex:" .. s.modelindex, "modelindex2:" .. s.modelindex2, "modelindex3:" .. s.modelindex3, "modelindex4:" .. s.modelindex4)
    debug(prefix.."frame:" .. s.frame, "skinnum:" .. s.skinnum, "effects:" .. s.effects, "renderfx:" .. s.renderfx)
    debug(prefix.."solid:" .. s.solid, "sound:" .. s.sound, "event:" .. s.event)
end
--- Dumps a client (gclient_*).
-- @param c the client to print out
-- @param depth an optional depth
function dump.printclient(c, depth) 
    local prefix, depth = dump.formatdepth(depth)
    if(c == nil) then
        debug(prefix.."CLIENT IS NULL")
    else
        debug(prefix.."Client dump for:", c)
        debug(prefix.."ping:" .. c.ping)
    end
end
--- Dumps a client/user command, which pertains to player movement (usercmd_t).
-- @param c the usercmd to print out
-- @param depth an optional depth
function dump.printusercmd(c, depth) 
    local prefix, depth = dump.formatdepth(depth)
    if(c == nil) then
        debug(prefix.."USERCMD IS NULL")
    else
        debug(prefix.."Usercmd dump for:", c)
        debug(prefix.."msec:" .. c.msec, "buttons:" .. c.buttons, "angles:" .. extra.shortvectostring(c.angles))
        debug(prefix.."forwardmove:" .. c.forwardmove, "sidemove:" .. c.sidemove, "upmove:" .. c.upmove)
        debug(prefix.."impulse:" .. c.impulse, "lightlevel:" .. c.lightlevel)
    end
end
--- Dumps a player movement structure, related to movement prediction (pmove_*).
-- @param p the pmove structure to print out
-- @param depth an optional depth
function dump.printpmove(p, depth) 
    local prefix, depth = dump.formatdepth(depth)
    if(p == nil) then
        debug(prefix.."PMOVE IS NULL")
    else
        debug(prefix.."Pmove dump for:", p)       
        debug(prefix.."viewangles:" .. extra.vec3tostring(p.viewangles), "viewoffset:" .. extra.vec3tostring(p.viewoffset), "kick_angles:" .. extra.vec3tostring(p.kick_angles))
        debug(prefix.."gunangles:" .. extra.vec3tostring(p.gunangles), "gunoffset:" .. extra.vec3tostring(p.gunoffset))
        debug(prefix.."gunindex:" .. tostring(p.gunindex), "gunframe:" .. tostring(p.gunframe))
        debug(prefix.."blend:" .. extra.getfloatarrayvals(p.blend, 4), "fov:" .. tostring(p.fov), "rdflags:" .. tostring(p.rdflags))
        debug(prefix.."stats:" .. extra.getshortarrayvals(p.stats, qshared.MAX_STATS))
        debug(prefix.."pmove (pmove_state_t):")
        dump.printpmovestate(p.pmove, depth+4)
    end
end
--- Dumps a player movement state structure, related to movement prediction (pmove_state_*).
-- @param p the pmove state structure to print out
-- @param depth an optional depth
function dump.printpmovestate(p, depth) 
    local prefix, depth = dump.formatdepth(depth)
    if(p == nil) then
        debug(prefix.."PMOVE_STATE IS NULL")
    else
        debug(prefix.."Pmove_state dump for:", p)
        debug(prefix.."pm_type:" .. p.pm_type, "origin:" .. extra.shortvectostring(p.origin), "velocity:" .. extra.shortvectostring(p.velocity))
        debug(prefix.."pm_flags:" .. p.pm_flags, "pm_time:" .. p.pm_time, "gravity:" .. p.gravity, "delta_angles:" .. extra.shortvectostring(p.delta_angles))
    end
end
--- Dumps a cvar structure, related to console variables (cvar_*).
-- @param c the cvar structure to print out
-- @param depth an optional depth
function dump.printcvar(c, depth) 
    local prefix, depth = dump.formatdepth(depth)
    if(c == nil) then
        debug(prefix.."CVAR IS NULL")
    else
        debug(prefix.."Cvar dump for:", c)
        debug(prefix.."name:" .. tostring(c.name), "string:" .. tostring(c.string), "latched_string:" .. tostring(c.latched_string))
        debug(prefix.."flags:" .. tostring(c.flags), "modified:" .. tostring(c.modified), "value:" .. tostring(c.value))
        debug(prefix.."next (cvar_s):" .. tostring(c.next))
    end
end
--- Returns a string with the given number of spaces.
-- @param depth the number of spaces to return, or nil to indicate zero
-- @return a string with depth number of spaces, the depth being used
 function dump.formatdepth(depth) 
    if(depth == nil) then depth = 0 end
    return string.format("%"..depth.."s",""), depth
end
--- Takes an array full of strings and prints them out using a delimiter.
-- @param d the delimiter to use
-- @param t the table of strings
-- @return a string with the values in the table
function dump.formatarray(d, t) 
    local ret = "";
    local i
    for i = 1,#t do 
        ret = ret .. tostring(t[i])
        if(i < #t) then ret = ret .. d end
    end
    return ret
end

-- **************************************
-- GI_/GIDP_/PRINT_/CS_/CVAR_/COLOR_/MULTICAST_/MAX_(some) global constants export + documentation
-- **************************************
-- Export *mostly all* GE_ and GIDP_ constants globally, and provide some info about the events (I am omitting ones we
-- obviously should not touch, like those for memory allocation).
--- Broadcasts the network buffer to all clients. If used for a call to GIDP_MULTICAST, you may use a nil origin.
MULTICAST_ALL = qshared.MULTICAST_ALL
--- Broadcasts the network buffer to clients in the PVS from the given origin.
MULTICAST_PVS = qshared.MULTICAST_PVS
--- Broadcasts the network buffer to clients in the PHS from the given origin.
MULTICAST_PHS = qshared.MULTICAST_PHS
--- Ends text formatting.
CHAR_ENDFORMAT = string.char(qshared.CHAR_ENDFORMAT)
--- Begins/ends underlining.
CHAR_UNDERLINE	= string.char(qshared.CHAR_UNDERLINE)
--- Begins/ends italics.
CHAR_ITALICS	= string.char(qshared.CHAR_ITALICS)
--- Begins color. The character after it sets the color.
CHAR_COLOR	= string.char(qshared.CHAR_COLOR)
--- The color of chat messages.
COLOR_CHAT	= string.char(qshared.COLOR_CHAT)
--- The color of map names.
COLOR_MAPNAM = qshared.COLOR_MAPNAME
--- "Set to cause it to be saved to vars.rc"
CVAR_ARCHIVE = qshared.CVAR_ARCHIVE -- TODO: figure out exactly what all CVAR_ mean
--- "Added to userinfo when changed"
CVAR_USERINFO = qshared.CVAR_USERINFO
--- "Added to serverinfo when changed"
CVAR_SERVERINFO = qshared.CVAR_SERVERINFO 
--- "Don't allow change from console at all, but can be set from the command line"
CVAR_NOSET = qshared.CVAR_NOSET
--- "Save changes until server restart"
CVAR_LATCH = qshared.CVAR_LATCH
--- The maximum number of supported clients.
MAX_CLIENTS = qshared.MAX_CLIENTS
--- The maximum number of entities.
MAX_EDICTS = qshared.MAX_EDICTS
--- The maximum number of lighting styles.
MAX_LIGHTSTYLES = qshared.MAX_LIGHTSTYLES
--- The maximum number of models.
MAX_MODELS = qshared.MAX_MODELS
--- The maximum number of sounds.
MAX_SOUNDS = qshared.MAX_SOUNDS
--- The maximum number of images.
MAX_IMAGES = qshared.MAX_IMAGES -- This appears to be stuff that goes on our HUD
--- The maximum number of items.
MAX_ITEMS = qshared.MAX_ITEMS
--- This is the maximum number of "general" stuff, kept in a configstrings index range.
MAX_GENERAL = qshared.MAX_GENERAL
--- Described as "max length of a quake game pathname." It also happens to be the maximum length of a configstring, so keep that in mind.
MAX_QPATH = qshared.MAX_QPATH
--- The index of the map information. This is pulled right out of worldspawn's "message" in the map, it appears. Thus, it is not necessarily the map's filename.
CS_NAME = qshared.CS_NAME
--- DP probably does not use this. It is always initialized to 0 by the game.
CS_CDTRACK = qshared.CDTRACK
--- The index of the current sky.
CS_SKY = qshared.CS_SKY
--- ??? You'll have to go into q_shared.h and the game code to learn more. This is in "%f %f %f" format. I think there are some constants in qshared to help you.
CS_SKYAXIS = qshared.CS_SKYAXIS
--- ??? You'll have to go into q_shared.h and the game code to learn more. This appears to be in "%f" format. I think there are some constants in qshared to help you.
CS_SKYROTATE = qshared.CS_SKYROTATE
--- This is HUD layout info, parsed by a function called SCR_ExecuteLayoutString in DP.
CS_STATUSBAR = qshared.CS_STATUSBAR -- NOTE: this contains the magical HUD display string thingamabobber
--- ??? "air acceleration control"
CS_AIRACCEL = qshared.CS_AIRACCEL
--- The index containing the maximum number of clients the server is allowing.
CS_MAXCLIENTS = qshared.CS_MAXCLIENTS
--- Checksum used for disallowing maps that do not match what the server is running. Client processes this themself.
CS_MAPCHECKSUM = qshared.CS_MAPCHECKSUM
--- Beginning index of the models list. Example of an entry: "models/weapons/v_68carbine/tris.md2"
CS_MODELS = qshared.CS_MODELS
--- Beginning index of the sounds list. Example of an entry: "guns/spyder1.wav" or "*death1.wav"
CS_SOUNDS = qshared.CS_SOUNDS
--- Ending index of models list. This is my own constant.
CS_MODELS_END = CS_SOUNDS - 1
--- Beginning index of the images list. I believe these are HUD images. They are in pballs/pics. Example of an entry: "i_bluee2"
CS_IMAGES = qshared.CS_IMAGES
--- Ending index of sounds list. This is my own constant.
CS_SOUNDS_END = CS_IMAGES - 1
--- Beginning index of the lights list. These strings define what a light looks like (steady, flickering, etc.). More info on them can be found in the source code somewhere, or on Quake 2 mapping sites.
CS_LIGHTS = qshared.CS_LIGHTS
--- Ending index of images list. This is my own constant.
CS_IMAGES_END = CS_LIGHTS - 1
--- Beginning index of the items list. All of the strings here are item names (ie: "VM-68").
CS_ITEMS = qshared.CS_ITEMS
--- Ending index of lights list. This is my own constant.
CS_LIGHTS_END = CS_IMAGES - 1
--- Beginning index of the player skins list. These appear to use the format "nickname\skinpath". Example: "ironfist\male/pb2r". When a client changes their name, it appears their index is updated with the new name.
CS_PLAYERSKINS = qshared.CS_PLAYERSKINS -- I noticed in a test, an ACEBOT got a higher index (not at CS_PLAYERSKINS), but my client came in and started at CS_PLAYERSKINS...
--- Ending index of lights list. This is my own constant.
CS_ITEMS_END = CS_PLAYERSKINS - 1 
--- Beginning index of the general list.
CS_GENERAL = qshared.CS_GENERAL
--- The time left in minutes:seconds. The game updates this a lot. This is my own constant.
CS_GENERAL_TIMELEFT = CS_GENERAL + 1
--- Ending index of player skins list. This is my own constant.
CS_PLAYERSKINS_END = CS_GENERAL - 1
--- The upper index of the configstrings (the last index).
MAX_CONFIGSTRINGS = qshared.MAX_CONFIGSTRINGS
--- Ending index of the general list. This is my own constant.
CS_GENERAL_END = qshared.CS_GENERAL+qshared.MAX_GENERAL-1
-- ??? / TODO: DOCUMENT ALL THESE!!!!! they may need _end range index indicators too...dunno if these are literal indices
CS_REQUIREDFILES = qshared.REQUIREDFILES -- jitdownload
CS_SERVERGVERSION = qshared.SERVERGVERSION -- jitversion
CS_SERVEREVERSION = qshared.SERVEREVERSION -- jitversion
CS_TEAMINDEXES = qshared.TEAMINDEXES -- jitscores
--- A string with "Gametype: #", where # is the gametype number.
CS_GAMETYPE = qshared.GAMETYPE -- jitscores
--- "For additional stuff". Probably not used.
CS_WHATEVERSNEXT = qshared.WHATEVERSNEXT 
CS_EVENTS = qshared.CS_EVENTS -- TODO: You may want to add EVENT_ constants, which are formatted strings... but weird thing is, it looks like you have to add one to the index to make it come out right (ie: in the game, the CS_EVENTS index had the client join format text, but in jit's enums, EVENT_NONE=0, so you'd think that index should not have been used...)
--- Pickup messages
PRINT_LOW = qshared.PRINT_LOW
--- Alternate alias for PRINT_LOW
PRINT_PICKUP = qshared.PRINT_LOW
--- Death messages
PRINT_MEDIUM = qshared.PRINT_MEDIUM
--- Alternate alias for PRINT_MEDIUM
PRINT_DEATH = qshared.PRINT_MEDIUM
--- Critical messages
PRINT_HIGH = qshared.PRINT_HIGH
--- Alternate alias for PRINT_HIGH
PRINT_CRITICAL = qshared.PRINT_HIGH
--- Chat messages
PRINT_CHAT = qshared.PRINT_CHAT
--- Pops up a dialog on the client
PRINT_DIALOG = qshared.PRINT_DIALOG
--- For item pickup notifications
PRINT_ITEM = qshared.PRINT_ITEM
--- For events (such as flag captures), these are encoded and you can listen to them with the standard 'server' plugin
PRINT_EVENT = qshared.PRINT_EVENT
--- For server sending ping, kills, deaths, etc. of a client
PRINT_SCOREDATA = qshared.PRINT_SCOREDATA
--- For client-side scoreboard
PRINT_PINGDATA = qshared.PRINT_PINGDATA
--- For client-side vote menu
PRINT_MAPLISTDATA = qshared.PRINT_MAPLISTDATA
--- Chat with name index encoded into first character(s)
PRINT_CHATN = qshared.PRINT_CHATN 
--- Probably similar to PRINT_CHATN
PRINT_CHATN_TEAM = qshared.PRINT_CHATN_TEAM
--- Probably similar to PRINT_CHATN
PRINT_CHATN_PRIVATE = qshared.PRINT_CHATN_PRIVATE
--- Probably similar to PRINT_CHATN
PRINT_CHATN_ACTION = qshared.PRINT_CHATN_ACTION
--- Not used.
PRINT_CHATN_RESERVED = qshared.PRINT_CHATN_RESERVED
--- Not used.
PRINT_CHATN_RESERVED2 = qshared.PRINT_CHATN_RESERVED2
--- Occurs when the game library is first loaded
 -- C Function: void		(*Init) (void);
GE_INIT = geinterceptcontrol.GE_INIT
--- Occurs when the game library is unloaded
 -- C Function: void		(*Shutdown) (void);
GE_SHUTDOWN = geinterceptcontrol.GE_SHUTDOWN
--- Occurs when a map is loaded. It is a good indication that a new game started.
 -- C Function: void	    (*SpawnEntities) (char *mapname, char *entstring, char *spawnpoint);
 --      mapname - The map name without the file extension (.bsp)
 --      entstring - The full multi-line entity declarations section from the map file
 --      spawnpoint - ??? I've only seen this as empty
GE_SPAWNENTITIES = geinterceptcontrol.GE_SPAWNENTITIES
--- Not used in DP
 -- C Function: void		(*WriteGame) (char *filename, qboolean autosave);
GE_WRITEGAME = geinterceptcontrol.GE_WRITEGAME
--- Not used in DP
 -- C Function: void		(*ReadGame) (char *filename);
GE_READGAME = geinterceptcontrol.GE_READGAME
--- Not used in DP
 -- C Function: void		(*WriteLevel) (char *filename);
GE_WRITELEVEL = geinterceptcontrol.GE_WRITELEVEL
--- Not used in DP
 -- C Function: void		(*ReadLevel) (char *filename);
GE_READLEVEL = geinterceptcontrol.GE_READLEVEL
--- Occurs when a client connects to the server (happens before ClientBegin).
 -- From C commentary: "[give] the game a chance to reject this connection or modify the userinfo"
 -- C Function: qboolean	(*ClientConnect) (edict_t *ent, char *userinfo);
 --      ent - The allocated entity for this client
 --      userinfo - A set of key-value pairs with client information, sort of like the server's own "configstrings"
 -- Return: true to allow the client to join the game, or false to deny them
GE_CLIENTCONNECT = geinterceptcontrol.GE_CLIENTCONNECT -- TODO: A reject message can be specified, look at figuring out how to use Info_ functions in q_shared
--- Client has now entered the game. Note that if the map changes, this occurs again, as the user is re-entering the game.
 -- C Function: void		(*ClientBegin) (edict_t *ent);
 --      ent - The allocated entity for this client
GE_CLIENTBEGIN = geinterceptcontrol.GE_CLIENTBEGIN 
--- Occurs when one of the client's userinfo values changes. Seems to happen shortly after ClientConnect/ClientBegin, also.
 -- C Function: void		(*ClientUserinfoChanged) (edict_t *ent, char *userinfo);
 --      ent - The allocated entity for this client
 --      userinfo - the same string you get for 'userinfo' in GE_CLIENTCONNECT (it contains all the information all over again)
GE_CLIENTUSERINFOCHANGED = geinterceptcontrol.GE_CLIENTUSERINFOCHANGED
--- Occurs when a client disconnects. Should also occur if they are kicked/timeout, etc.
 -- C Function: void		(*ClientDisconnect) (edict_t *ent);
 --      ent - The allocated entity for this client
GE_CLIENTDISCONNECT = geinterceptcontrol.GE_CLIENTDISCONNECT
--- Appears to occur any time a client sends a literal command. This 
 -- is basically everything beside player movement/impulse/attack, and some
 -- other stuff I can't remember. To actually access the command, you
 -- must use the following retrieval functions provided by
 -- GIDP: argc, argv, and args. This has no return value, so
 -- suppression is pretty easy!
 -- C Function: void		(*ClientCommand) (edict_t *ent);
 --      ent - The allocated entity for this client
GE_CLIENTCOMMAND = geinterceptcontrol.GE_CLIENTCOMMAND
--- This seems best described as a "client frame" -- the client
 -- the client gets to "think", or tell us what they're doing.
 -- Check out the DP source for more detailed info.
 -- C Function: void		(*ClientThink) (edict_t *ent, usercmd_t *cmd);
 --      ent - The allocated entity for this client
 --      cmd - The current information the client is conveying for this client frame
GE_CLIENTTHINK = geinterceptcontrol.GE_CLIENTTHINK
--- This is called to process an entire server frame.
 -- C Function: void		(*RunFrame) (void);
GE_RUNFRAME = geinterceptcontrol.GE_RUNFRAME
--- From C commentary: "ServerCommand will be called when an "sv <command>" 
 -- command is issued on the server console."
 -- You can access the arguments using the following functions provided in GIDP:
 -- argc, argv, and args.
 -- C Function: void		(*ServerCommand) (void);
GE_SERVERCOMMAND = geinterceptcontrol.GE_SERVERCOMMAND
--- Uses "SV_BroadcastPrintf", which "sends text to all active clients." Basically,
 -- you can print whatever you want directly to all clients. This also gets sent
 -- to the server console.
 --      printlevel - One of the global PRINT_* constants.
 --      fmt - This is supposed to be a format specifier, but you are forced to put all your text you want to send into it due to restrictions. Be aware that you must escape % with %%.
 --      ... - Due to restrictions, you may not provide multiargs to this function. Put all of your text in fmt.
 -- C Function: void	(*bprintf) (int printlevel, char *fmt, ...);
GIDP_BPRINTF = gidpinterceptcontrol.GIDP_BPRINTF
--- Prints "debug information" directly out to the console. Nothing goes to clients.
 --      fmt - This is supposed to be a format specifier, but you are forced to put all your text you want to send into it due to restrictions. Be aware that you must escape % with %%.
 --      ... - Due to restrictions, you may not provide multiargs to this function. Put all of your text in fmt.
 -- C Function: void	(*dprintf) (char *fmt, ...);
GIDP_DPRINTF = gidpinterceptcontrol.GIDP_DPRINTF
--- Prints directly to a single client. Nothing goes in the server console or to others.
 --      ent - The client's allocated entity. (If this is null, it will be sent globally)
 --      printlevel - One of the global PRINT_* constants.
 --      fmt - This is supposed to be a format specifier, but you are forced to put all your text you want to send into it due to restrictions. Be aware that you must escape % with %%.
 --      ... - Due to restrictions, you may not provide multiargs to this function. Put all of your text in fmt.
 -- C Function: void	(*cprintf) (edict_t *ent, int printlevel, char *fmt, ...);
GIDP_CPRINTF = gidpinterceptcontrol.GIDP_CPRINTF
--- Prints a message to the center of the given client's screen.
 --      ent - The client's allocated entity.
 --      fmt - This is supposed to be a format specifier, but you are forced to put all your text you want to send into it due to restrictions. Be aware that you must escape % with %%.
 --      ... - Due to restrictions, you may not provide multiargs to this function. Put all of your text in fmt.
 -- C Function: void	(*centerprintf) (edict_t *ent, char *fmt, ...);
GIDP_CENTERPRINTF = gidpinterceptcontrol.GIDP_CENTERPRINTF
--- Please see GDIP_POSITIONED_SOUND. This function is exactly the same as that one, except
 -- that the sound origin is where the ent is currently located (thus, it is not specified
 -- here).
 -- C Function: void	(*sound) (edict_t *ent, int channel, int soundindex, float volume, float attenuation, float timeofs);
GIDP_SOUND = gidpinterceptcontrol.GIDP_SOUND
--- Uses the server's "SV_StartSound" function. This plays sounds in the game, which are usually attached to entities.
 -- Please note that GIDP_SOUND actually uses this function (behind the scenes), with origin set as NULL.
 -- From commentary: "Each entity can have eight independent sound sources, like voice, weapon, feet, etc."
 --     origin - The location to play the sound (I think it will stay there, despite the ent's own origin changing). From commentary: "If origin is NULL, the origin is determined from the entity origin or the midpoint of the entity box for bmodels."
 --     ent - The entity this sound belongs to.
 --     channel - I believe this indicates the "channel" on the entity that this sound will play on. See earlier comment about "eight independent sources." Commentary says: "If channel & 8, the sound will be sent to everyone, not just things in the PHS. Channel 0 is an auto-allocate channel, the others override anything already running on that entity/channel pair."
 --     soundindex - Indicates the index of the sound to play
 --     volume - The volume expressed as a floating-point value between 0.0 and 1.0, inclusive
 --     attenuation - A floating-point value between 0.0 and 4.0, inclusive. From commentary: "An attenuation of 0 will play full volume everywhere in the level. Larger attenuations will drop off."
 --     timeofs - From commentary: "Timeofs can range from 0.0 to 0.1 [NOTE: This looks wrong, the code actually wants it to be 0.0 to 0.255, inclusive] to cause sounds to be started later in the frame than they normally would."
 -- C Function: (*positioned_sound) (vec3_t origin, edict_t *ent, int channel, int soundinedex, float volume, float attenuation, float timeofs);
GIDP_POSITIONED_SOUND = gidpinterceptcontrol.GIDP_POSITIONED_SOUND
--- From commentary: "Config strings hold all the index strings, the lightstyles, and misc data like the sky definition and cdtrack.
 -- All of the current configstrings are sent to clients when they connect, and changes are sent to all connected clients."
 -- Note that DP has its own number of configstrings.
 --      num - An index for this string. Indexes are basically the key for the string, so you need to know which ones you want to access beforehand. The ranges for these indexes are defined in the global CS_ constants.
 --      string - The string to set at this index. Please note, "Each config string can be at most MAX_QPATH characters." The MAX_QPATH constant is globally defined.
 -- C Function: void	(*configstring) (int num, char *string);
GIDP_CONFIGSTRING = gidpinterceptcontrol.GIDP_CONFIGSTRING
--- Kills the server right away with an error message.
 --      fmt - This is supposed to be a format specifier, but you are forced to put all your text you want to send into it due to restrictions. Be aware that you must escape % with %%.
 --      ... - Due to restrictions, you may not provide multiargs to this function. Put all of your text in fmt.
 -- C Function: void	(*error) (char *fmt, ...);
GIDP_ERROR = gidpinterceptcontrol.GIDP_ERROR
--- Searches for the specified string within the configstrings model index range. The string must match EXACTLY.
 -- If the string cannot be found, it is automatically allocated. If no room is left in the index range, the
 -- server will crash with an error (you cannot intercept it).
 --      name - The string to search with 
 -- Returns the index location of the found or allocated string, RELATIVE TO CS_MODELS
 -- C Function: int		(*modelindex) (char *name);
GIDP_MODELINDEX = gidpinterceptcontrol.GIDP_MODELINDEX
--- Searches for the specified string within the configstrings sound index range. The string must match EXACTLY.
 -- If the string cannot be found, it is automatically allocated. If no room is left in the index range, the
 -- server will crash with an error (you cannot intercept it).
 --      name - The string to search with 
 -- Returns the index location of the found or allocated string, RELATIVE TO CS_SOUNDS
 -- C Function: int		(*soundindex) (char *name);
GIDP_SOUNDINDEX = gidpinterceptcontrol.GIDP_SOUNDINDEX
--- Searches for the specified string within the configstrings image index range. The string must match EXACTLY.
 -- If the string cannot be found, it is automatically allocated. If no room is left in the index range, the
 -- server will crash with an error (you cannot intercept it).
 --      name - The string to search with 
 -- Returns the index location of the found or allocated string, RELATIVE TO CS_IMAGES
 -- C Function: int		(*imageindex) (char *name);
GIDP_IMAGEINDEX = gidpinterceptcontrol.GIDP_IMAGEINDEX
--- This appears to be used to set models for pretty much every entity in the except players.
 -- Players seem to get their model set manually or something (a configstring is added by the
 -- game for the player...).
 --      ent - The entity you are setting the model of.
 --      name - The name of the model. This is just like what is found in the CS_MODELS configstring index range. For example, "models/items/co2/7oz/tris.md2"
 -- C Function: void	(*setmodel) (edict_t *ent, char *name);
GIDP_SETMODEL = gidpinterceptcontrol.GIDP_SETMODEL -- TODO: I saw some model names called "*1" and "*2", figure out what those are / edit: they are inline models, I still don't get what their purpose is (may be part of the map -- ie a func_door)
--- Part of collision detection. Read the DP source code to learn more.
 -- C Function: trace_t	(*trace) (vec3_t start, vec3_t mins, vec3_t maxs, vec3_t end, edict_t *passent, int contentmask);
GIDP_TRACE = gidpinterceptcontrol.GIDP_TRACE -- TODO: Learn how this and all the other collision detection stuff works. 
--- Part of collision detection. Read the DP source code to learn more.
 -- C Function: int		(*pointcontents) (vec3_t point);
GIDP_POINTCONTENTS = gidpinterceptcontrol.GIDP_POINTCONTENTS 
--- Part of collision detection. Read the DP source code to learn more.
 -- C Function: qboolean	(*inPVS) (vec3_t p1, vec3_t p2);
GIDP_INPVS = gidpinterceptcontrol.GIDP_INPVS 
--- Part of collision detection. Read the DP source code to learn more.
 -- C Funimport.tracection: qboolean	(*inPHS) (vec3_t p1, vec3_t p2);
GIDP_INPHS = gidpinterceptcontrol.GIDP_INPHS 
--- Part of collision detection. Read the DP source code to learn more.
 -- C Function: void		(*SetAreaPortalState) (int portalnum, qboolean open);
GIDP_SETAREAPORTALSTATE = gidpinterceptcontrol.GIDP_SETAREAPORTALSTATE 
--- Part of collision detection. Read the DP source code to learn more.
 -- C Function: qboolean	(*AreasConnected) (int area1, int area2);
GIDP_AREASCONNECTED = gidpinterceptcontrol.GIDP_AREASCONNECTED 
--- From commentary: "an entity will never be sent to a client or used for collision if it is not passed to linkentity.  If the size, position, or
 -- solidity changes, it must be relinked." 
 --     ent - The entity to add to the linked entity list
 -- C Function: void	(*linkentity) (edict_t *ent);
GIDP_LINKENTITY = gidpinterceptcontrol.GIDP_LINKENTITY 
--- From commentary: "Call before removing an interactive edict."
 --     ent - The entity to remove from the linked entity list
 -- C Function: void	(*unlinkentity) (edict_t *ent);	
GIDP_UNLINKENTITY = gidpinterceptcontrol.GIDP_UNLINKENTITY 
--- See DP source code. I *think* this pulls a list of all entities in a given cube/box.
 -- C Function: int		(*BoxEdicts) (vec3_t mins, vec3_t maxs, edict_t **list,	int maxcount, int areatype);
GIDP_BOXEDICTS = gidpinterceptcontrol.GIDP_BOXEDICTS 
--- From commentary: "Player movement code common with client prediction."
 -- C Function: void	(*Pmove) (pmove_t *pmove);
GIDP_PMOVE = gidpinterceptcontrol.GIDP_PMOVE  -- TODO: make sure the dump functions work okay... there's a ton of NULL/nil values, and I don't think some of those are even possible (nil int???)
--- Sends the contents of the network buffer to a set of clients.
 --     origin - Used for the following flag
 --     to - One of the MULTICAST_* constants (basically all in PHS/PVS from given origin, or send to all)
 -- C Function: void	(*multicast) (vec3_t origin, multicast_t to);
GIDP_MULTICAST = gidpinterceptcontrol.GIDP_MULTICAST
--- Sends the contents of the network buffer to a single client.
 --     ent - The client's allocated entity
 --     reliable - Determines if the packet will be flagged reliable
 -- C Function: void	(*unicast) (edict_t *ent, qboolean reliable);
GIDP_UNICAST = gidpinterceptcontrol.GIDP_UNICAST
--- Puts data in the network buffer. Self-explanatory.
-- C Function: void	(*WriteChar) (int c);
GIDP_WRITECHAR = gidpinterceptcontrol.GIDP_WRITECHAR
--- Puts data in the network buffer. Self-explanatory.
-- C Function: void	(*WriteByte) (int c);
GIDP_WRITEBYTE = gidpinterceptcontrol.GIDP_WRITEBYTE
--- Puts data in the network buffer. Self-explanatory.
-- C Function: void	(*WriteShort) (int c);
GIDP_WRITESHORT = gidpinterceptcontrol.GIDP_WRITESHORT
--- Puts data in the network buffer. Self-explanatory.
-- C Function: void	(*WriteLong) (int c);
GIDP_WRITELONG = gidpinterceptcontrol.GIDP_WRITELONG
--- Puts data in the network buffer. Self-explanatory.
-- C Function: void	(*WriteFloat) (float f);
GIDP_WRITEFLOAT = gidpinterceptcontrol.GIDP_WRITEFLOAT
--- Puts data in the network buffer. Self-explanatory.
-- C Function: void	(*WriteString) (char *s);
GIDP_WRITESTRING = gidpinterceptcontrol.GIDP_WRITESTRING
--- Puts data in the network buffer. Self-explanatory.
-- C Function: void	(*WritePosition) (vec3_t pos);
GIDP_WRITEPOSITION = gidpinterceptcontrol.GIDP_WRITEPOSITION
--- Puts data in the network buffer for a coarse direction. Self-explanatory.
-- C Function: void	(*WriteDir) (vec3_t pos);
GIDP_WRITEDIR = gidpinterceptcontrol.GIDP_WRITEDIR
--- Puts data in the network buffer. Self-explanatory.
-- C Function: void	(*WriteAngle) (float f);
GIDP_WRITEANGLE = gidpinterceptcontrol.GIDP_WRITEANGLE
--- From commentary: "If the variable already exists, the value will not be set. The flags will be or'ed in if the variable exists."
 --     var_name - The name of the variable
 --     value - The default value to assign and return if the variable does not yet exist
 --     flags - See CVAR_ global constants
 -- C Function: cvar_t	*(*cvar) (char *var_name, char *value, int flags);
GIDP_CVAR = gidpinterceptcontrol.GIDP_CVAR
--- Sets a console variable.
 --     var_name - The name of the variable
 --     value - The value to set for the variable
 -- C Function: cvar_t	*(*cvar_set) (char *var_name, char *value);
GIDP_CVAR_SET = gidpinterceptcontrol.GIDP_CVAR_SET
--- Forcefully sets a console variable. I'm not sure DP uses this.
 --     var_name - The name of the variable
 --     value - The value to set for the variable
 -- C Function: cvar_t	*(*cvar_forceset) (char *var_name, char *value);
GIDP_CVAR_FORCESET = gidpinterceptcontrol.GIDP_CVAR_FORCESET
--- Returns the number of arguments waiting in argv(). This is used for GE_SERVERCOMMAND and GE_CLIENTCOMMAND.
 -- C Function: int		(*argc) (void);
GIDP_ARGC = gidpinterceptcontrol.GIDP_ARGC 
--- Returns the value of one of the arguments from ServerCommand/ClientCommand. This is used for GE_SERVERCOMMAND and GE_CLIENTCOMMAND.
 --     n - The argument index to access. Remember, this is into a 0-based index array.
 -- Returns a string argument.
 -- C Function: *(*argv) (int n);
GIDP_ARGV = gidpinterceptcontrol.GIDP_ARGV
--- Commentary says: "Concatenation of all argv >= 1." This is used for GE_SERVERCOMMAND and GE_CLIENTCOMMAND.
 -- C Function: char	*(*args) (void);
GIDP_ARGS = gidpinterceptcontrol.GIDP_ARGS -- TODO: I am not sure this even returns the right thing...verify that, then consider removal
--- Commentary says: "Add commands to the server console as if they were typed in for map changing, etc."
 --     text - The text to input into the server console.
 -- C Function: void	(*AddCommandString) (char *text);
GIDP_ADDCOMMANDSTRING = gidpinterceptcontrol.GIDP_ADDCOMMANDSTRING

-- **********************************
-- Plugin registration/unregistration
-- **********************************
--- Registers a plugin. A plugin should always register itself as part of its
-- initialization.
-- The following fields will be forcefully set on the plugin:
--     print, a standard multi-arg print function for general information
--     warn, a standard multi-arg print function for warnings
--     debug, a standard multi-arg print function for printing debugging information
--     listen, a table used to register and unregister event handling functions
--     unreglisteners, an array of listener functions to call when this plugin is unregistered
--     config, a reference to the configuration module for this plugin if it exists (this is nil if no configuration script was present)
--     plugpath, the directory your plugin is in, which is guaranteed to be terminated by a trailing slash
--     listenercounts, a table maintained by core and other plugins which contains the number of listeners this plugin has registered (it's for debugging, mostly)
-- The following fields are REQUIRED to exist for your plugin:
--     info.name, a short, preferrably single-word name for your plugin
--     info.description, a description of your plugin (no linefeeds please)
--     info.author, the author's name
--     info.version, the plugin's version (as a string)
-- @param plugin a table with the plugin's fields
function registerplugin(plugin)
    assert(plugin ~= nil, "plugin cannot be nil")
    assert(plugin.info ~= nil, "plugin.info cannot be nil")
    assert(plugin.info.name ~= nil, "plugin.info.name cannot be nil")
    assert(plugin.info.description ~= nil, "plugin.info.description cannot be nil")
    assert(plugin.info.author ~= nil, "plugin.info.author cannot be nil")
    assert(plugin.info.version ~= nil, "plugin.info.version cannot be nil")
    
    print("****************************")
    
    -- Modules are the standard, nice way to do this in Lua, so force people to use them
    local moduleloaded = false
    for index,module in pairs(package.loaded) do
        if(module == plugin) then 
            moduleloaded = true
            break
        end
    end
    if(not moduleloaded) then error("the provided candidate plugin must first be a loaded module before it can be registered") end
    
    print("Registering plugin '" .. plugin.info.name .. "', version '" .. plugin.info.version .. "', by '" .. plugin.info.author .. "'...")
       
    -- Load configuration for the plugin
    local configscript = plugin.info.name.."/config_"..plugin.info.name..".lua" 
    local configmodname = "config_"..plugin.info.name
    local configmod = nil
    -- note: FileExists takes absolute path
    if(util.FileExists(util.GetPluginsPath() .. configscript) == 1) then -- a plugin is not required to have a config script
        print("Loading plugin configuration for '"..plugin.info.name.."'")
        
        -- Load the config script out of plugins directory (it is supposed to be a module)
        util.LoadScript(configscript, "plugins");
        configmod = package.loaded[configmodname]
        
        -- Unload the config module right away, we no longer need it
        -- TODO: I think there's another package table you need to remove this from, like a cache one
        package.loaded[configmodname] = nil
        
        assert(configmod ~= nil, "The configuration module '"..configmodname.."' was not found for the plugin configuration script we just loaded. Please make sure the configuration script is a proper module.")
    end
    
    
    -- Set plugin fields
    plugin.unreglisteners = {}
    plugin.config = configmod
    plugin.plugpath = util.GetPluginsPath() .. plugin.info.name .. "/"
    plugin.print = function(...) pluginprint(plugin.info.name, formatforprint(...)) end   
    plugin.warn = function(...) pluginprint(plugin.info.name, "WARNING: " .. formatforprint(...)) end   
    plugin.debug = function(...) pluginprint(plugin.info.name, "Debug: " .. formatforprint(...)) end    
    plugin.listenercounts = {}
    plugin.listen = {
        reg = function (intercepttype, calltime, eventid, handler) intercept.registerEventHandler(plugin, intercepttype, calltime, eventid, handler) end,
        unreg = function(handler) return intercept.unregisterEventHandler(handler) end,
        game = {
            precall = function(eventid, handler) intercept.registerEventHandler(plugin, intercept.IN_GAME, intercept.CALL_PRE, eventid, handler) end,
            postcall = function(eventid, handler) intercept.registerEventHandler(plugin, intercept.IN_GAME, intercept.CALL_POST, eventid, handler) end
        },
        dp = {
            precall = function(eventid, handler) intercept.registerEventHandler(plugin, intercept.IN_DP, intercept.CALL_PRE, eventid, handler) end,
            postcall = function(eventid, handler) intercept.registerEventHandler(plugin, intercept.IN_DP, intercept.CALL_POST, eventid, handler) end
        }
    }
    -- Store the plugin
    plugins[#plugins + 1] = plugin
    -- We're done
    print("Successfully registered plugin '" .. plugin.info.name .. "'!")
    print("****************************")
end
--- Unregisters a plugin and all listeners associated with it. It is not, however, removed from
-- package.loaded. After you've called this function on a plugin, the plugin becomes essentially unusable,
-- as all utility fields set up by registration are set to nil. At this point, the plugin is a candidate
-- for garbage collection, provided you remove its loaded module status. Please do not remove the
-- plugin as a module before unregistering the plugin.
-- @param plugin the plugin to unregister
function unregisterplugin(plugin) 
    assert(plugin ~= nil, "plugin cannot be nil")
    local moduleloaded = false
    for index,module in pairs(package.loaded) do
        if(module == plugin) then 
            moduleloaded = true
            break
        end
    end
    if(not moduleloaded) then error("you should not unload the plugin as a module before unregistering it, please correct this issue") end
    
    -- Alert the unregistration listeners
    for i,listener in ipairs(plugin.unreglisteners) do
        listener(plugin)
    end
    
    -- Remove all the listeners
    intercept.removehandler(intercept.listeners[intercept.IN_GAME][intercept.CALL_PRE], 0, MAX_GE_EVENT, nil, plugin)
    intercept.removehandler(intercept.listeners[intercept.IN_GAME][intercept.CALL_POST], 0, MAX_GE_EVENT, nil, plugin)
    intercept.removehandler(intercept.listeners[intercept.IN_DP][intercept.CALL_PRE], 0, MAX_GIDP_EVENT, nil, plugin)
    intercept.removehandler(intercept.listeners[intercept.IN_DP][intercept.CALL_POST], 0, MAX_GIDP_EVENT, nil, plugin)
    
    -- Reset fields we set
    plugin.unreglisteners = nil
    plugin.print = nil
    plugin.warn = nil
    plugin.debug = nil
    plugin.listen = nil
    print("Unregistered plugin '" .. plugin.info.name .. "'")
end
--- Registers a plugin unregistration listener function. This function is called when a plugin
-- is being unregistered. This gives you a chance to clean up anything you may be storing
-- related to that plugin. For example, if for some reason your plugin has a reference
-- to another plugin, you should utilize this to ensure that you remove your own
-- plugin reference when the plugin is unregistered. Not doing so interferes with garbage
-- collection and can lead to unpredictable behavior for the plugin that you have a reference
-- to which has already been unregistered.
-- Note that if the handler function is already added, it is not added again.
-- @param plugin the plugin you wish to register the handler for
-- @param handler a function to call when this plugin is unregistered (it receives the plugin being unloaded as its sole parameter)
function registerunreglistener(plugin, handler) 
    for i,listener in ipairs(plugin.unreglisteners) do
        if(listener == handler) then return end -- Do not add the handler more than once
    end
    plugin.unreglisteners[#plugin.unreglisteners+1] = handler
    -- Update the listenercounts table
    local listenerkey = "core:unreg"
    local currentcount = plugin.listenercounts[listenerkey]
    if(currentcount == nil) then currentcount = 0 end
    currentcount = currentcount + 1
    plugin.listenercounts[listenerkey] = currentcount
end

-- **************************************
-- Interception registration for plugins.
-- **************************************
--- Contains all code required for plugins to be able to hook in to game calls.
intercept = {
    --- Table mapping of listeners: [IN_GAME or IN_DP][CALL_PRE or CALL_POST][eventid][listener index].(plugin or handler)
    listeners = {},
    --- A constant indicating calls that go into the game dynamic library
    IN_GAME = 0,
    --- A constant indicating calls that go into the Digital Paint executable (the guts of the server, which loads the game)
    IN_DP = 1,
    --- A constant indicating the pre-event (before the real function call has been made)
    CALL_PRE = 0,
    --- A constant indicating the post-event (after the real function call has been made)
    CALL_POST = 1,
    --- A constant for the pre-event indicating that the actual function call should not be made, but silently dropped. You MUST at some point set a return value if one is required, unless the function does not need a return value. Using DO_DROP will allow other listeners to still get this event, but their own DO_* instruction will be ignored, unless it is DO_DROPNOW. Be aware that other listeners can still mutate the return value.
    DO_DROP = 0,
    --- A constant for the pre-event indicating that the actual function call should be made. However, if another listener function previously called DO_DROP, this is ignored in favor of ultimately dropping the call.
    DO_ALLOW = 1,
    --- A constant for the pre-event indicating that the actual function call should not be made, but silently dropped. You MUST at some point set a return value if one is required, unless the function does not need a return value. Using DO_DROPNOW will NOT allow any remaining listener functions to get this event. Use wisely (note that you should avoid using this altogether, as it may affect other running plugin scripts).
    DO_DROPNOW = 2,
    --- A constant for the pre-event indicating that the actual function call should be made. Using DO_ALLOWNOW will NOT let any listeners past this one receive the event, and will instead jump to game function call immediately. Use wisely (note that you should avoid using this altogether, as it may affect other running plugin scripts).
    DO_ALLOWNOW = 3,
    --- The maximum index value for a GE_ event
    MAX_GE_EVENT = geinterceptcontrol.GE_SERVERCOMMAND,
    --- The maximum index value for a GIDP_ event
    MAX_GIDP_EVENT = gidpinterceptcontrol.GIDP_INPHS
}
-- Initialize the listeners table
intercept.listeners[intercept.IN_GAME] = {}
intercept.listeners[intercept.IN_DP] = {}
intercept.listeners[intercept.IN_GAME][intercept.CALL_PRE] = {}
intercept.listeners[intercept.IN_GAME][intercept.CALL_POST] = {}
intercept.listeners[intercept.IN_DP][intercept.CALL_PRE] = {}
intercept.listeners[intercept.IN_DP][intercept.CALL_POST] = {}
--- Registers an event listening function for a function call before it happens, which
-- gives you the ability to modify the parameters or block it (and if it has a return
-- value, to set that before it is dropped).
-- This is the central place to register for an event.
--
-- @param plugin your plugin table    
-- @param intercepttype a constant integer, IN_GAME or IN_DP
-- @param calltime a constant integer, CALL_PRE or CALL_POST
-- @param eventid the id of the event to handle
-- @param handler the handler function
function intercept.registerEventHandler(plugin, intercepttype, calltime, eventid, handler)
    -- Check parameters
    assert(plugin ~= nil, "plugin cannot be nil")
    assert(intercepttype ~= nil, "intercepttype cannot be nil")    
    assert(calltime ~= nil, "calltime cannot be nil")
    assert(eventid ~= nil, "eventid cannot be nil")
    assert(handler ~= nil, "handler function cannot be nil")
    assert(intercepttype == intercept.IN_GAME or intercepttype == intercept.IN_DP, "invalid intercept type")
    assert(calltime == intercept.CALL_PRE or calltime == intercept.CALL_POST, "invalid call time")
    
    -- Don't let ourself pass invalid event IDs on up, or something is going to segfault
    if(intercepttype == intercept.IN_GAME) 
        then assert(eventid >= 0 and eventid <= intercept.MAX_GE_EVENT, "invalid event id for ge") 
    elseif(intercepttype == intercept.IN_DP) 
        then assert(eventid >= 0 and eventid <= intercept.MAX_GIDP_EVENT, "invalid event id for gidp") 
    end
    
    -- Store the listener
    local newlistener = {}
    newlistener.plugin = plugin
    newlistener.handler = handler
    if(intercept.listeners[intercepttype][calltime][eventid] == nil) then -- Create the eventid=>listeners table if it does not exist
        intercept.listeners[intercepttype][calltime][eventid] = {}
    end
    local currentlisteners = intercept.listeners[intercepttype][calltime][eventid]
    currentlisteners[#currentlisteners + 1] = newlistener
    
    -- Update the listenercounts table
    local listenerkey = "core:ge-gi"
    local currentcount = plugin.listenercounts[listenerkey]
    if(currentcount == nil) then currentcount = 0 end
    currentcount = currentcount + 1
    plugin.listenercounts[listenerkey] = currentcount    
    
    -- Make sure we are now intercepting that event
    if(intercepttype == intercept.IN_GAME) then
        geinterceptcontrol.GE_InterceptEnable(eventid)
    elseif(intercepttype == intercept.IN_DP) then
        gidpinterceptcontrol.GIDP_InterceptEnable(eventid)
    end
end
--- A utility function to remove any instances of an event handler from the given
-- table that maps event IDs to plugins/handlers. For internal use.
-- @param t the table to search through and modify
-- @param matchhandler the handler function, that if matched, will be used to remove the listener (may be nil to not use)
-- @param matchplugin the plugin, that if matched, will be used to remove the listener (may be nil to not use)
-- @return true if removed, false if not
function intercept.removehandler(t, matchhandler, matchplugin)
    -- Note: Don't worry about if an event has no listeners left (and now the C code is wasting time calling us); the from-C event handler functions keep an eye out for that and stop taking events when there are no listeners left
    local removed = false
    for eventindex,listeners in pairs(t) do
        -- Note: this may be silly, but I am just recreating this eventindex's list of listeners rather than trying to remove from the existing table... lua gets a bit weird about table removal, and I'm not in the mood to deal with it.
        newlisteners = {}
        for i,handlerinfo in ipairs(listeners) do
            if(handlerinfo.handler == matchhandler or handlerinfo.plugin == matchplugin) then
                -- Update the listenercounts table
                local listenerkey = "core:ge-gi"
                local currentcount = handlerinfo.plugin.listenercounts[listenerkey]
                if(currentcount == nil) then currentcount = 0 end
                currentcount = currentcount - 1
                handlerinfo.plugin.listenercounts[listenerkey] = currentcount
    
                -- Drop it
                removed = true
            else
                -- This is not the handler we are getting rid of, keep it
                newlisteners[#newlisteners+1] = handlerinfo
            end
        end
        t[eventindex] = newlisteners
    end    
    return removed
end
--- Unregisters an event handler. Once done, the internals here have no reference to that
-- event handler function and it will no longer receive events. If for any reason the same
-- handler is listening to multiple events, you can be sure that it will be unregistered from
-- everything it was registered for.
-- @param handler the function that is handling the event
-- @return true if the handler was found and removed, or false if it was not found for unregistration
function intercept.unregisterEventHandler(handler)
    assert(handler ~= nil, "handler cannot be nil")
    -- Go find it and remove it...
    removed = false
    removed = removed or intercept.removehandler(intercept.listeners[intercept.IN_GAME][intercept.CALL_PRE], handler)
    removed = removed or intercept.removehandler(intercept.listeners[intercept.IN_GAME][intercept.CALL_POST], handler)
    removed = removed or intercept.removehandler(intercept.listeners[intercept.IN_DP][intercept.CALL_PRE], handler)
    removed = removed or intercept.removehandler(intercept.listeners[intercept.IN_DP][intercept.CALL_POST], handler)
    return removed
end

-- ******************************************
-- C-INVOKED FUNCTIONS AND EVENTS PROPAGATION
-- Here be magic and excessive verbosity.
-- ******************************************
--- A table of eventid=>function, where the function will return the pre-event arguments (in the C code, it returns a struct)
local gidp_preargs_lookup = {}
gidp_preargs_lookup[GIDP_BPRINTF] = gidpeventdata.GIDP_GetPreArgs_bprintf
gidp_preargs_lookup[GIDP_DPRINTF] = gidpeventdata.GIDP_GetPreArgs_dprintf
gidp_preargs_lookup[GIDP_CPRINTF] = gidpeventdata.GIDP_GetPreArgs_cprintf
gidp_preargs_lookup[GIDP_CENTERPRINTF] = gidpeventdata.GIDP_GetPreArgs_centerprintf
gidp_preargs_lookup[GIDP_SOUND] = gidpeventdata.GIDP_GetPreArgs_sound
gidp_preargs_lookup[GIDP_POSITIONED_SOUND] = gidpeventdata.GIDP_GetPreArgs_positioned_sound
gidp_preargs_lookup[GIDP_CONFIGSTRING] = gidpeventdata.GIDP_GetPreArgs_configstring
gidp_preargs_lookup[GIDP_ERROR] = gidpeventdata.GIDP_GetPreArgs_error
gidp_preargs_lookup[GIDP_MODELINDEX] = gidpeventdata.GIDP_GetPreArgs_modelindex
gidp_preargs_lookup[GIDP_SOUNDINDEX] = gidpeventdata.GIDP_GetPreArgs_soundindex
gidp_preargs_lookup[GIDP_IMAGEINDEX] = gidpeventdata.GIDP_GetPreArgs_imageindex
gidp_preargs_lookup[GIDP_SETMODEL] = gidpeventdata.GIDP_GetPreArgs_setmodel
gidp_preargs_lookup[GIDP_TRACE] = gidpeventdata.GIDP_GetPreArgs_trace
gidp_preargs_lookup[GIDP_POINTCONTENTS] = gidpeventdata.GIDP_GetPreArgs_pointcontents
gidp_preargs_lookup[GIDP_INPVS] = gidpeventdata.GIDP_GetPreArgs_inPVS
gidp_preargs_lookup[GIDP_INPHS] = gidpeventdata.GIDP_GetPreArgs_inPHS
gidp_preargs_lookup[GIDP_SETAREAPORTALSTATE] = gidpeventdata.GIDP_GetPreArgs_SetAreaPortalState
gidp_preargs_lookup[GIDP_AREASCONNECTED] = gidpeventdata.GIDP_GetPreArgs_AreasConnected
gidp_preargs_lookup[GIDP_LINKENTITY] = gidpeventdata.GIDP_GetPreArgs_linkentity
gidp_preargs_lookup[GIDP_UNLINKENTITY] = gidpeventdata.GIDP_GetPreArgs_unlinkentity
gidp_preargs_lookup[GIDP_WRITECHAR] = gidpeventdata.GIDP_GetPreArgs_WriteChar
gidp_preargs_lookup[GIDP_WRITEBYTE] = gidpeventdata.GIDP_GetPreArgs_WriteByte
gidp_preargs_lookup[GIDP_WRITESHORT] = gidpeventdata.GIDP_GetPreArgs_WriteShort
gidp_preargs_lookup[GIDP_WRITELONG] = gidpeventdata.GIDP_GetPreArgs_WriteLong
gidp_preargs_lookup[GIDP_WRITESTRING] = gidpeventdata.GIDP_GetPreArgs_WriteString
gidp_preargs_lookup[GIDP_WRITEPOSITION] = gidpeventdata.GIDP_GetPreArgs_WritePosition
gidp_preargs_lookup[GIDP_WRITEDIR] = gidpeventdata.GIDP_GetPreArgs_WriteDir
gidp_preargs_lookup[GIDP_WRITEANGLE] = gidpeventdata.GIDP_GetPreArgs_WriteAngle
gidp_preargs_lookup[GIDP_UNICAST] = gidpeventdata.GIDP_GetPreArgs_unicast
gidp_preargs_lookup[GIDP_MULTICAST] = gidpeventdata.GIDP_GetPreArgs_multicast
gidp_preargs_lookup[GIDP_BOXEDICTS] = gidpeventdata.GIDP_GetPreArgs_BoxEdicts
gidp_preargs_lookup[GIDP_PMOVE] = gidpeventdata.GIDP_GetPreArgs_Pmove
gidp_preargs_lookup[GIDP_CVAR] = gidpeventdata.GIDP_GetPreArgs_cvar
gidp_preargs_lookup[GIDP_CVAR_SET] = gidpeventdata.GIDP_GetPreArgs_cvar_set
gidp_preargs_lookup[GIDP_CVAR_FORCESET] = gidpeventdata.GIDP_GetPreArgs_cvar_forceset
gidp_preargs_lookup[GIDP_ARGC] = gidpeventdata.GIDP_GetPreArgs_argc
gidp_preargs_lookup[GIDP_ARGV] = gidpeventdata.GIDP_GetPreArgs_argv
gidp_preargs_lookup[GIDP_ARGS] = gidpeventdata.GIDP_GetPreArgs_args
gidp_preargs_lookup[GIDP_ADDCOMMANDSTRING] = gidpeventdata.GIDP_GetPreArgs_AddCommandString
--- A table of eventid=>function, where the function will return the post-event arguments (in the C code, it returns a struct)
local gidp_postargs_lookup = {}
gidp_postargs_lookup[GIDP_BPRINTF] = gidpeventdata.GIDP_GetPostArgs_bprintf
gidp_postargs_lookup[GIDP_DPRINTF] = gidpeventdata.GIDP_GetPostArgs_dprintf
gidp_postargs_lookup[GIDP_CPRINTF] = gidpeventdata.GIDP_GetPostArgs_cprintf
gidp_postargs_lookup[GIDP_CENTERPRINTF] = gidpeventdata.GIDP_GetPostArgs_centerprintf
gidp_postargs_lookup[GIDP_SOUND] = gidpeventdata.GIDP_GetPostArgs_sound
gidp_postargs_lookup[GIDP_POSITIONED_SOUND] = gidpeventdata.GIDP_GetPostArgs_positioned_sound
gidp_postargs_lookup[GIDP_CONFIGSTRING] = gidpeventdata.GIDP_GetPostArgs_configstring
gidp_postargs_lookup[GIDP_ERROR] = gidpeventdata.GIDP_GetPostArgs_error
gidp_postargs_lookup[GIDP_MODELINDEX] = gidpeventdata.GIDP_GetPostArgs_modelindex
gidp_postargs_lookup[GIDP_SOUNDINDEX] = gidpeventdata.GIDP_GetPostArgs_soundindex
gidp_postargs_lookup[GIDP_IMAGEINDEX] = gidpeventdata.GIDP_GetPostArgs_imageindex
gidp_postargs_lookup[GIDP_SETMODEL] = gidpeventdata.GIDP_GetPostArgs_setmodel
gidp_postargs_lookup[GIDP_TRACE] = gidpeventdata.GIDP_GetPostArgs_trace
gidp_postargs_lookup[GIDP_POINTCONTENTS] = gidpeventdata.GIDP_GetPostArgs_pointcontents
gidp_postargs_lookup[GIDP_INPVS] = gidpeventdata.GIDP_GetPostArgs_inPVS
gidp_postargs_lookup[GIDP_INPHS] = gidpeventdata.GIDP_GetPostArgs_inPHS
gidp_postargs_lookup[GIDP_SETAREAPORTALSTATE] = gidpeventdata.GIDP_GetPostArgs_SetAreaPortalState
gidp_postargs_lookup[GIDP_AREASCONNECTED] = gidpeventdata.GIDP_GetPostArgs_AreasConnected
gidp_postargs_lookup[GIDP_LINKENTITY] = gidpeventdata.GIDP_GetPostArgs_linkentity
gidp_postargs_lookup[GIDP_UNLINKENTITY] = gidpeventdata.GIDP_GetPostArgs_unlinkentity
gidp_postargs_lookup[GIDP_WRITECHAR] = gidpeventdata.GIDP_GetPostArgs_WriteChar
gidp_postargs_lookup[GIDP_WRITEBYTE] = gidpeventdata.GIDP_GetPostArgs_WriteByte
gidp_postargs_lookup[GIDP_WRITESHORT] = gidpeventdata.GIDP_GetPostArgs_WriteShort
gidp_postargs_lookup[GIDP_WRITELONG] = gidpeventdata.GIDP_GetPostArgs_WriteLong
gidp_postargs_lookup[GIDP_WRITESTRING] = gidpeventdata.GIDP_GetPostArgs_WriteString
gidp_postargs_lookup[GIDP_WRITEPOSITION] = gidpeventdata.GIDP_GetPostArgs_WritePosition
gidp_postargs_lookup[GIDP_WRITEDIR] = gidpeventdata.GIDP_GetPostArgs_WriteDir
gidp_postargs_lookup[GIDP_WRITEANGLE] = gidpeventdata.GIDP_GetPostArgs_WriteAngle
gidp_postargs_lookup[GIDP_UNICAST] = gidpeventdata.GIDP_GetPostArgs_unicast
gidp_postargs_lookup[GIDP_MULTICAST] = gidpeventdata.GIDP_GetPostArgs_multicast
gidp_postargs_lookup[GIDP_BOXEDICTS] = gidpeventdata.GIDP_GetPostArgs_BoxEdicts
gidp_postargs_lookup[GIDP_PMOVE] = gidpeventdata.GIDP_GetPostArgs_Pmove
gidp_postargs_lookup[GIDP_CVAR] = gidpeventdata.GIDP_GetPostArgs_cvar
gidp_postargs_lookup[GIDP_CVAR_SET] = gidpeventdata.GIDP_GetPostArgs_cvar_set
gidp_postargs_lookup[GIDP_CVAR_FORCESET] = gidpeventdata.GIDP_GetPostArgs_cvar_forceset
gidp_postargs_lookup[GIDP_ARGC] = gidpeventdata.GIDP_GetPostArgs_argc
gidp_postargs_lookup[GIDP_ARGV] = gidpeventdata.GIDP_GetPostArgs_argv
gidp_postargs_lookup[GIDP_ARGS] = gidpeventdata.GIDP_GetPostArgs_args
gidp_postargs_lookup[GIDP_ADDCOMMANDSTRING] = gidpeventdata.GIDP_GetPostArgs_AddCommandString
--- A table of eventid=>function, where the function will return the pre-event arguments (in the C code, it returns a struct)
local ge_preargs_lookup = {}
ge_preargs_lookup[GE_INIT] = geeventdata.GE_GetPreArgs_Init
ge_preargs_lookup[GE_SHUTDOWN] = geeventdata.GE_GetPreArgs_Shutdown
ge_preargs_lookup[GE_SPAWNENTITIES] = geeventdata.GE_GetPreArgs_SpawnEntities
ge_preargs_lookup[GE_WRITEGAME] = geeventdata.GE_GetPreArgs_WriteGame
ge_preargs_lookup[GE_READGAME] = geeventdata.GE_GetPreArgs_ReadGame
ge_preargs_lookup[GE_WRITELEVEL] = geeventdata.GE_GetPreArgs_WriteLevel
ge_preargs_lookup[GE_READLEVEL] = geeventdata.GE_GetPreArgs_ReadLevel
ge_preargs_lookup[GE_CLIENTCONNECT] = geeventdata.GE_GetPreArgs_ClientConnect
ge_preargs_lookup[GE_CLIENTBEGIN] = geeventdata.GE_GetPreArgs_ClientBegin
ge_preargs_lookup[GE_CLIENTUSERINFOCHANGED] = geeventdata.GE_GetPreArgs_ClientUserinfoChanged
ge_preargs_lookup[GE_CLIENTDISCONNECT] = geeventdata.GE_GetPreArgs_ClientDisconnect
ge_preargs_lookup[GE_CLIENTCOMMAND] = geeventdata.GE_GetPreArgs_ClientCommand
ge_preargs_lookup[GE_CLIENTTHINK] = geeventdata.GE_GetPreArgs_ClientThink
ge_preargs_lookup[GE_RUNFRAME] = geeventdata.GE_GetPreArgs_RunFrame
ge_preargs_lookup[GE_SERVERCOMMAND] = geeventdata.GE_GetPreArgs_ServerCommand
--- A table of eventid=>function, where the function will return the post-event arguments (in the C code, it returns a struct)
local ge_postargs_lookup = {}
ge_postargs_lookup[GE_INIT] = geeventdata.GE_GetPostArgs_Init
ge_postargs_lookup[GE_SHUTDOWN] = geeventdata.GE_GetPostArgs_Shutdown
ge_postargs_lookup[GE_SPAWNENTITIES] = geeventdata.GE_GetPostArgs_SpawnEntities
ge_postargs_lookup[GE_WRITEGAME] = geeventdata.GE_GetPostArgs_WriteGame
ge_postargs_lookup[GE_READGAME] = geeventdata.GE_GetPostArgs_ReadGame
ge_postargs_lookup[GE_WRITELEVEL] = geeventdata.GE_GetPostArgs_WriteLevel
ge_postargs_lookup[GE_READLEVEL] = geeventdata.GE_GetPostArgs_ReadLevel
ge_postargs_lookup[GE_CLIENTCONNECT] = geeventdata.GE_GetPostArgs_ClientConnect
ge_postargs_lookup[GE_CLIENTBEGIN] = geeventdata.GE_GetPostArgs_ClientBegin
ge_postargs_lookup[GE_CLIENTUSERINFOCHANGED] = geeventdata.GE_GetPostArgs_ClientUserinfoChanged
ge_postargs_lookup[GE_CLIENTDISCONNECT] = geeventdata.GE_GetPostArgs_ClientDisconnect
ge_postargs_lookup[GE_CLIENTCOMMAND] = geeventdata.GE_GetPostArgs_ClientCommand
ge_postargs_lookup[GE_CLIENTTHINK] = geeventdata.GE_GetPostArgs_ClientThink
ge_postargs_lookup[GE_RUNFRAME] = geeventdata.GE_GetPostArgs_RunFrame
ge_postargs_lookup[GE_SERVERCOMMAND] = geeventdata.GE_GetPostArgs_ServerCommand
-- An error handler for failed event dispatches.
function EventDispatchErrorHandler(errmsg)
    warn("======== Lua error in event dispatch ========\n"..luadebug.traceback(errmsg, 2))
    warn("=============================================")
end
-- Called by IronMod's C code for ge pre-call
function GEPreCallNotify(id)
    local data = ge_preargs_lookup[id]() 
    local pluginlisteners = intercept.listeners[intercept.IN_GAME][intercept.CALL_PRE][id]
    if(pluginlisteners == nil) then return geproxy.GE_ALLOW end
    local dropped = false
    if(#pluginlisteners > 0) then
        for i = 1,#pluginlisteners do
            local d = nil
            local dispatchfunc = function()
                d = pluginlisteners[i].handler(data, id)
            end
            xpcall(dispatchfunc, EventDispatchErrorHandler)
            if(d ~= nil) then
                if(d == intercept.DO_DROP) then 
                    dropped = true
                elseif(d == intercept.DO_DROPNOW) then
                    return geproxy.GE_DROP
                elseif(d == intercept.DO_ALLOWNOW) then
                    return geproxy.GE_ALLOW
                end
            end        
        end
        if(dropped) then return geproxy.GE_DROP else return geproxy.GE_ALLOW end
    else
        local postlisteners = intercept.listeners[intercept.IN_GAME][intercept.CALL_POST][id]
        if(postlisteners == nil or #postlisteners == 0) then
            -- No more listeners for post or pre, stop receiving this event
            geinterceptcontrol.GE_InterceptDisable(id)
            return geproxy.GE_ALLOW
        end
    end
end
-- Called by IronMod's C code for ge post-call
function GEPostCallNotify(id) 
    local data = ge_postargs_lookup[id]() 
    local pluginlisteners = intercept.listeners[intercept.IN_GAME][intercept.CALL_POST][id]
    if(pluginlisteners == nil) then return end
    if(#pluginlisteners > 0) then
        for i = 1,#pluginlisteners do
            local dispatchfunc = function()
                pluginlisteners[i].handler(data, id)
            end
            xpcall(dispatchfunc, EventDispatchErrorHandler)
        end
    else
        local prelisteners = intercept.listeners[intercept.IN_GAME][intercept.CALL_PRE][id]
        if(prelisteners == nil or #prelisteners == 0) then
            -- No more listeners for post or pre, stop receiving this event
            geinterceptcontrol.GE_InterceptDisable(id)
            return
        end
    end
end
-- Called by IronMod's C code for gidp pre-call
function GIDPPreCallNotify(id) 
    local data = gidp_preargs_lookup[id]()
    local pluginlisteners = intercept.listeners[intercept.IN_DP][intercept.CALL_PRE][id]
    if(pluginlisteners == nil) then return gidpproxy.GIDP_ALLOW end
    local dropped = false
    if(#pluginlisteners > 0) then
        for i = 1,#pluginlisteners do
            local d = nil
            local dispatchfunc = function()
                d = pluginlisteners[i].handler(data, id)
            end
            xpcall(dispatchfunc, EventDispatchErrorHandler)
            if(d ~= nil) then
                if(d == intercept.DO_DROP) then 
                    dropped = true
                elseif(d == intercept.DO_DROPNOW) then
                    return gidpproxy.GIDP_DROP
                elseif(d == intercept.DO_ALLOWNOW) then
                    return gidpproxy.GIDP_ALLOW
                end
            end        
        end
        if(dropped) then return gidpproxy.GIDP_DROP else return gidpproxy.GIDP_ALLOW end
    else
        local postlisteners = intercept.listeners[intercept.IN_DP][intercept.CALL_POST][id]
        if(postlisteners == nil or #postlisteners == 0) then
            -- No more listeners for post or pre, stop receiving this event
            gidpinterceptcontrol.GIDP_InterceptDisable(id)
            return gidpproxy.GIDP_ALLOW
        end
    end
end
-- Called by IronMod's C code for gidp post-call
function GIDPPostCallNotify(id) 
    local data = gidp_postargs_lookup[id]() 
    local pluginlisteners = intercept.listeners[intercept.IN_DP][intercept.CALL_POST][id]    
    if(pluginlisteners == nil) then return end    
    if(#pluginlisteners > 0) then
        for i = 1,#pluginlisteners do
            local dispatchfunc = function()
                pluginlisteners[i].handler(data, id)
            end
            xpcall(dispatchfunc, EventDispatchErrorHandler)
        end
    else
        local prelisteners = intercept.listeners[intercept.IN_DP][intercept.CALL_PRE][id]
        if(prelisteners == nil or #prelisteners == 0) then
            -- No more listeners for post or pre, stop receiving this event
            gidpinterceptcontrol.GIDP_InterceptDisable(id)
            return
        end
    end
end

--******************************
-- PLUGIN LOADING
--******************************
--- Loads a plugin from the "plugins" directory. The plugin must be located in "plugins/NAME/", where
-- NAME is the name of the plugin. Within this folder should be at least one file, plugin_NAME.lua, which
-- is what will be loaded. It is assumed that it follows proper plugin design conventions.
-- A second file that will be loaded if it is present is config_NAME.lua, which contains all configuration
-- information for that plugin. The plugin can access it by using a table added to it, called "config".
-- @param name a string representing the name of the plugin
function loadplugin(name) 
    assert(name ~= nil, "name cannot be nil")    
    -- We have ironmod's C code handle script loading
    local pluginscript = name.."/plugin_"..name..".lua"
    
    if(util.FileExists(util.GetPluginsPath() .. pluginscript) == 1) then
        util.LoadScript(pluginscript, "plugins"); -- NOTE: when the plugin registers itself, that is when its config module gets loaded and set up, so don't worry about it
    else    
        error("No such plugin '" .. pluginscript .. "'")
    end
end

--******************************
-- Extra functions that make the sharp edges of the C functions a bit smoother
-- ... and other things that I didn't want to break out seperate libraries for.
--******************************
--- Contains miscellaneous functions to do odd tasks that may be provided for in the exported C functions, but easier to use here.
extra = {}
--- This relatively primitive function recursively walks through a table or other
 -- lua data type to come up with an approximation of its memory use. This is done by
 -- looking at data types and their values. It is intended to be used
 -- as a rough debugging function to check for memory leaks. Recursive references
 -- should not cause a problem since all visited values are automatically added
 -- to the excludevals array.
 -- On further review, this function is nearly useless since it can't count
 -- local variables.
 -- @param val the value to inspect
 -- @param maxdepth the maximum number of sub-tables to visit, depth-wise
 -- @param excludevals this is an array of values that should explicitly be skipped when decending (it will be added to as things progress)
 -- @return approximate memory use in bytes, based on a typical 32bit system with 8-bit chars (or nil if this value is in the excludevals array)
function extra.tallymemory(val, maxdepth, excludevals)
    if(excludevals == nil) then excludevals = {} end
    local total = 0
    local t = type(val)
    for i=1,#excludevals do
        if(excludevals[i] == val) then
            return nil -- Exclude this 
        end
    end
    if(t == "nil") then
        total = total + 0
    elseif(t == "bool") then
        total = total + 1
    elseif(t == "number") then -- float64
        total = total + 8
    elseif(t == "function") then -- my guess is function pointers are 32bit
        total = total + 4
    elseif(t == "thread") then -- guess...
        total = total + 4
    elseif(t == "string") then -- tally it up
        total = total + #val + 4 -- Adding 32bit int since I figure that's what's used to store string length
    elseif(t == "table") then  -- start visiting keys and values if we aren't too deep     
        if(maxdepth >= 0) then
            for tkey,tval in pairs(val) do
                local key_numbytes = extra.tallymemory(tkey, maxdepth-1, excludevals)
                if(key_numbytes ~= nil) then
                    total = total + key_numbytes
                end
                local val_numbytes = extra.tallymemory(tval, maxdepth-1, excludevals)
                if(val_numbytes ~= nil) then
                    total = total + val_numbytes
                end
            end
        end
    else
        error("Unknown type '" .. t .. "'")
    end
    
    excludevals[#excludevals+1] = val -- Never visit this value again
    
    return total
end
--- Serializes a variable and writes it out to a file. Types are preserved 
 -- (ie: a number remains a number, a string remains a string). The supported
 -- types for serialization are "string", "number", "boolean", and "table". Tables are,
 -- of course, recursively serialized. The keys and values in the table must
 -- also be one of the valid types for serialization. Note that this function
 -- is not safe from recursive serialization.
 -- @param filehandle the file handle to write the output to
 -- @param var the value to serialize
 -- @param depth an optional integer indicating how far to indent the table information (this function is called recursively)
 -- @param an optional boolean value that determines if a newline is used for the file 
function extra.serialize(filehandle, var, depth, usenewline)
    if(depth == nil) then
        depth = 0
    end    
    if(usenewline == nil) then
        usenewline = true
    end
    local prefix = string.rep(" ", depth)
    local println = function(text)        
        filehandle:write(prefix .. text)
        if(usenewline) then filehandle:write("\n") end
    end 
    
    local typevar = type(var)
    if(typevar == "number") then
        println("[num:" .. var .. "]")
    elseif(typevar == "string") then
        println("[str:" .. url.escape(var) .. "]")
    elseif(typevar == "boolean") then
        println("[bool:" .. tostring(var) .. "]")
    elseif(typevar == "table") then
        println("{")
        for k,v in pairs(var) do
            extra.serialize(filehandle, k, depth+2, false)
            filehandle:write(" =\n") -- This is just to make things look nice, the parser already knows value goes on next line
            extra.serialize(filehandle, v, depth+4)
        end
        println("}")
    else
        error("cannot serialize type '"..typevar.."'")
    end
end
--- Deserializes a variable and returns it from a file that was serialized using
 -- serialize().
 -- @param lineiterator a function that returns the next line in the file, or nil when no more are left
 -- @param readingtable an optional value only used if we are reading for a table's key or value
 -- @return the value read from the file
function extra.deserialize(lineiterator, readingtable) 
    local line = lineiterator()
    if(line == nil) then
        error("Expected another line in the file")
    end 
    if(readingtable == nil) then 
        readingtable = false
    end    
    
    -- Extract what is between the [ ]
    local regulartypedata = string.match(line, "^%s*%[(.*)%].*$")
    if(regulartypedata ~= nil) then
        -- Non-table type
        local typename,value = string.match(regulartypedata, "^(.*):(.*)$")
        if(typename == "num") then
            return tonumber(value)
        elseif(typename == "str") then
            return url.unescape(value)
        elseif(typename == "bool") then
            return (value == "true")
        else
            error("Unknown type '"..tostring(typename).."'")
        end
    else
        -- It may be a table type begin or end (a single "{" or "}")
        if(string.match(line, "^%s*{.*$")) then
            -- This is the start of a table!
            local t = {}
            local nextkey = extra.deserialize(lineiterator, true)
            while(nextkey ~= nil) do
                -- Read value
                local val = extra.deserialize(lineiterator)
                t[nextkey] = val
                nextkey = extra.deserialize(lineiterator, true)
            end
            return t
        elseif (string.match(line, "^%s*}.*$")) then
            -- End of table
            if(readingtable) then
                return nil -- Signal end of table
            else
                -- We weren't reading a table in!
                error("Found end of table, but no table was being read in!")
            end
        else
            -- No idea what this is
            error("Unknown line: " .. line)
        end
    end
end
--- Converts a vec3_t into an easier-to-access lua table
 -- @param vec the vec3_t to convert
 -- @return table with keys x, y, and z
function extra.get3dvector(vec)  
    vec = util.get_vec3_as_float(vec)
    return { x = util.get_vec3_component(vec,0), y = util.get_vec3_component(vec,1), z = util.get_vec3_component(vec,2) }    
end
--- Converts a short[3] vector into an easier-to-access lua table.
 -- @param vec the short[3] to convert
 -- @return table with keys x, y, and z
function extra.get3dvector_short(vec)  
    return { x = util.get_shortvec_component(vec,0), y = util.get_shortvec_component(vec,1), z = util.get_shortvec_component(vec,2) }    
end
--- Converts a vec3_t into a string
 -- @param vec the vec3_t to convert
 -- @return a two-decimal-place formatted string representing the vector
function extra.vec3tostring(vec)  
    if(vec == nil) then
        return "NULL"
    else
        return extra.formatvector(extra.get3dvector(vec))
    end
end
--- Converts a short[3] vector into a string
 -- @param vec the short[3] vector to convert
 -- @return a two-decimal-place formatted string representing the vector
function extra.shortvectostring(vec)  
    return "(" .. extra.getshortarrayvals(vec, 3) .. ")"
end
--- Formats a table with vector components x, y, and z.
 -- @param vector the vector table to format
 -- @return a formatted string
function extra.formatvector(vector)  
    return "(" .. extra.formatnumber("%.2f",vector.x) .. "," .. extra.formatnumber("%.2f",vector.y) .. "," .. extra.formatnumber("%.2f",vector.z) .. ")"
end
--- Returns a string listing of values in a C float array.
 -- @param floatarray the float* pointer for the array to access
 -- @param size the size of the array
 -- @return a formatted string
function extra.getfloatarrayvals(floatarray, size)  
    if(floatarray == nil) then return "NULL" end
    local values = {}
    for i = 0,size-1 do
        values[#values+1] = util.get_floatarray_val(floatarray, i)
    end
    return dump.formatarray(",", values)
end
--- Returns a string listing of values in a C short array.
 -- @param shortarray the short* pointer for the array to access
 -- @param size the size of the array
 -- @return a formatted string
function extra.getshortarrayvals(shortarray, size)  
    if(shortarray == nil) then return "NULL" end
    local values = {}
    for i = 0,size-1 do
        values[#values+1] = util.get_shortarray_val(shortarray, i)
    end
    return dump.formatarray(",", values)
end
--- Returns a formatted string for a number, even if it is NaN or Inf
 -- @param fmt the format specifier for the single number
 -- @param num the number to format
 -- @return a formatted string representing that number
function extra.formatnumber(fmt, num)
    -- see http://lua-users.org/wiki/InfAndNanComparisons
    if(num ~= num or num == math.huge or num == -math.huge) then
        return tostring(num)
    else
        return string.format(fmt, num)
    end
end
--- Returns the size of a table. This runs in a linear time with the size of
 -- the table, so try to avoid calling it often.
 -- @param t the table
 -- @return the table's size
function extra.tablesize(t)
    local n = 0
    for k in pairs(t) do n = n + 1 end
    return n
end

--******************************
-- Misc stuff goes here
--******************************
math.randomseed(os.time()) -- make sure we get this seeded...

print("Core Lua script has been loaded. Now auto-registering plugin 'server'.")

--******************************
-- Load standard plugins
--******************************
loadplugin("server")
loadplugin("administration")

print("Core Lua script has finished.")

