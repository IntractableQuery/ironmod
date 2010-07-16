module("plugin_statlogger", package.seeall)

-- Required code
info = {
    name = "statlogger",  
    description = "Logs statistics using logging format v1",    
    author = "iron",
    version = "0.1",
    this = package.loaded.plugin_statlogger
}
registerplugin(info.this)
addserverlistener = server.geteventlistenerfunc(info.this)
addcommand = administration.getcommandregisterfunc(info.this)
-- End required code

------------------------
-- Internal variables --
------------------------
local sntp = require("luasntp")
local buffer = "" -- Lua strings can be used as byte buffers since they don't terminate at \0
local wepnums = { ["PGP"] = 1, ["Trracer"] = 2, ["Stingray"] = 3,
                  ["VM-68"] = 4, ["Spyder SE"] = 5, ["Carbine"] = 6,
                  ["Automag"] = 7, ["Autococker"] = 8, ["PaintGren"] = 9 }
local logfilehandle = nil
local seqnumber = 0
local LOG_VERSION = 1
local BIG_ENDIAN 
local cvar_val_cache = {} -- Index is same as CVARS, contains nil if value is not yet known
local CVARS =   { "elim",
                  "fraglimit",
                  "timelimit",
                  "ffire",
                  "grenadeffire",
                  "ctfmode",
                  "sv_gravity",
                  "tripping",
                  "password",
                  "SmokeGrens",
                  "PaintGrens",
                  "flagcapendsround",
                  "gren_explodeonimpact",
                  "match",
                  "maxclients",
                  "real_ball_flight",
                  "ball_speed",
                  "sv_maxvelocity",
                  "ball_addplayerspeed",
                  "ball_life",
                  "slowballsbounce",
                  "bouncy",
                  "gren_addplayerspeed",
                  "pbgren_bursts",
                  "pbgren_ballsperburst",
                  "waterfriction",
                  "bounceback",
                  "instant_spawn",
                  "port",
                  "deathmatch",
                  "dedicated",
                  "maxrate",
                  "instant_item_spawn",
                  "maxentities",
                  "hostname",
                  "allow_match",
                  "public",
                  "website",
                  "admin",
                  "e-mail",
                  "location" }

local LE_LOGSTART = 0x00
local LE_PLAYER_CONNECT = 0x01
local LE_PLAYER_BEGIN = 0x02
local LE_PLAYER_DISCONNECT = 0x03
local LE_PLAYER_JOINTEAM = 0x04
local LE_ROUNDOVER = 0x05
local LE_OVERTIME = 0x06
local LE_ROUNDSTART = 0x07
local LE_ADMINKILL = 0x08
local LE_KILL = 0x09
local LE_SUICIDE = 0x0a
local LE_FRIENDLYFIRE = 0x0b
local LE_RESPAWN = 0x0c
local LE_FLAG_GRAB = 0x0d
local LE_FLAG_DROP = 0x0e
local LE_FLAG_CAPTURED = 0x0f
local LE_CHAT = 0x10
local LE_MAP_CHANGE = 0x11
local LE_GLS_IDENTIFIED = 0x12
local LE_PLAYER_LOCATION = 0x13
local LE_CVAR = 0x14
local LE_NAME_CHANGE = 0x15
local LE_FATAL_ERROR = 0x16

---------------
-- Functions --
---------------
function BeginEvent(eventnum)
    buffer = "" -- May have old data from an error that resulted in no flush...
    
    -- Write timestamp and event id
    WriteUInt32(os.time())
    WriteByte(eventnum)
end
function FlushEvent()
    -- The buffer needs to be prefixed with the seq# and data length
    local origbuffer = buffer
    local datalength = #buffer - 5 -- int32 timestamp, 1 byte event id, then data after that
    buffer = "" -- Clear it so we can write in our seq/length
    WriteUInt32(seqnumber)
    WriteUInt16(datalength)
    buffer = buffer .. origbuffer -- Restore the buffer in its final state

    if(logfilehandle ~= nil) then
        logfilehandle:write(buffer)
        logfilehandle:flush()
    end
    
    -- Reset the buffer
    buffer = ""
    
    seqnumber = seqnumber + 1
