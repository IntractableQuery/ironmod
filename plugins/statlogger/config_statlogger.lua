module("config_statlogger", package.seeall) -- DO NOT REMOVE THIS LINE 

--- If true, local logging will be enabled and log sessions will be 
-- stored in /logs
ENABLE_LOCAL_LOG = true

--- If true, when the server first starts, a time synchronization will be 
-- performed on one of the SNTP servers listed in TIME_SERVERS. The purpose
-- of this is to include the correct unix time (with precision to about a 
-- second) in the log file. Without it, it is impossible to correctly
-- determine the time events happened in the log without knowing that the
-- game server's time has never changed (and this is never guaranteed).
-- It is *HIGHLY* suggested that you always leave this set to true. Remote
-- log repositories may rely on it in the future and statistics systems
-- may refuse logs that don't have synchronized time.
ENABLE_TIMESYNC = true 

--- This is a list of SNTP time servers to use. SNTP servers are used to obtain
-- the current time. Please don't add local LAN servers unless you really 
-- know what you're doing (if you desynch your LAN server, this is bad for
-- your logs). 
TIME_SERVERS = { "time-a.nist.gov", "time-b.nist.gov", "utcnist.colorado.edu",
                 "utcnist2.colorado.edu" }
