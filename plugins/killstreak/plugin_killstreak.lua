module("plugin_killstreak", package.seeall)

-- Required code
info = {
    name = "killstreak",  
    description = "Kill streak notification sounds/messages",    
    author = "iron",
    version = "1.0.0"
}
registerplugin(package.loaded.plugin_killstreak)
addserverlistener = server.geteventlistenerfunc(package.loaded.plugin_killstreak)
-- End required code

------------------------
-- Internal variables --
------------------------
local can_play_firstkill = true -- Reset to true every time a new round starts
local MODE_JUSTKILLER = 0
local MODE_BOTH = 1
local usesounds = config.usesounds

---------------
-- Functions --
---------------
--- Plays a sound for the given player(s) using our current settings.
-- @param player the player who did the killing
-- @param player the player who was killed
-- @param soundkey the key of the sound
-- @param soundplaymode MODE_JUSTKILLER to play the sound for just the killer, MODE_BOTH to play it for both the killer and victim (only applies if globalsound is false)
-- @return true if the soundkey had a sound entry that played, false if it didn't play
local function playsoundfor(player, victim, soundkey, atten, soundplaymode) 
    -- We can handle nil players (bots) without erroring, but you shouldn't be using ironmod with bots anyway...
    local soundfile = usesounds.sounds[soundkey]
    local message = usesounds.messages[soundkey]
    local hadsoundkey = false
    if(soundfile ~= nil) then
        hadsoundkey = true
        local soundindex = server.getsoundindex(usesounds.path .. soundfile)
        if(config.globalsound) then
            -- Since we want to use our own custom channel, we can't use server.playsound_all()
            if(player ~= nil) then
                server.playsound_ent(player.ent, config.sound_channel, soundindex, 1.0, nil, 0, false)     
            elseif(victim ~= nil) then
                server.playsound_ent(victim.ent, config.sound_channel, soundindex, 1.0, nil, 0, false)     
            end
        else
            if(player ~= nil) then
                server.playsound_ent(player.ent, config.sound_channel, soundindex, 1.0, config.sound_attenuation_level, 0, true)
            end
            if(soundplaymode == MODE_BOTH and victim ~= nil) then
                 server.playsound_ent(victim.ent, config.sound_channel, soundindex, 1.0, config.sound_attenuation_level, 0, true)   
            end
        end
    end
    
    -- TODO: this is very, very ugly. come up with a better way to hop around proper use of the print function without doing all this.
    if(message ~= nil and config.usemessages) then
        -- Perform any safe non-colored replacements
        if(player ~= nil) then message = string.gsub(message, "$streak", player.streak) end
        
        -- Perform formatted replacements
        local format_specifier = message.gsub(message, "%%", "%%%%") -- Escape the %'s for the format specifier
        local args = {}
        local killer_replace = function(s)
            if(player ~= nil) then
                args[#args+1] = player.name
                return "%s"
            else return "?" end
        end
        format_specifier = string.gsub(format_specifier, "$killer", killer_replace)
        local victim_replace = function(s)
            if(victim ~= nil) then
                args[#args+1] = victim.name
                return "%s"
            else return "?" end
        end
        format_specifier = string.gsub(format_specifier, "$victim", victim_replace)
        dump.printtable(args)
        server.printlineall(format_specifier, unpack(args))
    end
    
    return hadsoundkey
end

---------------
-- Listeners --
---------------
listen.game.precall(GE_SPAWNENTITIES, function(data) 
    -- Register our sounds so clients will download them -- calling getsoundindex() will put them in the server's configstrings
    for name,filename in pairs(usesounds.sounds) do
        server.getsoundindex(usesounds.path .. filename)
    end
    
    -- Just to be sure...
    server.putconsole("set allow_download_sounds 1")
end)

addserverlistener(server.SE_ROUNDSTART, function()
    can_play_firstkill = true -- reset
end)

addserverlistener(server.SE_KILL, function(killerplayer, kwep, victimplayer, vwep, text)   
    -- This will only play one sound. Precedence:
    -- Streak
    -- PGP kill
    -- First blood
    if(killerplayer ~= nil) then -- clearly, this will only play sounds for non-bots, although it works fine for human players who are *killing* bots       
        local streak = killerplayer.streak
        local playedspreesound = playsoundfor(killerplayer, victimplayer, "spree_" .. streak, MODE_JUSTKILLER)
        local playedpgpsound = false
        
        if((not playedspreesound) and server.getitem(kwep) == "PGP") then -- TODO: if you ever set up item constants, use that instead
            playedpgpsound = playsoundfor(killerplayer, victimplayer, "pgpkill", MODE_BOTH)
        end
        
        if(can_play_firstkill) then
            if ((not playedspreesound) and not(playedpgpsound)) then
                if(not config.globalsound) then
                    -- Only play firstkill at the same time as spree if it's not global (we don't want *everyone* to suffer them at the same time!)
                    playsoundfor(killerplayer, victimplayer, "firstkill", MODE_JUSTKILLER)
                end
            end
            can_play_firstkill = false
        end
    end
end)
