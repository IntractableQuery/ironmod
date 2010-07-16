module("plugin_testing", package.seeall)

-- Required code
info = {
    name = "testing",  
    description = "Testing...",    
    author = "iron",
    version = "1.0.0"
}
registerplugin(package.loaded.plugin_testing)
addserverlistener = server.geteventlistenerfunc(package.loaded.plugin_testing)
addcommand = administration.getcommandregisterfunc(package.loaded.plugin_testing)
-- End required code

local cback

listen.dp.postcall(GIDP_LINKENTITY, function(data)
    if(1==1) then return end
    debug("LINKENTITY")
    dump.printent(data.ent)
    debug("===================")
end)

listen.dp.postcall(GIDP_CVAR_SET, function(data)
    debug("CVAR_SET", data.var_name, tostring(data.value), "X", tostring(data.value.value))
end)

listen.dp.postcall(GIDP_CVAR_FORCESET, function(data)
    debug("CVAR_FORCESET", data.var_name, data.value.string)
end)

function planton(player)
    if(1==1) then return end
    local entity = util.allocate_edict_t()
    entity.s.modelindex = server.getmodelindex("models/plants/bigleaf2.md2")
    entity.solid = game.SOLID_NOT
    entity.inuse = 1
    entity.owner = player.ent
    local origin = player.ent.s.origin
    entity.s.origin = origin
    debug("")
    debug("")
    debug("")
    
    dump.printent(entity)
    gidp.linkentity(entity)
    
    debug("LINKED")
    dump.printent(entity)
    util.deallocate_mem(entity)
end

listen.game.postcall(GE_RUNFRAME, function(data)
    for i,player in pairs(server.players) do
        planton(player)
    end
end)

addserverlistener(server.SE_CHAT, function(player, text, teamchat)
    local name = "????"
    if(player ~= nil) then name = player.name end
    debug("->>>CHAT", name, text, teamchat)
end)

addserverlistener(server.SE_RESOLVED_GBLID, function(player)
    server.printlineall(1, "Just found: %s has id " .. player.gblid, player.name)
end)


local grabbedplayer,grabberplayer
listen.game.postcall(GE_RUNFRAME, function(data)
    local matrix = require("matrix")
    if(grabberplayer ~= nil and grabbedplayer ~= nil) then
        local angles = extra.get3dvector(grabberplayer.ent.s.angles)
        local origin = extra.get3dvector(grabberplayer.ent.s.origin)
        -- Note: only x/y are used in angles, and they are in degrees
        local magnitude = 100 -- Just need a reasonable value to extend beyond where the player is looking   
        local pitch,yaw,roll = math.rad(angles.x),math.rad(angles.y),math.rad(angles.z)
        debug("ANGLES:",angles.x,angles.y,angles.z,".....",pitch, yaw, roll)
        -- BEGIN PITCHYAWWHATEVER TO UNIT VECTOR
        -- See http://www.wolffdata.se/strapdown/strapdownhtml/strapdown.html "summary"
        local startvector = matrix{{1}, {0}, {0}} -- The unit vector we are going to rotate
        local matrix1 = { {1, 0,                0},
                          {0, math.cos(roll),   -math.sin(roll)},
                          {0, math.sin(roll),  math.cos(roll)} }
                        
        local matrix2 = { {math.cos(pitch), 0,  math.sin(pitch)},
                          {0,               1,  0},
                          {-math.sin(pitch), 0,  math.cos(pitch)} }
                          
        local matrix3 = { {math.cos(yaw),  -math.sin(yaw),  0},
                          {math.sin(yaw), math.cos(yaw),  0},
                          {0,               0,               1} }
        local resultmatrix = matrix.mul(matrix.mul(matrix.mul(matrix2, matrix3), matrix1), startvector)
        server.printlineall(1, "%s", angles.x..","..angles.y..","..angles.z)
        debug(resultmatrix:tostring())
        local vector = {x=resultmatrix[1][1]*magnitude, y=resultmatrix[2][1]*magnitude, z=resultmatrix[3][1]*magnitude}
        debug("VEC:", extra.formatvector(vector))
        
        -- END DAT SHET
        -- Add the directional vector to the origin to get the endpoint we want
        local endvec = {
            x = vector.x + origin.x,
            y = vector.y + origin.y,
            z = origin.z + 31
        }
        debug("endvec: " .. extra.formatvector(endvec))
        -- Make the endpoint into a vector to pass
        local endpoint = util.allocate_vec3_t(endvec.x, endvec.y, endvec.z)
        
        dump.printtable(angles)
        
        local trace = gidp.trace(grabberplayer.ent.s.origin, grabbedplayer.ent.mins, grabbedplayer.ent.maxs, endpoint, grabbedplayer.ent, 3)
        debug("allsolid=", trace.allsolid, "startsolid=", trace.startsolid, "fraction=", trace.fraction)
        grabbedplayer.ent.s.origin = trace.endpos
        grabbedplayer.ent.s.oldorigin = trace.endpos --trace.endpos
        util.deallocate_mem(endpoint)
    end
end)
listen.dp.postcall(GIDP_TRACE, function(data)
    if(1==1) then return end
    debug("TRACE:",  extra.vec3tostring(data.start),extra.vec3tostring(data.mins),extra.vec3tostring(data.maxs),extra.vec3tostring(data["end"]), "CONTENT", data.contentmask)
    dump.printent(data.passent)
        debug("===================================")
end)
addcommand("t", 0, administration.CMDTYPE_SILENT, false, "usage lol", "A test command.", function(text, sourcelevel, player, replyfunc)
    local moveplayer = nil
    for i,p in pairs(server.players) do
        if(p ~= player) then moveplayer = p end
    end
    grabbedplayer = moveplayer
    grabberplayer = player
end)