end
function WriteByte(byte)
    WriteUnsignedInteger(byte, 1)
end
function WriteUInt16(num)
    WriteUnsignedInteger(num, 2)
end
function WriteUInt32(num)
    WriteUnsignedInteger(num, 4)
end
function WriteIP(ip)
    assert(ip ~= nil, "ip cannot be nil")
    local o1,o2,o3,o4 = ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")
    assert(o1 ~= nil and o4 ~= nil, "Bad IP address '"..tostring(ip).."'")
    -- Write the uint32 manually
    WriteByte(o1)
    WriteByte(o2)
    WriteByte(o3)
    WriteByte(o4)
end
function WriteWeaponNum(wepname)
    -- TODO: if you ever do internal weapon indexing, it'd be useful here   
    local wepnum = wepnums[wepname]
    if(wepnum == nil) then
        -- This really shouldn't be happening, but the log format allows for it
        warn("WriteWeaponNum: Unknown weapon '"..wepname.."'; will log as unknown")
        wepnum = 0
    end
    WriteByte(wepnum)
end
function WriteTeamNum(teamindex)
    assert(teamindex ~= nil, "teamindex cannot be nil")
    local teamnum
    if(teamindex >= 1 and teamindex <= 4) then
        teamnum = teamindex
    else
        teamnum = 0 -- Team none
    end
    WriteByte(teamnum)    
end
function WriteString(str)
    assert(str ~= nil, "str cannot be nil")
    for i=1,#str do
        if(str:sub(i,i) == "\0") then error("String contains NULL, it cannot be encoded") end
    end
    buffer = buffer .. str .. "\0"
end
function WriteFloat32(num)
    assert(num ~= nil, "num cannot be nil")  
    local bytes = ""
    local startindex,endindex,step
    if(BIG_ENDIAN) then
        startindex = 0
        endindex = 3
        step = 1
    else
        startindex = 3
        endindex = 0
        step = -1
    end
    for i = startindex,endindex,step do
        local byte = util.get_byte_from_float(num, i)
        bytes = bytes .. string.char(byte)
    end
    buffer = buffer .. bytes
end
function WritePlayerLocation(player)
    assert(player ~= nil, "player cannot be nil")
    local pos = extra.get3dvector(player.ent.s.origin)
    
    WriteFloat32(pos.x)
    WriteFloat32(pos.y)
    WriteFloat32(pos.z)
end
--- Encodes an unsigned integer using the number of specified bytes. 
-- Overflowing the byte capacity will result in an error and the bytes will
-- not be written to the buffer.
function WriteUnsignedInteger(num, numbytes)
    assert(num ~= nil, "num cannot be nil")
    assert(numbytes ~= nil, "numbytes cannot be nil")
    local originalnum = num
    local tempbuffer = ""
    for curbyte = numbytes-1,0,-1 do
        num = math.floor(num) -- paranoid...
        local div = math.floor(math.pow(256, curbyte))
        local writebyte = math.floor(math.modf(num / div))
        num = math.fmod(num, div)
        tempbuffer = tempbuffer .. string.char(writebyte)
    end
    if(num > 0) then error(numbytes.." bytes cannot encode integer "..originalnum.." ("..num.." remains)") end
    buffer = buffer .. tempbuffer
