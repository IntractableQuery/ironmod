module("config_rockthevote", package.seeall) -- DO NOT REMOVE THIS LINE 

--- If true, then using the "rockthevote" command in chat will result in it
 -- showing up to other players too.
 -- If false, then the message is blocked so that others won't see it. 
 -- However, each rockthevote notification will contain a short bit of 
 -- information telling others how to rockthevote. There is no suggested setting 
 -- for this value. Setting it to false reduces message spam, though.
rtv_visible = false

--- If true, this will allow a single person to keep rocking the vote (the message indicating that they rocked the vote
 -- will show up each time they do it, although their vote still only counts one time).
 -- If false, then a single player can only rock the vote once (people will only see that they rocked the vote
 -- just one time).
 -- The suggested value for this is true, as it lets people easily see how many votes they still need.
rtv_multiple = true

--- This is the percentage of players in the server that must have rocked the vote in order to trigger
 -- a map vote. It is expressed as a number between 0 and 100, inclusive. Note that in calculating
 -- the number of players required for the vote from this percentage, that the ceiling is always
 -- taken. For example, 51% of 7 players is 4 players.
 -- You can use decimals if you like (ie: 67.5).
 -- It is suggested that you set this to 51 or greater.
rtv_percentpass = 51

--- If true, when the vote is rocked, it will wait until the end of the round to start the map vote.
 -- If false, when the vote is rocked, the map vote will immediately start (ending the game immediately).
 -- It is suggested you set this to true, as it lets people finish up playing first.
rtv_waitround = true

--- These are the messages used for various situations.
messages = {
    WANTROCK =              "%s wants to rock the vote (%s/%s)%s", -- WARNING: Do not change the number of %s's here, they are "name", "numvotes", "neededvotes", "extrahelp"
    EXTRAHELP =             ", type !rtv to join in",
    VOTEROCKED_FORCEVOTE =  "The vote was rocked, vote for the next map",
    NOROCK_ADMIN =          "You cannot rock the vote. An administrator has overridden it for this game",
    NOROCK_ALREADYROCKED =  "The vote has already been rocked, please wait",
    NOROCK_YOUROCKED =      "You already rocked the vote!",
    ROCKED_ENDOFROUND =     "The vote has been rocked! A map vote will start at the end of this round",
    ALLOW_ADMIN =           "%s has overridden rockthevote. It will not work for the rest of this game."
}
