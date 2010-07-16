module("plugin_rockthevote", package.seeall)

-- Required code
info = {
    name = "rockthevote",  
    description = "Provides early map vote initiation if enough players want to change the map",    
    author = "iron",
    version = "1.0.0"
}
local this = package.loaded.plugin_rockthevote -- Helps us keep track of ourself
registerplugin(this)
addserverlistener = server.geteventlistenerfunc(this)
addcommand = administration.getcommandregisterfunc(this)
-- End required code

----------------------
-- Local state vars --
----------------------
local rockedthevote = false -- This is set to true as soon as rockthevote is successful
local lockedthevote = false -- This is set if an admin overrides the vote
local default_timelimit = nil -- The server's timelimit before we started messing with it

---------------------
-- Local functions --
---------------------
--- Initializes a player's plugin data for our purposes and returns this data. If the
-- player has already been initialized, then nothing is changed and their current data
-- is returned.
-- @return rockthevote plugin data
local function getrtvdata(player) 
    if(player.plugindata.rockthevote ~= nil) then return player.plugindata.rockthevote end -- This person already has data!
    player.plugindata.rockthevote = {}
    local rtvdata = player.plugindata.rockthevote
    rtvdata.rocked = false
    return rtvdata
end

--- Returns the number of players needed to rock the vote trigger a map change via rockthevote.
-- @return a player count
local function getneededvotecount()
    return math.ceil((config.rtv_percentpass / 100) * server.playercount)
end

--- Counts the number of vote rocks we have so far.
-- @return the number of players who've rocked the vote
local function countvoterocks() 
    local count = 0
    for key,player in pairs(server.players) do
        local rtv = getrtvdata(player)
        if(rtv.rocked) then count = count + 1 end
    end
    return count
end

--- Tells everyone about a player rocking the vote
-- @param player the player who rocked the vote
local function notify_voterocked(player)
    local numvotes = countvoterocks()
    local neededvotes = getneededvotecount()
    local extrahelp = config.messages.EXTRAHELP
    if(config.rtv_visible) then extrahelp = "" end -- no reason to provide extra help if people can see other players doing it
    server.printlineall(1, config.messages.WANTROCK, player.name, numvotes, neededvotes, extrahelp)
end

--- Called to force a map vote. This is what happens some time after we rock the vote.
local function forcevote() 
    if(lockedthevote) then return end
    
    server.printlineall(1, config.messages.VOTEROCKED_FORCEVOTE) 
    
    -- TODO: I can't remember if there is a cvar that turns map voting on/off... if there is, you need to enable it
    
    -- Get the current timelimit - it will be restored when the map changes
    default_timelimit = tonumber(server.getcvar("timelimit", "20"))
    
    -- I don't know if this is really a safe thing to do, but it works very well
    server.setcvar("timelimit", "-1") 
end

--- Handles a player wanting to rock the vote.
-- @param player the player that wants to rock the vote
-- @param replyfunc a function that can be used to send reply(ies) back to the client
-- @return true if the command they sent should be showed to everyone
local function handleplayervote(player, replyfunc) 
    if(lockedthevote) then
        -- An admin disabled the vote for this game
        replyfunc(config.messages.NOROCK_ADMIN)
        return false
    end
    
    if(rockedthevote) then
        -- We already rocked the vote
        replyfunc(config.messages.NOROCK_ALREADYROCKED)
        return false
    end
    
    -- Retrieve the table we're storing on this player, or create a new one if we've not done so yet
    -- The information in the table is as follows:
    --   rocked, a boolean value indicating if we've rocked the vote yet
    local rtv = getrtvdata(player)
    
    
    if(rtv.rocked == true and not config.rtv_multiple) then
        -- This player already rocked the vote and we do not allow multiple vote rockings
        replyfunc(config.messages.NOROCK_YOUROCKED)
        return false
    end
    
    rtv.rocked = true
    notify_voterocked(player) -- tell everyone
    
    local numvotes = countvoterocks()
    local neededvotes = getneededvotecount()
    
    if(numvotes >= neededvotes) then
        -- The vote is rocked!
        rockedthevote = true
        
        if(config.waitround) then
            -- We will let the round end (we have a listener that handles this)
            replyfunc(config.messages.ROCKED_ENDOFROUND)        
        else
            -- Vote immediately
            forcevote()    
        end
    end
    
    return true
end

---------------
-- Listeners --
---------------
addserverlistener(server.SE_MAPCHANGE, function()
    -- A new map is being loaded, reset things
    rockedthevote = false
    lockedthevote = false
    -- Fix what we did to timelimit last game if we need to
    if(default_timelimit ~= nil) then
        server.setcvar("timelimit", default_timelimit)
        default_timelimit = nil
    end
    -- Go through the players we still have and make sure they can rock the vote again
    for key,player in pairs(server.players) do
        getrtvdata(player).rocked = false
    end
end)

addserverlistener(server.SE_ROUNDOVER, function()
    if(rockedthevote and config.rtv_waitround) then
        -- We've already rocked the vote, do it
        forcevote()
    end
end)

local rockthevote_cmdtype = administration.CMDTYPE_SILENT
if(config.rtv_visible) then rockthevote_cmdtype = administration.CMDTYPE_SEEALL end
addcommand("rockthevote", 0, rockthevote_cmdtype, false, nil, "Registers your request to change the map", function(text, sourcelevel, player, replyfunc, cmdinfo)
    handleplayervote(player, replyfunc)
end)
administration.addcommandalias("rtv", "rockthevote")
addcommand("rtvoverride", 100, administration.CMDTYPE_SILENT, false, nil, "Disables RTV for this map session", function(text, sourcelevel, player, replyfunc, cmdinfo) 
    server.printlineall(1, config.messages.ALLOW_ADMIN, player.name)
    lockedthevote = true    
end)
