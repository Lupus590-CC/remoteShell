local server = require("remoteShell.server")
local client = require("remoteShell.client")

peripheral.find("modem", function(side)
    rednet.open(side)
end)

-- TODO: mbs support?

-- TODO: code cleanup (merge client and server into main API)
-- TODO: arg checks
-- TODO: send input back
-- TODO: file transfer



local args = table.pack(...)
if args[1] == "client" then
    client.newClient().connectRemoteTerminal(args[2], term.current())
elseif args[1] == "server" then
    local s = server.newServer(args[2])
    local remoteTerminal = s.connectRemoteTerminal(18)
    
    local oldTerm = term.redirect(remoteTerminal)
    shell.run("shell")
    term.redirect(oldTerm)
end