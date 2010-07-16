module("config_teambalance", package.seeall)

--- If true, this will enforce team fairness. Players will not be able to join
 -- a team if it would imbalance the team player counts. If false, the player
 -- balancing still takes place, but players can still join other teams to
 -- unbalance the game until the next check is performed. It is suggested this
 -- be set to true.
ENFORCEBALANCE = true

--- When team balancing must take place, this will be used to determine who
 -- should get moved to the disadvantaged team. The available settings are
 -- as follows:
 --   "MAXKD" - The player with the highest kill-death ratio
 --   "LOWKD" - The player with the lowest kill-death ratio 
 --   "LOWTIME" - The player with the lowest amount of time spent on the server
 --   "RANDOM" - A player is randomly chosen
 -- The suggested value is random. Be aware that players may go back to their
 -- team again, though, which may result in players continually breaking the
 -- balance. Use ENFORCEBALANCE to prevent this.
PLAYERBALANCEMODE = "RANDOM"

--- This is the number of players that the teams must differ by in order to
 -- for a player or players to be automatically switched. It only makes sense 
 -- to set this to 2 or above (e.g. a setting of 2 would force a player 
 -- balance for 2v4, since one team has 2 more players than the other).
UNBALANCEDADVANTAGE = 2

--- After every round, the teams are checked to see if they are balanced. If
 -- not, they will be made balanced. This is the maximum number of players to
 -- balance for each check. For example, if you suddenly end up with a 1v1v6 game
 -- and this is set to 2, then the next round will be 2v2v4, and then next would
 -- be 2v3v3 (assuming nobody tries to correct the team balance themselves).
 -- Leaving this set to a high value is suggested, so that teams will always
 -- be balanced properly.
MAXBALANCEMOVE = 3
