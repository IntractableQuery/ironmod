module("config_serveroperation", package.seeall) -- DO NOT REMOVE THIS LINE 

-- The following controls what access level a person must have before they can
-- modify the cvar. If a cvar is not listed here, then DEFAULT_CVAR_ACCESS level
-- will be required.
CVAR_ACCESSLEVELS = {
    -- Low-level cvars  
    elim                            = 100, 
    fraglimit                       = 100,
    timelimit                       = 100,
    ffire                           = 100,
    grenadeffire                    = 100,
    chasecamonly                    = 100,
    ctfmode                         = 100,
    autojoin                        = 100,
    sv_gravity                      = 100,
    -- Mid-level cvars  
    tripping                        = 200,
    password                        = 200,
    idle                            = 200,
    SmokeGrens                      = 200,
    PaintGrens                      = 200, 
    flagcapendsround                = 200, 
    gren_explodeonimpact            = 200,
    match                           = 200,         
    deadtalk                        = 200,    
    -- High-level cvars      
    rot_type                        = 300,
    maxclients                      = 300,   
    real_ball_flight                = 300,
    ball_speed                      = 300,
    sv_maxvelocity                  = 300, 
    ball_addplayerspeed             = 300,
    ball_life                       = 300, 
    slowballsbounce                 = 300,
    bouncy                          = 300,
    gren_addplayerspeed             = 300,
    pbgren_bursts                   = 300,
    pbgren_ballsperburst            = 300,
    waterfriction                   = 300,
    bounceback                      = 300,
    item_addplayerspeed             = 300,
    item_reducedropped              = 300,
    instant_spawn                   = 300,
    grensounds                      = 300,
    pbgren_smoketrail               = 300,
    cursing                         = 300,
    punishedpoints                  = 300,
    g_autorecord                    = 300,
    -- Server ownership cvars   
    motdfile                        = 400,
    rot_file                        = 400,
    sl_logging                      = 400,
    port                            = 400,
    deathmatch                      = 400,
    dedicated                       = 400,
    allow_download                  = 400,
    maxrate                         = 400,
    allow_download_players          = 400,
    cmdfloodprotect                 = 400,
    floodprotect                    = 400,
    numpasses                       = 400,
    instant_item_spawn              = 400,
    filterban                       = 400,
    maxentities                     = 400,
    log_ip                          = 400,
    sv_login                        = 400    
}

-- This is the default access level used for changing cvars. The cvars in
-- CVAR_ACCESSLEVELS are first evaluated, and then this will be used if
-- it was not there. It is HIGHLY suggested this be set to 400 above, since
-- some cvars that have been left out in CVAR_ACCESSLEVELS can be used to
-- gain undesired access to the server (such as using the oppass# cvars or
-- rcon-related cvars). By setting it to 400, you ensure that only trusted 
-- people can use these commands.
DEFAULT_CVAR_ACCESS = 400

-- If true, changes to cvars will be reported to all the players in the game,
-- including the new value for the cvar. If false, changes take place
-- silently. There are some other cvars below that control exactly when
-- this will take place and how much information other people see.
SHOW_CVAR_CHANGED = true

-- This is the maximum cvar access level required in order to show the command
-- being set, assuming SHOW_CVAR_CHANGED is already true. If SHOW_CVAR_CHANGED 
-- is false, this does nothing. It is suggested this be set to the same
-- or lower value as DEFAULT_CVAR_ACCESS (usually 400) so that people cannot 
-- see you if you try to use "oppass#" or other highly important server
-- cvars. If SHOW_CVAR_CHANGED is false, this does nothing.
SHOW_CVAR_MAXLEVEL = 400

-- This is a list of cvars to NEVER show the value of, although players will
-- still be told about them being changed if SHOW_CVAR_CHANGED is true. If
-- SHOW_CVAR_CHANGED is false, this does nothing. Note that it is
-- assumed that you'll set SHOW_CVAR_MAXLEVEL to a suitable level so that
-- people can never even see you trying to set very sensitive cvars
-- like "oppass#" and those that are rcon-related.
SHOW_CVAR_EXEMPT = { "password" }