end
--- Debug function to print out the buffer as a hex string
function DumpBuffer()
    local safechars = "1234567890-=!@#$%^&*()_+`~[]\\;'./,{}|:\"<?>qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM "
    local function safeformat(char)
        for i = 1,#safechars do
            if(safechars:sub(i,i) == char) then return char end
        end
        return "."
    end
    local function gethex(from, to)
        if(to > #buffer) then to = #buffer end
        local str = ""
        for i=from,to do
            local byte = buffer:sub(i,i):byte()
            local output = string.format("%x", byte)
            if(#output == 1) then output = "0"..output end
            str = str .. output .. " "
        end
        return str
    end
    local function getstring(from, to)
        if(to > #buffer) then to = #buffer end
        local str = ""
        for i=from,to do
            str = str .. safeformat(buffer:sub(i,i))
        end
        return str
    end
    local i = 1
    while i <= #buffer do -- rows        
        local hexstr = gethex(i,i+3) .. "  " .. gethex(i+4,i+7)
        local str = getstring(i,i+3) .. "  " .. getstring(i+4,i+7)
        debug(string.format("DUMP %-2s: %-30s  %-30s", i, hexstr, str))
        i = i + 8
    end
end
function getunixtime() 
    return os.time()
end
-- Updates cvars that have changed, or that we've not reported yet
function updatecvars()
    for i,cvarname in ipairs(CVARS) do
        local oldval = cvar_val_cache[i]
        local reportval = nil -- will become non-nil if we need to update
        if(oldval ~= nil) then
            -- Check current value, see if it's changed
            local curval = server.getcvar(cvarname)
            if(curval ~= oldval) then reportval = curval end
        else
            -- Report the new value
            reportval = server.getcvar(cvarname)
        end
        if(reportval ~= nil) then
            cvar_val_cache[i] = reportval -- note that we reported it
            BeginEvent(LE_CVAR)
            WriteUInt16(i - 1)
            WriteString(reportval)
            FlushEvent()
        end
    end
end
-- Verifies that the given player reference is not nil. If it is, then an
-- LE_FATAL_ERROR entry is made in the log file and an error is raised.
-- @param player the player to test
-- @param extratext some text to include in the error message if the player happens to be nil
function verifyplayer(player, extratext)
    if(player == nil) then
        local errmsg = "session state corruption: encountered nil player"
        if(extratext ~= nil) then errmsg = errmsg .. " ("..extratext..")" end
        BeginEvent(LE_FATAL_ERROR)
        WriteString(errmsg)
        FlushEvent()
        error(errmsg)
    end
end

---------------
-- Listeners --
---------------
listen.game.postcall(GE_RUNFRAME, function(data)
    updatecvars()
end)
addserverlistener(server.SE_CONNECT, function(player)
    verifyplayer(player, "SE_CLIENTCONNECT")
    if(player.ip ~= nil) then
        -- TODO: I had problems with getting nil IPs at one point; you can see this is likely due to code that seems to not see the ip field in the server's handling code... it never set the IP (might want to look into this more later, but I don't think it's a problem to ignore nil-ip players)
        BeginEvent(LE_PLAYER_CONNECT)
        WriteIP(player.ip)
        WriteUInt16(player.port)
        WriteByte(player.num)
        WriteString(server.createuserinfo(player.info))
        FlushEvent()
    end
end)
addserverlistener(server.SE_NAMECHANGE, function(player, oldname)
    debug("SE_NAMECHANGE", tostring(player))
    verifyplayer(player, "SE_NAMECHANGE")
    -- TODO: can the name change come before the connect? I think it's possible to have a nil player???... I put a debug in SE_ENTER to explicitly catch this
    BeginEvent(LE_NAME_CHANGE)
    WriteByte(player.num)
    WriteString(player.name)
    FlushEvent()
end)
addserverlistener(server.SE_ENTER, function(player)
    debug("SE_ENTER", tostring(player.name))
    verifyplayer(player, "SE_ENTER")
    BeginEvent(LE_PLAYER_BEGIN)
    WriteByte(player.num)
    WriteTeamNum(player.teamindex)
    WriteString(player.name)
    FlushEvent()
end)
addserverlistener(server.SE_DISCONNECT, function(player)
    verifyplayer(player, "SE_DISCONNECT")
    BeginEvent(LE_PLAYER_DISCONNECT)
    WriteByte(player.num)
    FlushEvent()
end)
addserverlistener(server.SE_JOINTEAM, function(player, oldteamindex)
    verifyplayer(player, "SE_JOINTEAM")
    BeginEvent(LE_PLAYER_JOINTEAM)
    WriteByte(player.num)
    WriteTeamNum(player.teamindex)
    FlushEvent()
end)
addserverlistener(server.SE_ROUNDOVER, function()
    BeginEvent(LE_ROUNDOVER)
    FlushEvent()
end)
addserverlistener(server.SE_OVERTIME, function()
    BeginEvent(LE_OVERTIME)
    FlushEvent()
end)
addserverlistener(server.SE_ROUNDSTART, function()
    BeginEvent(LE_ROUNDSTART)
    FlushEvent()
end)
addserverlistener(server.SE_ADMINKILL, function(victimplayer, adminplayer)
    verifyplayer(player, "SE_ADMINKILL")
    local adminplayernum = 0
    local wasadmin = 0
    if(adminplayer ~= nil) then 
        adminplayernum = adminplayer.num 
        wasadmin = 1
    end
    BeginEvent(LE_PLAYER_LOCATION)
    WriteByte(victimplayer.num)
    WritePlayerLocation(victimplayer)
    FlushEvent()
    
    BeginEvent(LE_ADMINKILL)
    WriteByte(victimplayer.num)
    WriteByte(wasadmin)
    WriteByte(adminplayernum)
    FlushEvent()
end)
addserverlistener(server.SE_KILL, function(kp, kwindex, vp, vwindex)
    -- We can get nil for kp or vp if there's a bot in the mix
    verifyplayer(kp, "SE_KILL kp")
    verifyplayer(vp, "SE_KILL vp")
    local kwitem = server.getitem(kwindex)
    local vwitem = server.getitem(vwindex)
    BeginEvent(LE_PLAYER_LOCATION)
    WriteByte(kp.num)
    WritePlayerLocation(kp)
    FlushEvent()
    
    BeginEvent(LE_PLAYER_LOCATION)
    WriteByte(vp.num)
    WritePlayerLocation(vp)
    FlushEvent()
    
    BeginEvent(LE_KILL)
    WriteByte(kp.num)
    WriteByte(vp.num)
    WriteWeaponNum(kwitem)
    WriteWeaponNum(vwitem)
    FlushEvent()
end)
addserverlistener(server.SE_SUICIDE, function(player)
    verifyplayer(player, "SE_SUICIDE")
    BeginEvent(LE_PLAYER_LOCATION)
    WriteByte(player.num)
    WritePlayerLocation(player)
    FlushEvent()
    
    BeginEvent(LE_SUICIDE)
    WriteByte(player.num)
    FlushEvent()
end)
addserverlistener(server.SE_FFIRE, function(kp, vp)
    verifyplayer(kp, "SE_FFIRE")
    verifyplayer(vp, "SE_FFIRE")
    BeginEvent(LE_PLAYER_LOCATION)
    WriteByte(kp.num)
    WritePlayerLocation(kp)
    FlushEvent()
    
    BeginEvent(LE_PLAYER_LOCATION)
    WriteByte(vp.num)
    WritePlayerLocation(vp)
    FlushEvent()
    
    if(kp == nil or vp == nil) then error("nil player in game; don't use bots (this session's state is now corrupt)") end
    BeginEvent(LE_FRIENDLYFIRE)
    WriteByte(kp.num)
    WriteByte(vp.num)
    FlushEvent()
end)
addserverlistener(server.SE_RESPAWN, function(player)
    verifyplayer(player, "SE_RESPAWN")
    BeginEvent(LE_RESPAWN)
    WriteByte(player.num)
    FlushEvent()
end)
addserverlistener(server.SE_FLAGGRAB, function(player)
    verifyplayer(player, "SE_FLAGGRAB")
    BeginEvent(LE_FLAG_GRAB)
    WriteByte(player.num)
    FlushEvent()
end)
addserverlistener(server.SE_FLAGDROP, function(player)
    verifyplayer(player, "SE_FLAGDROP")
    BeginEvent(LE_FLAG_DROP)
    WriteByte(player.num)
    FlushEvent()
end)
addserverlistener(server.SE_FLAGCAP, function(player)
    verifyplayer(player, "SE_FLAGCAP")
    BeginEvent(LE_FLAG_CAPTURED)
    WriteByte(player.num)
    FlushEvent()
end)
addserverlistener(server.SE_CHAT, function(player, text, teamchat)
    verifyplayer(player, "SE_CHAT")
    local wasteamchat = 0
    if(teamchat) then wasteamchat = 1 end
    
    BeginEvent(LE_CHAT)
    WriteByte(player.num)
    WriteByte(wasteamchat)
    WriteString(text)
    FlushEvent()
end)
addserverlistener(server.SE_MAPCHANGE, function(mapname)
    BeginEvent(LE_MAP_CHANGE)
    WriteString(mapname)
    FlushEvent()
end)
addserverlistener(server.SE_RESOLVED_GBLID, function(player)
    verifyplayer(player, "SE_RESOLVED_GBLID")
    BeginEvent(LE_GLS_IDENTIFIED)
    WriteByte(player.num)
    WriteUInt32(player.gblid)
    FlushEvent()
end)


-----------------------
-- General execution --
-----------------------
local timeserver = ""
local correctTimeFunc = nil
if(config.ENABLE_TIMESYNC) then
    print("TimeSync enabled, performing synchronization now...")
    
    -- Pick a random time server to start with   
    local serverindex =  math.random(1, #config.TIME_SERVERS)
    repeat
        timeserver = config.TIME_SERVERS[serverindex]
        print("Trying SNTP://"..timeserver)
        local errmsg
        correctTimeFunc,errmsg = sntp.GetCorrectTimeFunction(timeserver)
        if(correctTimeFunc ~= nil) then
            -- Success!
            print("Success! Synchronized to '" .. timeserver .. "'")
        else
            print("SNTP server '" .. timeserver .. "' failed: " .. errmsg)            
            -- Cycle to next server
            serverindex = serverindex + 1
            if(serverindex > #config.TIME_SERVERS) then serverindex = 1 end
        end
    until(correctTimeFunc ~= nil)
else
    warn("TimeSync is disabled, your logs are at risk of losing their time frames if your server time changes")
end

-- We use util.get_byte_from_float, where the parameter is of indeterminate
-- endianness (we'll assume a float is 4 bytes, though). Let's figure out
-- what we are working with.
local testnum = 1;
if(util.get_byte_from_float(testnum, 0) ~= 0) then -- this doesn't make sense to me, but it's big-endian if the leftmost byte is non-0... I need to read up on floats
    BIG_ENDIAN = true
    print("Detected big-endian architecture")
else
    BIG_ENDIAN = false
    print("Detected little-endian architecture")
end

-- Grab starting time
local START_TIME = getunixtime()
local START_SYNC_TIME = nil
if(config.ENABLE_TIMESYNC) then START_SYNC_TIME = correctTimeFunc() end
    
print("Using log version " .. LOG_VERSION)
if(config.ENABLE_LOCAL_LOG) then
    print("Local logging is enabled")
    local logname = "dps_lt"..START_TIME
    if(config.ENABLE_TIMESYNC) then
        logname = logname .. "_st" .. START_SYNC_TIME .. ".log"
    end
    local logfile = plugpath.."logs/"..logname
    print("Session log: " .. logfile)
    
    -- Try to open it
    logfilehandle,errmsg = io.open(logfile, "a+b") -- append only, only write to end
    if(logfilehandle ~= nil) then
        print("Successfully opened log file")
    else
        warn("Unable to open file, you may need to create the logs directory")
        error("Cannot open file: " .. errmsg)
    end
    
    -- Open the log summary file which keeps a list of log files in the order
    -- of their creation. This is used to establish the order of the logs, since
    -- we can never truly trust the timestamps for this purpose, even with SNTP.
    local logsummaryfile = plugpath.."logs/logsummary.log"
    print("Adding entry to log summary file: " .. logsummaryfile)
    logsummaryhandle,errmsg = io.open(logsummaryfile, "a+b") -- append only, only write to end
    if(logsummaryhandle ~= nil) then
        logsummaryhandle:write(logname .. "\n")
        logsummaryhandle:close()
        print("Successfully added log entry to summary log")
    else
        error("Cannot open file: " .. errmsg)
    end
end

BeginEvent(LE_LOGSTART)
WriteUInt16(LOG_VERSION)
if(config.ENABLE_TIMESYNC) then
    WriteByte(1)
    WriteUInt32(correctTimeFunc())
    WriteString("SNTP://"..timeserver)
else
    WriteByte(0)
    WriteUInt32(0)
    WriteString("")
end
FlushEvent()

updatecvars() -- log spec says to always do this at session start
