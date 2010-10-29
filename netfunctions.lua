-- mostly written by firsm

relay.net = {}

local net = relay.net
local sockets = {}
local states = {}

function net.RegisterSocket(name, sock)
    sockets[name] = sock
    states[name] = true
end

function net.SocketIsUp(name)
    return states[name]
end

function net.CloseSocket(name)
    local s = sockets[name]
    if s and s.tcp then
        s.tcp:Disconnect()
    end
    states[name] = nil
    sockets[name] = nil
end
    
function net.CloseAllSockets()
    for x, y in pairs(sockets) do
        net.CloseSocket(x)
    end
end

function net.ListSockets()
    if not (states == nil) then
        return states
    else
        return {}
    end
end


function net.make_client(port, host, cb_ConnectionMade, cb_ConnectionFailed, cb_LineReceived, cb_ConnectionLost, name)
    local c = {}
    local sock
    local t = Timer()
    
    if not tonumber(port) then
        cb_ConnectionFailed("Invalid port number")
        return
    end
    
    local function ConnectionMade(con, not_ok)
        if not_ok then
            if sock then sock.tcp:Disconnect() end
            cb_ConnectionFailed(not_ok..".")
        else
            net.RegisterSocket(name, con)
            cb_ConnectionMade("Now connected to "..host.." on port "..tostring(port))
        end
    end
    
    local function LineReceived(con, line)
        if line then
            cb_LineReceived(string.clean(line))
        end
    end
    
    local function ConnectionLost(con)
        net.CloseSocket(name)
        cb_ConnectionLost("Connection closed by foreign host")
    end
    
    if net.SocketIsUp(name) then
        cb_ConnectionFailed("Already connected")
    end
        

    sock = TCP.make_client(host, tonumber(port), ConnectionMade, LineReceived, ConnectionLost)
    -- start a timeout timer here
    local tcp = {}
    function c:Send(msg)
        sock.tcp:Send(msg.."\r\n")
        --print(msg)
    end 
    function c:Disconnect()
        cb_ConnectionLost("Connection closed (requested)")
        net.CloseSocket(name)
    end
    return c
end
