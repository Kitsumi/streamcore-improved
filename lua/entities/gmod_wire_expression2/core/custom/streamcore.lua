E2Lib.RegisterExtension("streamcore", true)

-- Keep track of how many streams each player have
local streamCounter = WireLib.RegisterPlayerTable()

-- Keep track of how long to wait before allowing each player to start a stream again
local nextCreations = WireLib.RegisterPlayerTable()

local function canStartStream(ply)
	if StreamCore.config.adminonly:GetBool() and not ply:IsAdmin() then
		return false
	end

	local count = streamCounter[ply] or 0
	if count >= StreamCore.config.maxstreams:GetInt() then
		return false
	end

	local now, nex = SysTime(), nextCreations[ply] or 0
	if now < nex then
		return false
	end

	return true
end

local function canStreamUpdate(self)
	return SysTime() > self.data.sc_next_update
end

local function streamStop(self, streamId, dontBroadcast)
	if not self.data.sc_streams[streamId] then return end
	self.data.sc_streams[streamId] = nil

	streamCounter[self.player] = streamCounter[self.player] - 1

	if dontBroadcast then return end

	net.Start("streamcore.command")
		net.WriteUInt(0, 3)
		net.WriteString(streamId)
	net.Broadcast()
end

local function streamStart(self, parent, id, volume, url, autoplay)
	local owner = self.player

	if not IsValid(owner) then return end
	if not IsValid(parent) then return end

	if not E2Lib.isOwner(self, parent) then
		error("Tried to create a stream on a entity you do not own!")
		return
	end

	local streamId = self.entity:EntIndex() .. "-" .. id

	-- Note that the last parameter is "true" here. We dont have to
	-- transmit to clients to stop the stream since streamStart on the client
	-- will already stop streams that use the same ID
	streamStop(self, streamId, true)

	local count = streamCounter[owner] or 0
	if count >= StreamCore.config.maxstreams:GetInt() then
		error("Reached the limit of streams!")
	end

	if not canStartStream(owner) then return end

	if not StreamCore:IsURLWhitelisted(url) then
		error("The URL is not whitelisted on the server!")
		return
	end

	if url:find("dropbox", 1, true) then
		url, _ = string.gsub(url, [[^http%://dl%.dropboxusercontent%.com/]], [[https://dl.dropboxusercontent.com/]])
		url, _ = string.gsub(url, [[^https?://dl.dropbox.com/]], [[https://www.dropbox.com/]])
		url, _ = string.gsub(url, [[^https?://www.dropbox.com/s/(.+)%?dl%=[01]$]], [[https://dl.dropboxusercontent.com/s/%1]])
		url, _ = string.gsub(url, [[^https?://www.dropbox.com/s/(.+)$]], [[https://dl.dropboxusercontent.com/s/%1]])
	end

	nextCreations[owner] = SysTime() + StreamCore.config.ap_seconds:GetFloat()
	streamCounter[owner] = count + 1

	self.data.sc_next_update = 0
	self.data.sc_streams[streamId] = true

	net.Start("streamcore.command")
		net.WriteUInt(1, 3)
		net.WriteString(streamId)

		net.WriteString(url)
		net.WriteFloat(math.Clamp(volume, 0.0, 3.0))
		net.WriteFloat(StreamCore.config.maxradius:GetFloat() * 0.5)
		net.WriteEntity(parent)
		net.WriteBool(self.data.sc_is3d)
		net.WriteEntity(owner)
		net.WriteBool(autoplay)
	net.Broadcast()
end

__e2setcost(5)
e2function void streamDisable3D(disable)
	self.data = self.data or {}
	self.data.sc_is3d = not (disable > 0)
end

e2function number streamsRemaining()
	return StreamCore.config.maxstreams:GetInt() - (streamCounter[self.player] or 0)
end

e2function number streamMaxRadius()
	return StreamCore.config.maxradius:GetFloat()
end

e2function number streamAdminOnly()
	return StreamCore.config.adminonly:GetBool() and 1 or 0
end

e2function number streamCanStart()
	return canStartStream(self.player) and 1 or 0
end

e2function number streamCanUpdate()
	return canStreamUpdate(self) and 1 or 0
end

__e2setcost(10)
e2function void streamStop(id)
	streamStop(self, self.entity:EntIndex() .. "-" .. id)
end

__e2setcost(50)
e2function void entity:streamStart(id, volume, string url)
	streamStart(self, this, id, volume, url, true)
end

e2function void entity:streamStart(id, string url, volume)
	streamStart(self, this, id, volume, url, true)
end

e2function void entity:streamStart(id, string url)
	streamStart(self, this, id, 1.0, url, true)
end

e2function void entity:streamCreate(id, string url, volume)
	streamStart(self, this, id, volume, url, false)
end

__e2setcost(15)
e2function void streamVolume(id, volume)
	local streamId = self.entity:EntIndex() .. "-" .. id
	local owner = self.player

	if not self.data.sc_streams[streamId] then
		error("Tried to use streamVolume on a inexistent stream!")
		return
	end

	if not canStreamUpdate(self) then return end
	self.data.sc_next_update = SysTime() + 0.1

	net.Start("streamcore.command")
		net.WriteUInt(2, 3)
		net.WriteString(streamId)
		net.WriteFloat(math.Clamp(volume, 0.0, 2.0))
	net.Broadcast()
end

e2function void streamRadius(id, radius)
	local streamId = self.entity:EntIndex() .. "-" .. id
	local owner = self.player

	if not self.data.sc_streams[streamId] then return end
	if not canStreamUpdate(self) then return end

	self.data.sc_next_update = SysTime() + 0.1

	net.Start("streamcore.command")
		net.WriteUInt(3, 3)
		net.WriteString(streamId)
		net.WriteFloat(math.Clamp(radius, 10, StreamCore.config.maxradius:GetFloat()))
	net.Broadcast()
end

e2function void streamTime(id, time)
	local streamId = self.entity:EntIndex() .. "-" .. id
	local owner = self.player

	if not self.data.sc_streams[streamId] then return end
	if not canStreamUpdate(self) then return end

	self.data.sc_next_update = SysTime() + 0.1

	net.Start("streamcore.command")
		net.WriteUInt(4, 3)
		net.WriteString(streamId)
		net.WriteFloat(math.max(time, 0))
	net.Broadcast()
end

registerCallback("construct", function(self)
	self.data = self.data or {}
	self.data.sc_is3d = true
	self.data.sc_next_update = 0
	self.data.sc_streams = {}
end)

registerCallback("destruct", function(self)
	for streamId, _ in pairs(self.data.sc_streams) do
		streamStop(self, streamId)
	end

	self.data.sc_streams = {}
end)