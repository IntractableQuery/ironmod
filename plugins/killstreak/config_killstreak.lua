module("config_killstreak", package.seeall) -- DO NOT REMOVE THIS LINE (please make sure it matches the filename without the .lua extension)

-- Configuration for ....
--- UT99/quake sounds. 
utsounds = {
    path            = "ironmod/spreekill/q/", -- Path to sounds
}
utsounds.sounds = { -- You can remove some of these sounds if you wish
        firstkill   = "firstblood.wav", -- first kill of the new round
        pgpkill     = "humiliation.wav", -- played when a player kills another with the PGP (if globalsound is false, this plays for both of the players involved, not just the killer)
        spree_3     = "killingspree.wav",
        spree_4     = "monsterkill.wav",
        spree_5     = "ultrakill.wav",
        spree_6     = "dominating.wav",
        spree_7     = "rampage.wav",
        spree_8     = "godlike.wav",
        spree_9     = "holyshit.wav"
}
utsounds.messages = { -- You can remove some of these messages if you wish
        firstkill   = "$killer gets FIRST BLOOD",
        --pgpkill     = "$killer has humiliated $victim with the PGP",
        spree_3     = "$killer is on a KILLING SPREE!",
        spree_4     = "$killer made a MONSTER KILL!",
        spree_5     = "$killer made an ULTRA KILL!",
        spree_6     = "$killer is DOMINATING!",
        spree_7     = "$killer is on a RAMPAGE!",
        spree_8     = "$killer is GODLIKE!",
        spree_9     = "$killer has made $streak kills without dying... HOLY SHIT!!!"
}
--- Set this to the set of sounds you want to use (utsounds)
usesounds = utsounds
--- If true, messages are printed to all players when the sound is played
usemessages = true
--- If true, the sound gets sent to all players. If false, it is played where the player is currently located when they made the kill.
globalsound = false
--- This is the attentuation level used if you have globalsound set to false.
-- Use a value from 1.0 to 4.0, where a higher value means more sound falloff. 
-- Remember that you can't hear this sound falloff at all if you are the one the sound is playing for. 
-- As a baseline to compare with, player death sounds are a 2.0 and weapon/item pickups are a 3.0. 
-- An attentuation of 4.0 will result in only the player who did the killing hearing it.
sound_attenuation_level = 2.5 
--- This is the sound channel used for all sound that is played. You should probably leave it alone.
-- Basically, if it is an integer, it is useful for preventing two sounds from playing at once for a single player 
-- (so, if I get two kills really fast and they both produced sounds, the last sound to play overrides the earlier one).
-- Set this to nil if you want an auto-allocated sound channel, which will just play the sound as it comes, even if it overlaps another.
sound_channel = 15 -- This doesn't appear to be a channel used by anything else, so it should be good for our purposes...

