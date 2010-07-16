-- LuaSNTP, a Simple Network Time Protocol implementation based on RFC2030.
-- Don't count on this for insane precision, I only created it with it being
-- precise down to a second or so in mind. os.time() is a major limiting factor.
--
-- Be aware that this will seed math's random number generator when it first
-- loads.
--
-- Depends on LuaSocket.

module("luasntp", package.seeall)

local socket = require("socket")
local ZEROBYTE = string.char(0)
math.randomseed(os.time())

--- This convenience function wraps QueryTime() to provide you with a return
 -- function that you can call to get the current time at the SNTP server
 -- (that is, the "correct time"). This only queries the server once.
 -- Note that the returned function can also take an optional timestamp, which
 -- results in behavior similar to that of GetServerTime() (that is, the local
 -- timestamp in seconds you provide will be converted to the "correct time").
 -- 
 -- @param host the hostname (or IP address) of the remote SNTP server
 -- @return [a function that returns the current server time as a unix timestamp] or [nil and an error message if the server query failed]
function GetCorrectTimeFunction(host)
    local offset,errmsg = QueryTime(host)
    if(offset == nil) then
        return nil,errmsg
    else
        -- Success!
        local correctTimeFunc = function(timestamp)
            if(timestamp == nil) then timestamp = GetUnixTime() end
            return GetServerTime(timestamp, offset)
        end
        return correctTimeFunc
    end
end

--- Communicates using SNTP with the remote host to obtain a clock offset
 -- relative to the SNTP server. You can use GetServerTime() to get the time
 -- at the server using your own time and the offset provided here. 
 --
 -- @param host the hostname (or IP address) of the remote SNTP server
 -- @return the clock offset (a value you can add to local time to get server time) or if there is a failure, nil will be returned along with an error message
