local replyTimeout = 100
local protocolName = "Lupus590:terminalOverRednet"
local events = {
    terminalCall = "terminal_call",
    terminalResponce = "terminal_responce",
    terminalError = "terminal_error",
    connectionRequest = "connection_request",
    connectionResonce = "connection_responce"
}

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

local oldPullEvent = os.pullEvent
local overWrotePullevent = false
local function overWritePullEvent()
    if not overWrotePullevent then
        os.pullEvent = function(filter)
            if filter and events[filter] then
                local event
                repeat
                    event = table.pack(translateEvent(oldPullEvent("rednet")))
                until filter == event[1]
                return table.unpack(event)
            end
            return translateEvent(oldPullEvent(filter))
        end
    end
    overWrotePullevent = true
end

local function newClient()
    local function connectRemoteTerminal(hostName, parentTerminal)        
        local hostId = rednet.lookup(protocolName, hostName)
        local function newTerminalResponder(senderID)
            local function returnCall(callId, ...)
                rednet.send(senderID, {type = events.terminalResponce, callId = callId, returnValues = table.pack(...) }, protocolName)
            end
        
            local function returnError(callId, ...)
                rednet.send(senderID, {type = events.terminalError, callId = callId, returnValues = table.pack(...) }, protocolName)
            end
        
            return {
                returnCall = returnCall,
                returnError = returnError,
            }
        end
        local terminalResponder = newTerminalResponder(hostId)
        while true do
            local event, terminalEventArg = translateEvent(os.pullEvent())
            if event == events.terminalCall then
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

local function newServer(hostName)
    rednet.host(protocolName, hostName)
    local function connectRemoteTerminal(receiverId)
        local function newTerminalSender(receiverId)

            local function sendCall(method, ...)
                local callId = 1 -- string.format("%08x", math.random(1, 2147483647)) -- TODO: change back
                rednet.send(receiverId, {type = events.terminalCall, callId = callId, method = method, args = table.pack(...) }, protocolName)
                while true do
                    local senderId, message = rednet.receive(protocolName, replyTimeout)
                    if senderId == receiverId and type(message) == "table" and message.callId == callId then
                        if  message.type == events.terminalResponce then
                            return table.unpack(message.returnValues)
                        elseif message.type == events.terminalError then
                            error("\nRemote Code:\n  "..table.concat(message.returnValues, "  \n").."\nEnd of Remote Code", 2)
                        end
                    elseif senderId == nil then
                        error("Timed out awaiting responce",0)
                    end
                end
            end
        
            return {
                sendCall = sendCall,
            }
        end
        local remoteTerminal = newTerminalSender(receiverId)
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
    protocolName = protocolName,
    events = events,
    translateEvent = translateEvent,
    eventTranslatorDeamon = eventTranslatorDeamon,
    overWritePullEvent = overWritePullEvent,
    newClient = newClient,
    newServer = newServer,

}