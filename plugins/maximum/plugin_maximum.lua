module("plugin_maximum", package.seeall)

-- Required code
info = {
    name = "maximum",  
    description = "Awesome crysis abilities",    
    author = "iron",
    version = "1.0",
    this = package.loaded.plugin_maximum
}
registerplugin(info.this)
addserverlistener = server.geteventlistenerfunc(info.this)
addcommand = administration.getcommandregisterfunc(info.this)
-- End required code

------------------------
-- Internal variables --
------------------------
local sound_cloak = "ironmod/maximum/c.wav"
local sound_armor = "ironmod/maximum/a.wav"
local sound_speed = "ironmod/maximum/sp.wav"
local sound_strength = "ironmod/maximum/st.wav"
local sound_off = "ironmod/maximum/off.wav"

---------------
-- Functions --
---------------
local function getplayermaximumtable(player)
    local maxtable = player.plugindata.maximum
    if(maxtable == nil) then
        maxtable = {}
        maxtable.cloak = false
        maxtable.strength = false
        maxtable.grabbedplayer = nil
        maxtable.speed = false
        maxtable.speedangle = 0
        maxtable.armor = false
    end
    player.plugindata.maximum = maxtable
    return maxtable
end
local function getenabledstuff(player, omit)
    local maxtable = getplayermaximumtable(player)
    local stuff = ""
    local checkentries = { "cloak", "strength", "speed", "armor" }
    for i,entry in ipairs(checkentries) do
        if(entry ~= omit and maxtable[entry] == true) then
            stuff = stuff .. entry:upper() .. " "
        end
    end
    return stuff:match("^%s*(.-)%s*$")
end
local function findclosestplayerto(player, maxdistance)
    -- We only inspect X/Y axis
    local closestplayer = nil
    local lowestdistance = nil
    local mypos = extra.get3dvector(player.ent.s.origin)
    for i,otherplayer in pairs(server.players) do
        if(otherplayer ~= player and otherplayer.alive) then
            local otherpos = extra.get3dvector(otherplayer.ent.s.origin)
            local distance = math.sqrt(math.pow(otherpos.x-mypos.x, 2) + math.pow(otherpos.y-mypos.y, 2))
            if(lowestdistance == nil or distance < lowestdistance) then
                if(distance <= maxdistance) then
                    closestplayer = otherplayer
                    lowestdistance = distance
                end
            end
        end
    end
    
    return closestplayer
end

---------------
-- Listeners --
---------------
listen.game.precall(GE_SPAWNENTITIES, function(data) 
    -- Register our sounds so clients will download them -- calling getsoundindex() will put them in the server's configstrings
    server.getsoundindex(sound_cloak)
    server.getsoundindex(sound_speed)
    server.getsoundindex(sound_armor)
    server.getsoundindex(sound_strength)
    server.getsoundindex(sound_off)
    
    -- Just to be sure...
    server.putconsole("set allow_download_sounds 1")
    
    -- reset player states
    for i,player in pairs(server.players) do
        player.plugindata.maximum = nil -- Reset entire table        
    end
    -- todo: spin won't turn off when round restarts
end)

addserverlistener(server.SE_KILL, function(kp, kw, vp, vw)
    if(vp ~= nil) then
        local maxtable = getplayermaximumtable(vp)
        if(maxtable.cloak) then
            -- Decloak them upon death
            maxtable.cloak = false
            vp.ent.svflags = 0
        end
    end
end)

listen.game.postcall(GE_RUNFRAME, function(data)
    for i,player in pairs(server.players) do
        local maxtable = getplayermaximumtable(player)
        if(maxtable.speed) then
            -- Spin the player
            if(maxtable.speedangle >= 180) then 
                maxtable.speedangle = maxtable.speedangle - 360
            else
                maxtable.speedangle = maxtable.speedangle + 200
            end
            local angles = extra.get3dvector(player.ent.s.angles)
            local vec = util.allocate_vec3_t(angles.x, maxtable.speedangle, angles.z)
            player.ent.s.angles = vec
            player.ent.s.frame = math.random(0, 190)
            util.deallocate_mem(vec)
        end
        if(maxtable.strength) then
            -- Todo: clients that disconnect will mess this up
            -- Update the grabbed player's position to the front of the grabber 
            local angles = extra.get3dvector(player.ent.s.angles)
            local origin = extra.get3dvector(player.ent.s.origin)
            local radius = 100
            local angle = math.rad(angles.y)
            local neworigin = util.allocate_vec3_t(origin.x+math.cos(angle)*radius, origin.y+math.sin(angle)*radius, origin.z+31)
            -- Do a trace to prevent sticking someone in/through a wall
            local trace = gidp.trace(player.ent.s.origin, maxtable.grabbedplayer.ent.mins, maxtable.grabbedplayer.ent.maxs, neworigin, maxtable.grabbedplayer.ent, 3)
            maxtable.grabbedplayer.ent.s.origin = trace.endpos
            maxtable.grabbedplayer.ent.s.oldorigin = trace.endpos
            util.deallocate_mem(neworigin)
        end
    end
end)

