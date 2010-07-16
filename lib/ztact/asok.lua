

-- public domain 20080404 lua@ztact.com


require 'coroutine'
require 'math'
require 'table'

require 'socket'
require 'ztact'


local coroutine, string = coroutine, string
local ztact = ztact


local assert, ipairs, next, pairs, pcall, setmetatable, type, unpack =
      assert, ipairs, next, pairs, pcall, setmetatable, type, unpack

local append  = table.insert
local floor   = math.floor
local gettime = socket.gettime
local max     = math.max
local remove  = table.remove
local select  = socket.select
local sleep   = socket.sleep


require 'debug'  local debug = debug
-- local getfenv, print = getfenv, print


local asok = _G    ------------------------------------------------ module asok
module ((...) or 'asok')
asok = asok[(...) or 'asok']

-- xarr is an array passed to socket.select
-- xset is associative sok->co, where co is currently waiting on sok
-- xabn is associative sok->co, where co just stoppend waiting on sok
-- xque is associative sok->{}, where {} is a stack of co's waiting for a
--                              chance to wait on sok

local rarr, rset, rabn, rque = {}, {}, {}, {}
local warr, wset, wabn, wque = {}, {}, {}, {}

local zset, previously, soonest = {}, gettime ()    -- sleeper management

local wrap, sok2aux = {}, setmetatable ( {}, { __mode = 'k' } )


local function lookup (sok)    -- - - - - - - - - - - - - - - - - - - -  lookup
  -- if not sok then  print (debug.traceback ())  end
  local aux = sok2aux[sok] or sok2aux[sok.sok]
  if not aux then
    aux = {}
    sok2aux[sok.sok or sok] = aux
    end
  -- print ('lookup', aux, sok.sok or sok)
  return aux, sok.sok or sok
  end


local function rebuild (xarr, xset, xabn, xque)    -- - - - - - - - - - rebuild

  for sok in pairs (xabn) do    -- for sok in abandoned sockets
    if xque[sok] then    -- if queued coroutine wants sok
      xset[sok] = remove (xque[sok])
      xabn[sok] = nil    -- sok is no longer abandoned
      if not next (xque[sok]) then  xque[sok] = nil  end
      end  end

  if next (xabn) then    -- if there are still abandoned sockets
    for i   in pairs (xarr) do  xarr[i] = nil       end    -- clear   xarr
    for sok in pairs (xset) do  append (xarr, sok)  end    -- rebuild xarr
    for key in pairs (xabn) do  xabn[key] = nil     end    -- clear   xabn
    end  end


local resume_map = setmetatable ( {}, { __mode='kv' } )


local function yield (sok, xarr, xset, xabn, xque)    -- - - - - - - - -  yield

  local aux = lookup (sok)
  local co = coroutine.running ()
  -- print ('yield0', co, resume_map[co] or co)
  co = resume_map[co] or co    -- are we inside asok.xpcall()?

  if xset[sok] then    -- if collision then queue coroutine for future select
    xque[sok] = xque[sok] or {}
    append (xque[sok], co)
  else
    xset[sok] = co                        -- assign sok to co
    if xabn[sok] then  xabn[sok] = nil    -- if abandoned then reclaim
    else  append (xarr, sok)  end         -- else append (new) sok to xarr
    end

  coroutine.yield ()
  xset[sok] = nil     -- abandon sok
  xabn[sok] = true    -- abandon sok
  end


local function yield_read (sok)    -- - - - - - - - - - - - - - - -  yield_read
  return yield (sok, rarr, rset, rabn, rque)  end


local function yield_write (sok)    -- - - - - - - - - - - - - -- - yield_write
  return yield (sok, warr, wset, wabn, wque)  end


function asok.__index (tbl, key)    -- - - - - - - - - - - - - - - - -  __index

  local val = asok[key] or wrap[key]
  if val or key == 'sok' then  return val  end

  if tbl.sok and type (tbl.sok[key]) == 'function' then
    wrap[key] = function (self, ...)  return self.sok[key] (self.sok, ...)  end
    return wrap[key]
    end  end


function asok:accept ()    -- - - - - - - - - - - - - - - - - - - - - -  accept
  local aux, sok = lookup (self)
  local timeout
  if aux.timeout then  timeout = gettime () + aux.timeout  end  
  while true do
    local client, err = sok:accept ()
    if     client            then  return client
    elseif err ~= 'timeout'  then  return nil, err
    elseif timeout and gettime () > timeout then  return nil, 'timeout'  end
    yield_read (sok)
    end  end


function asok:connect (address, port)    -- - - - - - - - - - - - - - - connect
  local aux, sok = lookup (self)
  local s, err = sok:connect (address, port)
  if not s and err == 'timeout' then
    yield_write (sok)
    return true    -- todo: fix this small kludge?  will it ever matter?
    end
  return nil, err
  end


function asok.xpcall (f, err, ...)    -- - - - - - - - - - - - - - - - - xpcall

  local co1 = coroutine.create (f)
  resume_map[co1] = resume_map[coroutine.running ()] or coroutine.running ()

  local result = { coroutine.resume (co1, ...) }
  while true do
    if err and not result[1] then  return false, err (unpack (result, 2))  end
    if coroutine.status (co1) == 'dead' then  return unpack (result)  end
    result = { coroutine.resume (co1, coroutine.yield (unpack (result, 2))) }
    end  end


