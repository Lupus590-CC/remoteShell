local terminalOverRednet = require("remoteShell.terminalOverRednet")

local function newServer(hostName)
    rednet.host(terminalOverRednet.protocolName, hostName)
    local function connectRemoteTerminal(receiverId)
        local remoteTerminal = terminalOverRednet.newTerminalSender(receiverId)
        local fakeTermMeta = {
            __index = function(_, key)
                return function(...)
                    return remoteTerminal.sendCall(key, ...)
                end
            end
        }
        local fakeTerm = setmetatable({}, fakeTermMeta)

        return fakeTerm
    end
    return {
        connectRemoteTerminal = connectRemoteTerminal,
    }
end

return {
    newServer = newServer,
}