addcommand("cloak", 300, administration.CMDTYPE_SILENT, false, nil, "Makes you invisible (or, visible again).", function(text, sourcelevel, player, replyfunc)
    local maxtable = getplayermaximumtable(player)
    if(maxtable.cloak) then
        -- Disable cloak
        maxtable.cloak = not maxtable.cloak
        player.ent.svflags = 0
        server.playsound_ent(player.ent, nil, server.getsoundindex(sound_off), 1.0, 2.5, 0, true)
        replyfunc("Cloak disabled ("..getenabledstuff(player)..")")
    else
        -- Enable cloak
        maxtable.cloak = not maxtable.cloak
        player.ent.svflags = game.SVF_NOCLIENT
        server.playsound_ent(player.ent, nil, server.getsoundindex(sound_cloak), 1.0, 2.5, 0, true)
        replyfunc("CLOAK ENGAGED ("..getenabledstuff(player)..")", 2)
    end
end)
addcommand("armor", 300, administration.CMDTYPE_SILENT, false, nil, "Makes you invincible (or, vulnerable again). You also can be walked through.", function(text, sourcelevel, player, replyfunc)
    local maxtable = getplayermaximumtable(player)
    if(maxtable.armor) then
        maxtable.armor = not maxtable.armor
        player.ent.solid = game.SOLID_BBOX
        server.playsound_ent(player.ent, nil, server.getsoundindex(sound_off), 1.0, 2.5, 0, true)
        replyfunc("Armor disabled ("..getenabledstuff(player)..")")
    else
        maxtable.armor = not maxtable.armor
        player.ent.solid = game.SOLID_NOT
        server.playsound_ent(player.ent, nil, server.getsoundindex(sound_armor), 1.0, 2.5, 0, true)
        replyfunc("MAXIMUM ARMOR ("..getenabledstuff(player)..")", 2)
    end
end)
addcommand("speed", 300, administration.CMDTYPE_SILENT, false, nil, "Twists you around like a retard", function(text, sourcelevel, player, replyfunc)
    local maxtable = getplayermaximumtable(player)
    if(maxtable.speed) then
        maxtable.speed = not maxtable.speed
        server.playsound_ent(player.ent, nil, server.getsoundindex(sound_off), 1.0, 2.5, 0, true)
        replyfunc("Speed disabled ("..getenabledstuff(player)..")")
    else
        maxtable.speed = not maxtable.speed
        server.playsound_ent(player.ent, nil, server.getsoundindex(sound_speed), 1.0, 2.5, 0, true)
        replyfunc("MAXIMUM SPEED ("..getenabledstuff(player)..")", 2)
    end
end)
addcommand("strength", 100, administration.CMDTYPE_SILENT, false, nil, "Grabs the closest player (or drops the current one).", function(text, sourcelevel, player, replyfunc)
    local maxtable = getplayermaximumtable(player)
    if(maxtable.strength) then
        maxtable.strength = not maxtable.strength
        server.playsound_ent(player.ent, nil, server.getsoundindex(sound_off), 1.0, 2.5, 0, true)
        replyfunc("Strength disabled ("..getenabledstuff(player)..")")
    else
        local otherplayer = findclosestplayerto(player, 160) -- Try to find a player in 160 unit radius
        if(otherplayer ~= nil) then
            maxtable.strength = not maxtable.strength
            maxtable.grabbedplayer = otherplayer
            server.playsound_ent(player.ent, nil, server.getsoundindex(sound_strength), 1.0, 2.5, 0, true)            
            replyfunc("MAXIMUM STRENGTH ("..getenabledstuff(player)..")", 2)
            replyfunc("Grabbed " .. otherplayer.name, 3)
        else
            replyfunc("No player to grab (you need to get closer to your target)", 3)
        end
    end
end)

