local skynet = require "skynet"
local max_client = 64

skynet.start(function()
    skynet.error("Server start")

    if not skynet.getenv "daemon" then
	   local console = skynet.newservice("console")
    end
    skynet.newservice("debug_console",8000)
    skynet.newservice("wsserver")
    skynet.exit()
end)
