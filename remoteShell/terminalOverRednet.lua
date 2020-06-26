local replyTimeout = 100
local protocolName = "Lupus590:terminalOverRednet"
local events = { terminalCall = "terminal_call", terminalResponce = "terminal_responce"}

local function newTerminalSender(receiverId)

    local function sendCall(method, ...)
        local callId = string.format("%08x", math.random(1, 2147483647))
        rednet.send(receiverId, {type = events.terminalCall, callId = callId, method = method, args = table.pack(...) }, protocolName)
        while true do
            local senderId, message table.pack(rednet.receive(protocolName, replyTimeout))
            if senderId == receiverId and type(message) == "table" and message.callId == callId and message.type == events.terminalResponce then
                return message.returnValues
            end
        end
    end

    return {
        sendCall = sendCall,
    }
end

local function newTerminalResponder(senderID)
    local function returnCall(callId, ...)
        rednet.send(senderID, {type = events.terminalResponce, callId = callId, returnValues = table.pack(...) }, protocolName)
    end

    return {
        returnCall = returnCall,
    }
end

local function translateEvent(...)
    local event = table.pack(...)
    if event[1] == "rednet" and event[3] == protocolName and type(event[2]) == "table" then
        return event[2].type, event[2]
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

return {
    protocolName = protocolName,
    events = events,
    newTerminalSender = newTerminalSender,
    newTerminalResponder = newTerminalResponder,
    translateEvent = translateEvent,
    eventTranslatorDeamon = eventTranslatorDeamon,
    overWritePullEvent = overWritePullEvent,
}