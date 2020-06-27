local replyTimeout = 100
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
local inputEvents = { -- TODO: how does the host recive this? how does it handle multiple clients?
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

-- converts appropriate rednet events into the protocol events above
-- returns the converted event or the original event if it wasn't convertable. An unknown rednet event will get forwarded as expected
local function translateEvent(...)
    local event = table.pack(...)
    if event[1] == "rednet_message" then
        local sender, message, protocol = event[2], event[3], event[4]
        if (protocol and protocol == protocolName or true) and type(message) == "table" then
            return message.type, message
        else
            return table.unpack(event)
        end
    else
        return table.unpack(event)
    end
end

local function eventTranslatorDeamon()
    while true do
        local event = table.pack(translateEvent(os.pullEvent("rednet")))
        if event ~= "rednet" then
            os.queueEvent(table.unpack(event))
        end
    end
end

-- provides methods for sending return values and errors to the host's terminal proxy
local function newTerminalResponder(hostId)
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
    local function sendCall(method, ...)
        rednet.send(clientId, {type = protocolEvents.terminalCall, method = method, args = table.pack(...) }, protocolName)
        while true do
            local senderId, message = rednet.receive(protocolName, replyTimeout) -- TODO: put into translateEvent
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

local function connectToRemoteTerminalHost(hostId, parentTerminal)
    local terminalResponder = newTerminalResponder(hostId)    
    rednet.send(hostId, {type = protocolEvents.connectionRequest}, protocolName)
    repeat
        local recievedId, message = rednet.receive(protocolName, nil)
    until recievedId == hostId and message and message.type == protocolEvents.connectionResponce and message.accepted

    while true do
        local event, terminalEventArg = translateEvent(os.pullEvent())
        if event == protocolEvents.terminalCall then
            local returnValues = table.pack(pcall(parentTerminal[terminalEventArg.method], table.unpack(terminalEventArg.args)))
            local ok = table.remove(returnValues,1)
            returnValues.n = returnValues.n -1
            if ok then
                terminalResponder.returnCall(terminalEventArg.callId, table.unpack(returnValues))
            else
                terminalResponder.returnError(terminalEventArg.callId, table.unpack(returnValues))
            end
        elseif event == protocolEvents.disconnection then
            return
        end
    end
end
    
local function remoteTerminalDeamon(startupProgram)
    while true do
        local clientId
        repeat
            local message
            clientId, message = rednet.receive(protocolName, nil)
        until message and message.type == protocolEvents.connectionRequest

        rednet.send(clientId, {type = protocolEvents.connectionResponce, accepted = true}, protocolName)
        local remoteTerminal = newRemoteTerminalProxy(clientId)
        remoteTerminal.write("hello world from remote\n")
        rednet.send(clientId, {type = protocolEvents.disconnection}, protocolName)
    end
end

return {
    protocolName = protocolName,
    protocolEvents = protocolEvents,
    translateEvent = translateEvent,
    eventTranslatorDeamon = eventTranslatorDeamon,
    newTerminalResponder = newTerminalResponder,
    connectToRemoteTerminalHost = connectToRemoteTerminalHost,
    newRemoteTerminalProxy = newRemoteTerminalProxy,
    remoteTerminalDeamon = remoteTerminalDeamon,

}