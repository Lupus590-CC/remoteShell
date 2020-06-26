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
    
    print("hello world")
    local s = server.newServer(args[2])
    
    print("hello world")
    local remoteTerminal = s.connectRemoteTerminal(18)
    remoteTerminal.write("hello world")
    --term.redirect(remoteTerminal)
    print("hello world")
    --shell.run("starup/00_mbs.lua")
end