
local terminalOverRednet = require("remoteShell.terminalOverRednet")

peripheral.find("modem", function(side)
    rednet.open(side)
end)

-- TODO: mbs support? choosable startup program

-- TODO: arg checks
-- TODO: file transfer
-- TODO: folder/drive mounting
-- TODO: remote peripherals
-- TODO: client catch terminate events and give menu to quite or forward terminate
-- TODO: vnc mode
-- TODO: encrypt mode?
-- TODO: forward connections or prevent connecting through a server
-- TODO: send diconnect on server terminate

local args = table.pack(...)
local function main()
    if args[1] == "client" then
        local hostId = tonumber(args[2])
        terminalOverRednet.connectToRemoteTerminal(hostId, term.current())
    elseif args[1] == "server" then
        terminalOverRednet.remoteTerminalDeamon()
    end
end

parallel.waitForAny(terminalOverRednet.eventTranslatorDeamon, main)