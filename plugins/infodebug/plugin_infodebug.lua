module("plugin_infodebug", package.seeall)

-- Required code
info = {
    name = "infodebug",  
    description = "Provides configurable verbose output to debug ironmod's events",    
    author = "iron",
    version = "1.0"
}
local this = package.loaded.plugin_infodebug
registerplugin(this)
addserverlistener = server.geteventlistenerfunc(this)
addcommand = administration.getcommandregisterfunc(this)
-- End required code

--- Maps event integer values to their name
local ge_events
--- Maps event integer values to their name
local gidp_events
--- Maps event integer values to their name
local se_events

--- This hacky function will kindly return a table of all fields matching
-- the given pattern in the given table.
-- @param t the table to search
-- @param patternmatch the pattern to match for the field name
-- @return a table of the fields and their values
function findfields(t, patternmatch)
    local r = {}
    for key,val in pairs(t) do
        if(type(key) == "string" and key:match(patternmatch)) then
            r[key] = val
        end
    end
    return r
end
--- Switches key/values in a table and returns the result.
-- @param t the table to use, but not modify
-- @return the switched table
function switchkeyvals(t)
    local r = {}
    for key,val in pairs(t) do
        r[val] = key
    end
    return r
end


-- Initialize the event tables
ge_events = switchkeyvals(findfields(_G, "^GE_.*$"))
gidp_events = switchkeyvals(findfields(_G, "^GIDP_.*$"))
se_events = switchkeyvals(findfields(server, "^SE_.*$"))


if(config.DISPLAY_GE_EVENTNAMES) then
    print("Will display GE (game) event names")
    -- Register a listener for every GE event
    listener = function(data, eventid)
        debug("GE EVENT: " .. ge_events[eventid] .. " ("..eventid..")")
    end
    for eventid,eventname in pairs(ge_events) do
        listen.game.postcall(eventid, listener)
    end
end

if(config.DISPLAY_GI_EVENTNAMES) then
    print("Will display GI (dp) event names")
    listener = function(data, eventid)
        debug("GIDP EVENT: " .. gidp_events[eventid] .. " ("..eventid..")")
    end
    for eventid,eventname in pairs(gidp_events) do
        listen.dp.postcall(eventid, listener)
    end
end

if(config.DISPLAY_SE_EVENTS) then
    print("Will display SE (lua server) event information")
    for eventid,eventname in pairs(se_events) do
        debug("Listening for SE event " .. eventname .. " ("..eventid..")")
        addserverlistener(eventid, function(...)
            debug("SE EVENT: " .. eventname .. " ("..eventid..") -> ", ...)
        end)
    end
end


