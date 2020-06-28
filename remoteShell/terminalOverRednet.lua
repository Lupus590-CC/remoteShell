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

local function eventTranslatorDeamon() -- seperate coroutine may be a cause of slowdown -- TODO: attempt to obsolete
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
                    return table.unpack(message.returnValues, 1, message.returnValues.n)
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
    rednet.send(hostId, {type = protocolEvents.connectionRequest}, protocolName) -- TODO: start a timer and resend the request if it times out
    repeat
        local _, recievedId, message = os.pullEvent(protocolEvents.connectionResponce) -- TODO: handle connection rejection
    until recievedId == hostId and message and message.type == protocolEvents.connectionResponce and message.accepted

    while true do
        local event = table.pack(os.pullEvent())
        if event[1] == protocolEvents.terminalCall and event[2] == hostId then
            local terminalEventArg = event[3]
            local returnValues = table.pack(pcall(parentTerminal[terminalEventArg.method], table.unpack(terminalEventArg.args, 1, terminalEventArg.args.n)))
            local ok = table.remove(returnValues,1)
            returnValues.n = returnValues.n -1
            if ok then
                terminalResponder.returnCall(terminalEventArg.callId, table.unpack(returnValues, 1, returnValues.n))
            else
                terminalResponder.returnError(terminalEventArg.callId, table.unpack(returnValues, 1, returnValues.n))
            end
        elseif event[1] == protocolEvents.disconnection then
            error("Disconnected by remote host",0)
        elseif inputEvents[event[1]] then
            rednet.send(hostId, {type = protocolEvents.inputEvent, eventData = event}, protocolName)
        end
    end
end

-- simple net shell like server
local function remoteTerminalHostDeamon(startupProgram)
    if not eventTranslatiorIsRunning then error("event translator is not running") end
    local remotesList = {}
    local originalTerm = term.current()

    local function clientConnectionAcceptor()
        while true do
            local _, clientId = os.pullEvent(protocolEvents.connectionRequest)

            local function shellRun()
                local shellToUse
                if fs.exists(".mbs/bin/shell.lua") then shellToUse = ".mbs/bin/shell.lua"
                elseif fs.exists("rom/.mbs/bin/shell.lua") then shellToUse = "rom/.mbs/bin/shell.lua"
                else shellToUse = "rom/programs/shell.lua" end

                shellToUse = "rom/programs/shell.lua"
                
                --local ok, err = pcall(os.run, {shell = shell}, shellToUse) --, shell.resolve(startupProgram)) -- TODO: restore

                print("hello")
                os.pullEvent()
                print("hello2")
                --error()
            end

            if not remotesList[clientId] then
                local t = newRemoteTerminalProxy(clientId)
                local c = coroutine.create(shellRun)
                term.redirect(t)
                local _, e = coroutine.resume(c)
                t = term.current()
                remotesList[clientId] = {term = t, coroutine = c, eventFilter = e}
                rednet.send(clientId, {type = protocolEvents.connectionResponce, accepted = true}, protocolName)
            else
                rednet.send(clientId, {type = protocolEvents.connectionResponce, accepted = false, reason = "Duplicate connection"}, protocolName)
            end
        end
    end

    local function clientProcessHostProcess()
        local function deepCopyTable(orig, copies) -- source: http://lua-users.org/wiki/CopyTable
            copies = copies or {}
            local orig_type = type(orig)
            local copy
            if orig_type == 'table' then
                if copies[orig] then
                    copy = copies[orig]
                else
                    copy = {}
                    copies[orig] = copy
                    for orig_key, orig_value in next, orig, nil do
                        copy[deepCopyTable(orig_key, copies)] = deepCopyTable(orig_value, copies)
                    end
                    setmetatable(copy, deepCopyTable(getmetatable(orig), copies))
                end
            else -- number, string, boolean, etc
                copy = orig
            end
            return copy
        end

        while true do
            local event = table.pack(os.pullEvent())
            for clientId, clientData in pairs(remotesList) do
                -- TODO: test that the event is not relavent to us
                -- TODO: test for client wanting specific event
                if coroutine.status(clientData.coroutine) == "dead" then
                    rednet.send(clientId, {type = protocolEvents.disconnection}, protocolName) -- TODO: give clients a reason for the disconnect (hosted program errored, hosted program ended)
                    remotesList[clientId] = nil
                else
                    
                    local convertedEvent = event
                    if clientData.eventFilter then
                        if protocolEvents[ clientData.eventFilter] and event[1] == "rednet_message" then
                            local sender, message, protocol = event[2], event[3], event[4]
                            if protocol == protocolName and sender == clientId then
                                -- TODO: convert the event when translator deamon is obsolete
                                --convertedEvent = table.pack(message.type, sender, message)
                            end
                        end
                    end

                    if clientData.eventFilter == nil or event[1] == clientData.eventFilter then
                        local eventCopy = deepCopyTable(convertedEvent) -- TODO: skip copy if we translated it

                        term.redirect(clientData.term)
                        local _
                        _, remotesList[clientId].eventFilter = coroutine.resume(clientData.coroutine, eventCopy)
                        remotesList[clientId].term = term.current()
                    end
                    
                end
            end
        end
    end

    parallel.waitForAny(clientConnectionAcceptor, clientProcessHostProcess)
    term.redirect(originalTerm)
end

return {
    protocolName = protocolName,
    protocolEvents = protocolEvents,
    inputEvents = inputEvents,
    eventTranslatorDeamon = eventTranslatorDeamon,
    newTerminalResponder = newTerminalResponder,
    connectToRemoteTerminal = connectToRemoteTerminal,
    newRemoteTerminalProxy = newRemoteTerminalProxy,
    remoteTerminalHostDeamon = remoteTerminalHostDeamon,

}