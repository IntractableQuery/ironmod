module("plugin_teambalance", package.seeall)

-- Required code
info = {
    name = "teambalance",  
    description = "Automatically balances teams",    
    author = "iron",
    version = "1.0",
    this = package.loaded.plugin_teambalance
}
registerplugin(info.this)
addserverlistener = server.geteventlistenerfunc(info.this)
addcommand = administration.getcommandregisterfunc(info.this)
-- End required code

---------------
-- Variables --
---------------
--- Holds the current player counts (updated by tallyplayercounts())
playercounts = {}

-----------------------------
-- Local utility functions --
-----------------------------
--- Returns a table where the keys are a server.TEAM_* constant and the values
-- are the player counts on those respective teams. A team that does not exist
-- will have no entry. This would include teams with nobody on them and obs.
function tallyplayercounts()
    playercounts = {}
    for i,player in pairs(server.players) do
        local teamid = player.teamindex
        if(teamid ~= server.TEAM_NONE) then -- obs isn't a valid team
            if(teamid == nil) then
                -- Ignore this player, they're probably connecting
            else
                local currentcount = playercounts[teamid]
                if(currentcount == nil) then currentcount = 0 end
                currentcount = currentcount + 1
                playercounts[teamid] = currentcount
            end
        end
    end
end
--- Tests if a team has an unfair advantage over the other teams. Note that 
-- other teams with no players whatsoever will be ignored. For example, a game
-- that is 5v0 has no imbalance, and a game that is 4v4v0 will have no
-- imbalance. This prevents annoying swapping, although all it takes is a 
-- single player joining the empty team to re-activate the balancing.
-- @param teamindex the team to test
-- @param extraplayers an optional argument that specifies an additional test to see if adding this number of players will unbalance the teams
-- @return true if the team has an unfair advantage, false otherwise
local function isteamunbalanced(teamindex, extraplayers)
    debug("isteamunbalanced: " .. server.getteamname(teamindex))
    assert(teamindex ~= nil, "teamindex cannot be nil")
    if(extraplayers == nil) then extraplayers = 0 end
    -- Check ourself against all other teams
    for otherteamindex,playercount in pairs(playercounts) do
        debug("Team (other)" .. server.getteamname(otherteamindex).." vs. (this)"..server.getteamname(teamindex), "thisteamplayercount/extraplayers/otherteamplayercount", playercounts[teamindex] ,extraplayers ,playercount)
        if(otherteamindex ~= teamindex and playercounts[teamindex] ~= nil and playercounts[teamindex] ~= 0 and (playercounts[teamindex] + extraplayers - playercount >= config.UNBALANCEDADVANTAGE)) then
            debug("Imbalance:" , playercounts[teamindex] ,extraplayers ,playercount)
            return true
        end
    end
    return false
end
--- Returns a player from the given team matching the desired criteria expressed
-- with config.PLAYERBALANCEMODE.
-- @param teamindex the team to find a player from
-- @return a player reference for the given team
local function grabplayerforbalance(teamindex)
    debug("Obtaining a player on team " .. teamindex .. " ("..server.getteamname(teamindex)..") for movement to another team")
    assert(teamindex ~= nil, "teamindex cannot be nil")
    if(config.PLAYERBALANCEMODE == "RANDOM") then
        local playercount = playercounts[teamindex]
        local nthplayer = math.random(1,playercount)
        local n = 1
        for i,player in pairs(server.players) do
            if(player.teamindex == teamindex) then -- Only iterate over players on the team we are pulling a player from!
                if(n == nthplayer) then
                    -- Here's our random player 
                    return player
                end
                n = n + 1
            end
        end
        error("nthplayer never found: nthplayer="..tostring(nthplayer)..", playercount="..tostring(playercount)) -- This should never happen... 
    elseif(config.PLAYERBALANCEMODE == "MAXKD" or config.PLAYERBALANCEMODE == "MINKD") then
        -- Calculate the kill-death ratios of each player
        local maxplayer, minplayer
        local maxkd, minkd
        for i,player in pairs(server.players) do
            if(player.teamindex == teamindex) then
                local kdratio = player.kills / player.deaths
                if(maxkd == nil or kdratio > maxkd) then 
                    maxkd = kdratio
                    maxplayer = player 
                end
                if(minkd == nil or kdratio < minkd) then 
                    minkd = kdratio
                    minplayer = player 
                end
            end
        end
        if(config.PLAYERBALANCEMODE == "MAXKD") then
            return maxplayer
        else
            return minplayer
        end
    elseif(config.PLAYERBALANCEMODE == "LOWTIME") then
        local mintime, minplayer
        for i,player in pairs(server.players) do
            if(player.teamindex == teamindex) then
                if(mintime == nil or player.starttime < mintime) then 
                    mintime = player.starttime
                    minplayer = player 
                end
            end
        end
        return minplayer
    end
  
