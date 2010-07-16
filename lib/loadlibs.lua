-- This script is invoked by ironmod to configure any libraries for use
-- that we will need. This typically involves putting .lua or .so/.dll
-- modules/libraries in the package.path and/or package.cpath strings.

-- BEGIN STANDARD IRONMOD LIBS (please do not remove any of these)
    -- LuaSocket (TCP/UDP/DNS functionality, and a bit more).
    -- http://www.tecgraf.puc-rio.br/~diego/professional/luasocket/
    package.cpath = package.cpath .. ";" .. util.GetIronModPath() .. "lib/luasocket/?.so"
    package.path = package.path .. ";" .. util.GetIronModPath() .. "lib/luasocket/?.lua"
    -- ztact misc. lua utilities (includes async LuaSocket functionality using 
    -- coroutines that yield during socket blocking).
    -- I have removed some stuff that won't be used, like the posix interface.
    -- http://ztact.com/software/
    package.path = package.path .. ";" .. util.GetIronModPath() .. "lib/ztact/?.lua"
    -- LuaMatrix/SimpleMatrix (multidimensional matrix handling).
    -- http://lua-users.org/wiki/SimpleMatrix
    package.path = package.path .. ";" .. util.GetIronModPath() .. "lib/matrix/?.lua"
    -- My SNTP implementation
    package.path = package.path .. ";" .. util.GetIronModPath() .. "lib/luasntp/?.lua"
-- END STANDARD IRONMOD LIBS