function QueryTime(host)
    local udpSocket = socket.udp()
    udpSocket:setpeername(host, 123) -- 123 is standard SNTP port
    local packet,transmitTime = BuildQueryPacket()
        
    local result,errmsg = udpSocket:send(packet)
    if(result == nil) then
        -- Packet send failure
        return nil,"Data send failure: " .. errmsg
    end
    
    -- Get the reply, mark the time, and parse it
    local reply,errmsg = udpSocket:receive(48)
    if(reply == nil) then
        -- Receive failure
        return nil, "Data receive failure: " .. errmsg
    end
    local destinationTimestamp = Unix2SNTP(GetUnixTime())
    local t = ParseReplyPacket(reply)
    
    -- If this server is for any reason not servicing people, "all fields are 0"
    if(t.receiveTimestamp == 0 and t.transmitTimestamp == 0) then
        return nil, "SNTP server responded with zeroed fields, it is probably not offering time synchronization at the moment"
    end
    
    -- Note: round trip delay is practically useless since most low-latency connections will do this in under a second :(
    local roundTripDelay = (destinationTimestamp - t.originateTimestamp) - (t.transmitTimestamp - t.receiveTimestamp)
    -- Again, clock offset is only accurate to within a second or so...
    local localClockOffset = ((t.receiveTimestamp - t.originateTimestamp) + (t.transmitTimestamp - destinationTimestamp)) / 2;
    
    return localClockOffset + (roundTripDelay / 2) -- I need to verify this is correct, although close inspection makes it seem so
end

--- Builds an SNTP request packet containing the current time. This is meant for
 -- immediate dispatch to the SNTP server. 
 -- This packet is quite literally passed between us and the SNTP server 
 -- in its entirety, so we're both writing stuff into it.
 -- @return the raw packet as a string and the timestamp used in the transmit field
function BuildQueryPacket()
    -- The "header mask" is a term I coined for the first 8 bits of the
    -- request, which contains:
    -- 2 bit Leap Indicator (server fills)
    -- 3 bit Version Number (we fill, version 3)
    -- 3 bit Mode (we fill, mode 3/client)
    local headerMask = BitsToByte({0, 0,
                                   0, 1, 1,
                                   0, 1, 1})
                                   
    -- zero out the 8-bit values following
    local stratum = ZEROBYTE  
    local pollinterval = ZEROBYTE
    local precision = ZEROBYTE
    
    -- zero root delay/dispersion/ref identifier
    local rootDelay = string.rep(ZEROBYTE, 4)    
    local rootDispersion = string.rep(ZEROBYTE, 4) 
    local referenceIdentifier = string.rep(ZEROBYTE, 4) 
    
    -- zero our timestamps that are going to get filled later
    local referenceTimestamp = string.rep(ZEROBYTE, 8) -- we've written 16 bytes up to this point
    local originateTimestamp = string.rep(ZEROBYTE, 8) 
    local receiveTimestamp = string.rep(ZEROBYTE, 8) 
    
    -- Write in our own timestamp for this moment in time
    local transmitTime = Unix2SNTP(GetUnixTime())
    local transmitTimestamp = BuildTimestamp(transmitTime)
    
    -- Build the packet
    return headerMask .. stratum .. pollinterval .. precision .. rootDelay ..
           rootDispersion .. referenceIdentifier .. referenceTimestamp ..
           originateTimestamp .. receiveTimestamp .. transmitTimestamp, transmitTime
end

--- Parses the packet we get back from the SNTP server.
 --
 -- @param packet the raw packet
 -- @return a table with some of the fields we originally encoded in BuildQueryPacket()
function ParseReplyPacket(packet)
    local t = {}
    t.referenceTimestamp = DecodeTimestamp(packet:sub(16+1, 16+7+1))
    t.originateTimestamp = DecodeTimestamp(packet:sub(24+1, 24+7+1))
    t.receiveTimestamp   = DecodeTimestamp(packet:sub(32+1, 32+7+1))
    t.transmitTimestamp  = DecodeTimestamp(packet:sub(40+1, 40+7+1))
    return t
end

--- Builds a big-endian raw byte from bits. This serves as an excellent way
 -- for me to avoid thinking in hex.
 --
 -- @param bits an array of 1's and 0's
function BitsToByte(bits)
    assert(bits ~= nil, "bits cannot be nil")
    assert(#bits == 8, "there must be only 8 bits")
    local byte = 0
    for i=7,0,-1 do
        local bitindex = 8-i
        byte = byte + math.pow(2, i) * bits[bitindex]
    end
    return string.char(byte)
end

--- Transforms the given number into a raw 64-bit (big-endian) timestamp. The 
 -- double needs to be in the NTSP timestamp format (time in seconds since 
 -- January 1, 1900), and is expressed in seconds (the fractional portion
 -- allows for precision down to about 0.2 nanoseconds).
 -- 
 -- @param timestamp the time to encode
function BuildTimestamp(timestamp)
    local bytes = ""
    
    for i=0,6 do -- only do the first 7 bytes
    
        local div = math.pow(2, (3-i)*8)
        local byte = math.floor(timestamp / div)
        bytes = bytes .. string.char(byte)
        timestamp = timestamp - byte * div
    end
    -- the RFC suggests we use random data for the lower-order bits... here's byte 8
    bytes = bytes .. string.char(math.random(0,255))
    
    return bytes
end

--- Transforms the given raw 64-bit timestamp into a number value.
 -- 
 -- @param bytes the raw bytes to decode
function DecodeTimestamp(bytes)
    local timestamp = 0
    for i=0,7 do
        local byte = string.byte(bytes:sub(i+1,i+1))
        timestamp = timestamp + (byte * math.pow(2, (3-i)*8))
    end
    return timestamp
end

--- Returns the current (local) Unix time. This relies on os.time() actually returning
 -- unix time!
 --
 -- @return unix time, expressed with seconds precision
function GetUnixTime()
    return os.time()
end

--- Converts Unix time to SNTP time.
--
-- @param unixtime a unix timestamp
-- @return the time as a SNTP timestamp
function Unix2SNTP(unixtime)
    return unixtime + 2208988800
end

--- Converts SNTP time to Unix time.
--
-- @param sntptime a SNTP timestamp
-- @return the time as a Unix timestamp
function SNTP2Unix(sntptime)
    return sntptime - 2208988800
end

--- Given a clock offset for a remote NTSP server, this converts local seconds 
 -- into seconds at the NTSP server (it doesn't matter if it is a NTSP timestamp
 -- or unix timestamp, since both express time in seconds).
 --
 -- @param timestamp a timestamp in seconds
 -- @param offset the time offset relative to the server (you get this by calling QueryTime())
 -- @return the time rounded to seconds (an integer value)
function GetServerTime(timestamp, offset)
    return math.floor((timestamp + offset) + 0.5)
end