function asok:receive (...)    -- - - - - - - - - - - - - - - - - - - - receive

  local aux, sok = lookup (self)
  local tcp = not sok.sendto    -- is sok udp or tcp?
  local pattern, prefix = ...
  pattern = pattern or '*l'

  -- receive or fail
  local timeout = aux.timeout and gettime () + aux.timeout
  local data
  while not data do

    if tcp then data, err, prefix = sok:receive (pattern, prefix)
    else        data, err, prefix = sok:receive (...)  end

    if err and err ~= 'timeout' then  return data, err, prefix  end

    if err == 'timeout' then
      if timeout and gettime () >= timeout then
        return nil, 'timeout', prefix
      else  yield_read (sok)  end
      end  end

  data = data or prefix

  if aux.receive_cps then  asok.sleep (#data/aux.receive_cps)  end
  return data
  end


function asok.resume (co, ...)    -- - - - - - - - - - - - - - - - - - - resume
  local s, err = coroutine.resume (co, ...)
  if err then  print (debug.traceback (co, err))  sleep (10)  end
  return s, err
  end


local function send_tcp (aux, sok, data, i, j)    -- - - - - - - - - - send_tcp

  i = i or 1
  j = j or #data
  local cps = aux.send_cps

  local timeout = aux.timeout and gettime () + aux.timeout
  local last

  while i <= j do

    local k = j
    if cps then    -- throttle (i.e. sleep as needed)
      if j-i+1 < cps then  asok.sleep (j-i+1/cps)
      elseif cps < 1 then  asok.sleep (1/cps)      k = i
      else                 asok.sleep (1)          k = i+cps-1  end
      end

    while i <= k do

      local l, err, err_last = sok:send (data, i, k)
      last = err_last or l or last

      --print ('send', i, k, j, last, '----', l, err, err_last)

      i = last and last + 1 or i

      -- success!
      if last and last == j then  return last  end

      -- non-timeout error
      if err and err ~= 'timeout' then  return nil, err, last  end

      -- asok timeout
      if timeout and gettime () > timeout then
         return nil, 'timeout', last  end

      -- socket timeout
      if err == 'timeout' then  yield_write (sok)  end

      end  end  end


local function send_udp (aux, sok, datagram)    -- - - - - - - - - - - send_udp
  if aux.send_cps then  asok.sleep (#datagram/aux.send_cps)  end
  return sok:send (datagram)
  end


function asok:send (...)    -- - - - - - - - - - - - - - - - - - - - - - - send
  local aux, sok = lookup (self)
  if sok.sendto then  return send_udp (aux, sok, ...)
  else                return send_tcp (aux, sok, ...)  end
  end


function asok:settimeout (timeout)    -- - - - - - - - - - - - - - - settimeout
  lookup (self).timeout = timeout  return true  end


function asok.select (rset_aux, wset_aux, timeout)    -- - - - - - - - - select

  -- note: [rw]set_aux are currently ignored but may be used in the future

  while not timeout or timeout > 0 do

    local now = gettime ()  soonest = timeout and now + timeout

    if now < previously then for co,when in pairs (zset) do    -- time-warp!
      zset[co] = when - previously + now  end  end
    previously = now

    for co,when in pairs (zset) do    -- review sleepers
      if now >= when then  zset[co] = nil  asok.resume (co)
      elseif not soonest or when < soonest then  soonest = when  end
      end

    if next (rabn) then  rebuild (rarr, rset, rabn, rque)  end
    if next (wabn) then  rebuild (warr, wset, wabn, wque)  end

    soonest = soonest and max (0, soonest - gettime ())
    local r, w, err = select (rarr, warr, soonest)

    for i,sok in ipairs (r) do  asok.resume (rset[sok])  end
    for i,sok in ipairs (w) do  asok.resume (wset[sok])  end

    timeout = timeout and timeout - max (0, gettime () - now)
    end  end


function asok.sleep (seconds)    -- - - - - - - - - - - - - - - - - - - - sleep
  if seconds > 0 then
    seconds = gettime () + seconds
    if not soonest or seconds < soonest then  soonest = seconds  end
    zset[coroutine.running ()] = seconds
    coroutine.yield ()
    end  end


function asok:socks4_connect (ip, port)    -- - - - - - - - - -  socks4_connect

  local a, b = ztact.htons (port)
  local c, d, e, f = assert (string.match (ip, '^(%d+)%.(%d+)%.(%d+)%.(%d+)$'))
  local request = string.char (4, 1, a, b, c, d, e, f, 0)
  assert (asok.send (self, request))

  local expect  = string.char (0, 0x5a)
  local receive = assert (asok.receive (self, 8))
  return assert (string.find (receive, expect, 1, true))
  end


function asok:throttle_receive (cps)    -- - - - - - - - - - - throttle_receive
  lookup (self).receive_cps = cps  return true  end


function asok:throttle_send (cps)    -- - - - - - - - - - - - - - throttle_send
  lookup (self).send_cps = cps  return true  end


function asok.wrap (sok, timeout)    -- - - - - - - - - - - - - - - - - -  wrap
  assert (sok:settimeout (timeout or 0))
  return setmetatable ( { sok = sok }, asok )  end


return asok