addcommand("wat", 0, administration.CMDTYPE_SILENT, false, "usage lol", "A test command.", function(text, sourcelevel, player, replyfunc)
    --planton(player)
    for i,otherplayer in pairs(server.players) do
        --otherplayer.ent.solid = game.SOLID_NOT
        --otherplayer.ent.s.solid = game.SOLID_NOT
        debug("RENDERFX:", otherplayer.ent.s.renderfx)
        otherplayer.ent.s.renderfx = 99999999
        debug("RENDERFX:", otherplayer.ent.s.renderfx)
        otherplayer.ent.s.event = 99999999
        otherplayer.ent.s.effects = 99999999
        otherplayer.ent.s.frame = 1
    end
   -- player.ent.svflags = game.SVF_NOCLIENT
    
    replyfunc("ok did it")
end)

addcommand("test", 200, administration.CMDTYPE_SEEALL, false, "usage lol", "A test command.", function(text, sourcelevel, player, replyfunc)
    replyfunc("Command handler for test got this:".. text,3)
end)

addcommand("test2", 0, administration.CMDTYPE_SEEALL, false, "usage lol", "A test command 2.", function(text, sourcelevel, player, replyfunc)
    replyfunc("Command handler for test2 got this:".. text)
end)

addcommand("yay", 0, administration.CMDTYPE_SILENT, false, "usage lol", "Silent :>.", function(text, sourcelevel, player, replyfunc)
    replyfunc("Command handler for yay got this:".. text)
    administration.docommandhelp(0, replyfunc)
end)
administration.addcommandalias("x", "yay")

t = {
    testkey = "hello",
    testtable = { "this", "is", "an", "array" },
    nestedtable = {a=100, b=true, c="HELLO M8"},
    testboolean = true,
    troublestring = "lol\they\nthere he he he!!!!@@$@!"
}

f = io.open(plugpath.."testoutput.txt", "w")
debug("file handle is", f)
extra.serialize(f, t)
f:close()

f = io.open(plugpath.."testoutput.txt", "r")
local deserialized_table = extra.deserialize(f:lines())
f:close()

debug("TESTO:")
dump.printtable(deserialized_table)



