local skynet = require "skynet"
local socket = require "skynet.socket"
local frame  = require "websocket.frame"
local handshake = require "websocket.handshake"
local sockethelper = require "http.sockethelper"

local agent = { }
local REQUEST = { }
local FD, read, write

local function _send(message)
	local encoded = frame.encode(message, frame.TEXT)
	write(encoded)
end

local function _handshake(fd)
	FD = fd
	read  = sockethelper.readfunc(fd)
	write = sockethelper.writefunc(fd)

	local header = ""
	while true do
		local bytes = read()
		header = header .. bytes
		if #header > 8192 then
			skynet.error("<websocket.handshake>error: header size > 8192")
			return
		end

		local _, to = header:find("\r\n\r\n", -#bytes-3, true)
		if to then
			header = header:sub(1, to)
			break
		end
	end

	print("accept handshake http request:" .. header)

	local protocols = { } -- todo: how to set protocols?
	local response, protocol = handshake.accept_upgrade(header, protocols)
	if not response then
		skynet.error("<websocket.handshake>error: handshake parse header fault")
		return
	end

	print("send handshake http response:" .. response)

	write(response)
	skynet.error(string.format("<websocket.handshake>web socket %q connection established", fd))

	return true
end

local function _close()
	local encoded = frame.encode_close(1000, 'force close')
	encoded = frame.encode(encoded, frame.CLOSE)

	print("force close:" .. encoded)

	write(encoded)
	socket.close(FD)
end

local function _dispatch(text, opcode)
	print(string.format("<websocket>opcode:%q message:%q", opcode, text))

	local TEXT  = assert(frame.TEXT)
	local CLOSE = assert(frame.CLOSE)
	assert(opcode == TEXT or opcode == CLOSE, opcode)

	if opcode == TEXT then
		-- your message deserialization and logic
		return true
	end

	if opcode == CLOSE then
	    local code, reason = frame.decode_close(message)
	    print(string.format("<websocket>CLOSE code:%q reason:%q", code, reason))
	    local encoded = frame.encode_close(code)
	    encoded = frame.encode(encoded, frame.CLOSE)

	    local ok, err = pcall(write, encoded)
	    if not ok then
	    	-- remote endpoint may has closed tcp-connection already
	    	skynet.error("write close protocol failure:" .. tostring(err))
	    end
	    socket.close(assert(FD))
	end
end

local function _recv()
	local last
	local frames = {}
	local first_opcode

	while true do
		-- skynet will report error and close socket if socket error (see socket.lua)
		local encoded = read()
		if last then
			encoded = last .. encoded
			last = nil
		end

		repeat
			local decoded, fin, opcode, rest = frame.decode(encoded)
			if decoded then
				if not first_opcode then
					first_opcode = opcode
				end
				table.insert(frames, decoded)
				encoded = rest
				if fin == true then
					if not _dispatch(table.concat(frames), first_opcode) then
						-- socket closed in [_dispatch]
						return
					end
					frames = { }
					first_opcode = nil
				end
			end
		until (not decoded)
		
		if #encoded > 0 then
			last = encoded
		end
	end
end

function agent.start(fd)
	socket.start(fd)

	skynet.error("<websocket>start handshake")
	if not _handshake(fd) then
		socket.close(fd)
		skynet.exit()
		return
	end

	skynet.error("<websocket>receive and dispatch")
	_recv()

	skynet.error("<websocket>exit")
	skynet.exit()
end

skynet.start(function()
	skynet.dispatch("lua", function (_, _, fd, method, ...)
		local f = assert(agent[method])
		skynet.retpack(f(fd, ...))
	end)
end)