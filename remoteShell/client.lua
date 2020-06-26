local terminalOverRednet = require("remoteShell.terminalOverRednet")
--terminalOverRednet.overWritePullEvent()

local function newClient()

    local function connectRemoteTerminal(hostName, parentTerminal)        
        local hostId = rednet.lookup(terminalOverRednet.protocolName, hostName)
        local terminalResponder = terminalOverRednet.newTerminalResponder(hostId)
        while true do
            local event, terminalEventArg, protocol = os.pullEvent()
            
            
            event, terminalEventArg = terminalOverRednet.translateEvent(event, terminalEventArg, protocol)
            if event == terminalOverRednet.events.terminalCall then
                local returnValues = table.pack(pcall(parentTerminal[terminalEventArg.method], table.unpack(terminalEventArg.args)))
                local ok = table.remove(returnValues,1)
                returnValues.n = returnValues.n -1
                if ok then
                    terminalResponder.returnCall(terminalEventArg.callId, table.unpack(returnValues))
                else
                    terminalResponder.returnError(terminalEventArg.callId, table.unpack(returnValues))
                end
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
