
local terminalOverRednet = require("remoteShell.terminalOverRednet")

peripheral.find("modem", function(side)
    rednet.open(side)
end)

-- TODO: mbs support?

-- TODO: code cleanup (merge client and server into main API)
-- TODO: arg checks
-- TODO: send input back
-- TODO: file transfer
-- TODO: folder/drive mounting
-- TODO: remote peripherals
-- TODO: client catch terminate events and give menut to quite or forward terminate
-- TODO: vnc mode
-- TODO: encrypt mode?



local args = table.pack(...)
if args[1] == "client" then
            
    local hostId = tonumber(args[2])
    terminalOverRednet.connectToRemoteTerminalHost(hostId, term.current())
elseif args[1] == "server" then
    terminalOverRednet.remoteTerminalDeamon("shell")
end