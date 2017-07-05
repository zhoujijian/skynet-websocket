local skynet = require "skynet"
local socket = require "skynet.socket"

skynet.start(function()
	local id = socket.listen("0.0.0.0", 8001)
	skynet.error("web server listen on web port 8001")

	socket.start(id, function(id, addr)
		local agent = skynet.newservice("wsagent")
		skynet.error(string.format("%s connected, pass it to agent :%08x", addr, agent))
		skynet.send(agent, "lua", id, "start")
	end)
end)