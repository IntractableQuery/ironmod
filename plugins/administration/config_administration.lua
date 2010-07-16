module("config_administration")

--- If true, local logging will be enabled. The log file records all commands
-- issued by players.
LOG_ENABLED = true

--- Sets the minimum level required for a command's use to be logged to the
-- log file. Setting this to 1 is suggested, since it will keep regular level
-- 0 commands out of the log file, which you typically don't care about. This
-- allows you to effectively log administrator commands.
LOG_MINLEVEL = 1

--- Sets the log file to use. The log is stored in the plugin directory here.
LOG_FILE = "commands.log"

--- This is a prefix that can be used for using commands in the
-- game using chat. For example, if you set this to "!" and have a command
-- called "map", you can use it simply by saying "!map" in chat. You should
-- do your best to leave this as it is.
COMMANDPREFIX = "!"

--- This is used to identify what type of user a person is just by looking at
-- their access level. Please don't modify it without a compelling reason.
-- Do not use access levels over 500.
ACCESSNAMES = {
    {start=0,   ending=0,   name="regular user"},
    {start=1,   ending=99,  name="VIP user"},
    {start=100, ending=199, name="junior administrator"},
    {start=200, ending=299, name="regular administrator"},
    {start=300, ending=399, name="senior administrator"},
    {start=400, ending=499, name="server operator"},
    {start=500, ending=500, name="server owner"}
}

--- The filename to use for user storage.
USERCONFIGFILE = "users.cfg"

--- This is the access level required to change your own settings using "set".
-- It is suggested that you leave it as it is, since users can modify their own
-- access level using this, and should be highly trusted.
SELFSETLEVEL = 400

--- This is the minimum access level required for a user to be exempt from
-- temporary bans. Be aware that a temporary ban can still be issued against
-- players who are only authenticated by being in the server (ie: they must log
-- in or be recognized by their global login ID). This is mostly here to prevent
-- other plugins from trying perform real-time tempbans on administrators while
-- they are in the game.
-- You should make sure that the "tempban" command can only be used by trusted
-- administrators, as they *can* ban you and other higher-level admins after you
-- leave the game. 
-- The suggested level for this is 200, which allows administrators to tempban
-- junior administrators and below, while preventing them from banning other
-- regular administrators or higher who are currently in the game.
TEMPBANEXEMPTLEVEL=200
