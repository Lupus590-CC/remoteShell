local replyTimeout = 30
local protocolName = "Lupus590:terminalOverRednet"
local protocolEvents = {
    terminalCall = "terminal_call",
    terminalResponce = "terminal_responce",
    terminalError = "terminal_error",
    inputEvent = "input_event",
    connectionRequest = "connection_request",
    connectionResponce = "connection_responce",
    disconnection = "disconnection"
}
local inputEvents = {
    char = true,
    key = true,
    key_up = true,
    mouse_click = true,
    mouse_drag = true,
    mouse_scroll = true,
    mouse_up = true,
    paste = true,
    term_resize = true,
}

local eventTranslatiorIsRunning = false

local function eventTranslatorDeamon() -- seperate coroutine may be a cause of slowdown
    eventTranslatiorIsRunning = true
    
    while true do
        local sender, message, protocol = rednet.receive(protocolName, nil)
        if type(message) == "table" then
            os.queueEvent(message.type, sender, message)
        end
    end
end

-- provides methods for sending return values and errors to the host's terminal proxy
local function newTerminalResponder(hostId)
    if not eventTranslatiorIsRunning then error("event translator is not running") end
    local function returnCall(callId, ...)
        rednet.send(hostId, {type = protocolEvents.terminalResponce, callId = callId, returnValues = table.pack(...) }, protocolName)
    end

    local function returnError(callId, ...)
        rednet.send(hostId, {type = protocolEvents.terminalError, callId = callId, returnValues = table.pack(...) }, protocolName)
    end

    return {
        returnCall = returnCall,
        returnError = returnError,
    }
end

-- creates a fake terminal object which forwards calls to the remote screen
local function newRemoteTerminalProxy(clientId)
    if not eventTranslatiorIsRunning then error("event translator is not running") end
    local function sendCall(method, ...)
        rednet.send(clientId, {type = protocolEvents.terminalCall, method = method, args = table.pack(...) }, protocolName)
        while true do

            local senderId, message = rednet.receive(protocolName, replyTimeout)
            if senderId == clientId and type(message) == "table" then
                if  message.type == protocolEvents.terminalResponce then
                    return table.unpack(message.returnValues)
                elseif message.type == protocolEvents.terminalError then
                    error("\nRemote Code:\n  "..table.concat(message.returnValues, "  \n").."\nEnd of Remote Code", 2)
                end
            elseif senderId == nil then
                error("Timed out awaiting responce",0)
            end
        end
    end
    local fakeTermMeta = {
        __index = function(_, key)
            return function(...)
                return sendCall(key, ...)
            end
        end
    }

    return setmetatable({}, fakeTermMeta)
end

-- simple net shell like client
local function connectToRemoteTerminal(hostId, parentTerminal)
    if not eventTranslatiorIsRunning then error("event translator is not running") end
    local terminalResponder = newTerminalResponder(hostId)    
    rednet.send(hostId, {type = protocolEvents.connectionRequest}, protocolName)
    repeat
        local _, recievedId, message = os.pullEvent(protocolEvents.connectionResponce)
    until recievedId == hostId and message and message.type == protocolEvents.connectionResponce and message.accepted

    while true do
        local event = table.pack(os.pullEvent())
        if event[1] == protocolEvents.terminalCall and event[2] == hostId then
            local terminalEventArg = event[3]
            local returnValues = table.pack(pcall(parentTerminal[terminalEventArg.method], table.unpack(terminalEventArg.args)))
            local ok = table.remove(returnValues,1)
            returnValues.n = returnValues.n -1
            if ok then
                terminalResponder.returnCall(terminalEventArg.callId, table.unpack(returnValues))
            else
                terminalResponder.returnError(terminalEventArg.callId, table.unpack(returnValues))
            end
        elseif event[1] == protocolEvents.disconnection then
            error("Disconnected by remote host",0)
        elseif inputEvents[event[1]] then
            rednet.send(hostId, {type = protocolEvents.inputEvent, eventData = event}, protocolName)
        end
    end
end

-- simple net shell like server
local function remoteTerminalDeamon(startupProgram)
    if not eventTranslatiorIsRunning then error("event translator is not running") end
    while true do
        local _, clientId = os.pullEvent(protocolEvents.connectionRequest)
        rednet.send(clientId, {type = protocolEvents.connectionResponce, accepted = true}, protocolName)
        local remoteTerminal = newRemoteTerminalProxy(clientId)
        local oldTerm = term.redirect(remoteTerminal)

        local function shellRun()
            os.run({shell = shell}, "rom/programs/shell.lua", startupProgram)
        end

        local function convertEvents()
            while true do
                local sender, message, protocol = rednet.receive(protocolName, nil)
                if type(message) == "table" and message.type == protocolEvents.inputEvent and sender == clientId then
                    os.queueEvent(table.unpack(message.eventData))
                end
            end
        end

        parallel.waitForAny(convertEvents, shellRun)

        rednet.send(clientId, {type = protocolEvents.disconnection}, protocolName)
        term.redirect(oldTerm)
        return
    end
end

return {
    protocolName = protocolName,
    protocolEvents = protocolEvents,
    inputEvents = inputEvents,
    eventTranslatorDeamon = eventTranslatorDeamon,
    newTerminalResponder = newTerminalResponder,
    connectToRemoteTerminal = connectToRemoteTerminal,
    newRemoteTerminalProxy = newRemoteTerminalProxy,
    remoteTerminalDeamon = remoteTerminalDeamon,

}