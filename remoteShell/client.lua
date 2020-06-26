local terminalOverRednet = require("remoteShell.terminalOverRednet")
terminalOverRednet.overWritePullEvent()

local function newClient()

    local function connectRemoteTerminal(hostName, parentTerminal)        
        local hostId = rednet.lookup(terminalOverRednet.protocolName, hostName)
        local terminalResponder = terminalOverRednet.newTerminalResponder(hostId)

        while true do
            local _, terminalEventArg = os.pullEvent(terminalOverRednet.events.terminalCall)
            local returnValues = table.pack(pcall(parentTerminal[terminalEventArg.method], table.unpack(terminalEventArg.args)))
            local ok = table.remove(returnValues)
            if ok then
                terminalResponder.returnCall(terminalEventArg.callId, table.unpack(returnValues))
            end
        end
    end

    return {
        connectRemoteTerminal = connectRemoteTerminal,
    }
end

return {
    newClient = newClient,
}
