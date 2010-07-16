-- This script exposes an error handling function used by ironmod when making
-- Lua functions calls. It dumps a stack trace and then exits ironmod. 
-- This is mostly to catch errors during the startup of ironmod.
-- Note that more fine-grain error handling, such as that
-- for plugins, is implemented elsewhere and is not related to this.
-- This should be the very first script loaded.

local stdprint = print -- core.lua is going to change print

function ironmod_errorhandler(errmsg)
    stdprint("========================== Lua Error ==========================")
    stdprint(debug.traceback(errmsg, 2));
    stdprint("===================== ironmod_errorhandler ====================")
    os.exit(1)
end