end
--- Looks for a team with an unfair advantage (unbalanced) and returns the
-- player that can be moved to another team to even things up. 
-- @return a player reference or nil if there are no unbalanced teams
local function findswappableplayer()
    -- Find a team with an unfair advantage
    for teamindex=1,4 do -- Team indexes range from 1 to 4
        if(isteamunbalanced(teamindex)) then
            -- We found a team with an unfair advantage, so pick a player and return them
            return grabplayerforbalance(teamindex)
        else
        end
    end
    return nil
end
--- Returns the team index of the team with the lowest number of players.
-- No guaranteed order is imposed in the case of two teams having the
-- same number of players.
-- @return the team index with the lowest number of players
local function getsmallestteamindex()
    local minteamindex, minplayercount
    for teamindex,playercount in pairs(playercounts) do
        if(minteamindex == nil or minplayercount > playercount) then
            minteamindex = teamindex
            minplayercount = playercount
        end
    end
    return minteamindex
end
--- Checks for a player imbalance with the teams. Due to the nature of the
-- tallyplayercounts() function, this will not force people over to empty teams.
-- Of course, in a three or four team map, all it takes is one person joining
-- the empty team to trigger the balancing.
local function teambalance()
    server.printlineall(1, "Balancing teams...") -- TODO: rm this after debug
    for i,player in pairs(server.players) do
        local teamname = nil
        if(player.teamindex ~= nil) then
            teamname = server.getteamname(player.teamindex)
        end
        debug("TEAMDEBUG player entry: " .. tostring(player.teamindex) .. ":" .. tostring(teamname) .. ":" .. player.name)
    end
    
    -- This table maps player references to the new team index they will be forced to
    local balanceplayers = {}
    tallyplayercounts()
    for i=1,config.MAXBALANCEMOVE do
        -- NOTE: You can't call tallyplayercounts() in here repeatedly since the client command spoofing won't take place until later due to queuing
        local player = findswappableplayer()        
        if(player ~= nil) then            
            -- Swap this person to the team with the least amount of players
            local teamindex = getsmallestteamindex()
            local teamname = server.getteamname(teamindex)
            -- Manually fix the player counts table
            debug("My check:", tostring(player.teamindex), tostring(player.name), tostring(playercounts[player.teamindex]))-- The following line is somehow missing team info at times for playercounts[player.teamindex] (it's nil) when it should be fine, let's print some crap
            playercounts[player.teamindex] = playercounts[player.teamindex] - 1
            playercounts[teamindex] = playercounts[teamindex] + 1
            -- Tell everyone
            server.printlineall(1, "Moving %s to team %s to balance the teams", player.name, teamname)
            -- Make it look like the client is sending a JOIN command (yes, this is very hacky and has certain rare problems, but it generally works just fine)
            server.spoofclientcommand(player, {"join", teamname})
        else
            -- Nobody left to swap  
            if(i==1) then
                server.printlineall(1, "Teams look good, no balancing required.") -- TODO: rm this after debug
            end          
            return
        end        
    end
end

---------------
-- LISTENERS --
---------------
addserverlistener(server.SE_ROUNDOVER, function()
    -- Check to see if we need to balance the teams
    teambalance()
end)

if(config.ENFORCEBALANCE) then
    addserverlistener(server.SE_CLIENTCOMMAND, function(player, clientcommands)
        -- Add a listener to block players from joining teams
        if(#clientcommands >= 2 and string.upper(clientcommands[1]) == "JOIN") then  
            debug("CLIENT JOINTEAM REQUEST:", unpack(clientcommands))   
            for i=1,4 do
                debug("players on " .. server.getteamname(i) .. ": " .. tostring(playercounts[i]))
            end
            tallyplayercounts()       
            local teamname = string.lower(clientcommands[2])
            local jointeamindex = server.getteamindex(teamname)
            if(jointeamindex ~= server.TEAM_NONE) then
                -- Would allowing the join make the target team have too many players?
                tallyplayercounts()
                if(playercounts[player.teamindex] ~= nil) then -- Observers don't have this stuff...not sure about player.teamindex
                    playercounts[player.teamindex] = playercounts[player.teamindex] - 1 -- Remove this player from their team before we check for imbalance
                end
                if(isteamunbalanced(jointeamindex, 1)) then -- Check for imbalance, giving a +1 extra player to each team (this player)
                    -- Letting the player join this team would be unfair. Tell them, and block it.
                    server.printlineclient(1, player, "You cannot join team "..server.getteamname(jointeamindex).."; that would unbalance the teams.")
                    return true
                end                
            end
        end
    end)
end

addcommand("tally", 200, administration.CMDTYPE_SILENT, true, nil, "Debugging command to see player tally result", function(text, sourcelevel, player, replyfunc, cmdinfo)
    tallyplayercounts() 
    for teamindex,count in pairs(playercounts) do
        replyfunc("Team " .. teamindex .. " ("..server.getteamname(teamindex).."): " .. tostring(count) .. " players")
    end      
    for i,player in pairs(server.players) do
        local teamname = nil
        if(player.teamindex ~= nil) then
            teamname = server.getteamname(player.teamindex)
        end
        replyfunc(tostring(player.teamindex) .. ":" .. tostring(teamname) .. ":" .. player.name, 2)
    end
    replyfunc("End of teams.")
end)
