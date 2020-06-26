local server = require("remoteShell.server")
local client = require("remoteShell.client")

peripheral.find("modem", function(side)
    rednet.open(side)
end)

-- TODO: mbs support


local args = table.pack(...)
if args[1] == "client" then
    client.newClient().connectRemoteTerminal(args[2], term.current())
elseif args[1] == "server" then
    local s = server.newServer(args[2])
    local remoteTerminal = s.connectRemoteTerminal(18)
    
    local oldTerm = term.redirect(remoteTerminal)
    shell.run("hello")
    term.redirect(oldTerm)
end