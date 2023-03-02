--[[
    A few notes about the StreamCore.streams table:

    - Stream IDs are a concatenation of the entity index they are playing from,
    a underscore and any number that players passed to entity:streamStart

    - Every stream is stored as a key-value dictionary, where
    the key is the stream ID and the value is the stream properties

    - The properties are stored in a ordered list, each being:
        [1](IGModAudioChannel)	- Sound channel created with sound.PlayURL
        [2](string)				- URL of the stream
        [3](number)				- Volume
        [4](number)				- Radius
        [5](entity)				- Parent entity this stream is playing from
        [6](bool)				- Is this stream a 3D sound
        [7](number)				- Playback rate
        [8](bool)				- Enable looping
        [9](bool)				- Is paused
]]

local StreamCore = {
    streams = {},
    printTagColor = Color( 255, 145, 0 ),

    cvarDisabled = CreateClientConVar(
        "streamc_disabled",
        "0", true, false,
        "Disable all StreamCore features (for yourself).",
        0, 1
    )
}

function StreamCore:PrintConsole( msg )
    MsgC( self.printTagColor, "[StreamCore] ", color_white, msg, "\n" )
end

function StreamCore:PrintConsoleError( msg )
    MsgC( self.printTagColor, "[StreamCore] ", Color( 255, 0, 0 ), "ERROR: ", color_white, msg, "\n" )
end

function StreamCore:IsDisabled()
    return self.cvarDisabled:GetBool()
end

function StreamCore:Stop( id )
    if not self.streams[id] then return end

    if IsValid( self.streams[id][1] ) then
        self.streams[id][1]:Stop()
    end

    self.streams[id] = nil
    self:PrintConsole( "Stream #" .. id .. " successfully stopped!" )
end

function StreamCore:StopAll()
    for id, _ in pairs( self.streams ) do
        self:Stop( id )
    end

    self.streams = {}
end

-- Safely calls a function from IGModAudioChannel.
-- This was needed since sometimes sound.PlayURL ignores the
-- noblock flag, and some functions would throw errors without it
function StreamCore:CallFunc( id, func, ... )
    if not self.streams[id] then return end

    local soundObj = self.streams[id][1]
    if not IsValid( soundObj ) then return end

    local suc = pcall( soundObj[func], soundObj, ... )
    if not suc then
        self:PrintConsoleError( "Stream #" .. id .. " does not support: " .. func )
    end
end

function StreamCore:Start( id, url, vol, radius, parent, is3d, owner, isPaused )
    if self:IsDisabled() then return end
    if not IsValid( parent ) then return end
    if not IsValid( owner ) then return end

    -- Make sure we don"t have any other stream playing with this ID
    self:Stop( id )

    -- Create the stream object, even though we havent loaded the sound yet, so that
    -- any updates that happen before it loads will get applied once it does.
    self.streams[id] = { nil, url, vol, radius, parent, is3d, 1.0, false, isPaused }

    self:PrintConsole( "Stream #" .. id .. " by " .. owner:Name() .. ": " .. url )

    local flags = is3d and "noblock noplay 3d" or "noblock noplay"

    sound.PlayURL( url, flags, function( soundObj, _, errStr )
        if not IsValid( soundObj ) then
            self:PrintConsoleError( "Stream #" .. id .. " failed to load: " .. errStr )
            return
        end

        -- Dont play if our parent is invalid, or soundObj loaded after the stream was previously stopped,
        -- or a new one started with the same id (Can happen if the HTTP request takes a while to respond)
        if not IsValid( parent ) or not self.streams[id] or IsValid( self.streams[id][1] ) then
            soundObj:Stop()
            return
        end

        -- Dont play if the sound is short and the local player is too far
        if soundObj:GetLength() < 30 and LocalPlayer():GetPos():Distance( parent:GetPos() ) > radius * 2 then
            soundObj:Stop()
            return
        end

        if is3d then
            -- we"re going to calculate the fade distance ourselves,
            -- so set the 3d fade distance very high
            soundObj:Set3DFadeDistance( 9999, 99999 )
            soundObj:SetPos( parent:GetPos() )
        end

        self.streams[id][1] = soundObj

        soundObj:SetVolume( 0.0 )
        soundObj:SetPlaybackRate( self.streams[id][7] )

        self:CallFunc( id, "EnableLooping", self.streams[id][8] )

        if not self.streams[id][9] then
            soundObj:Play()
        end
    end )
end

function StreamCore:SetVolume( id, vol )
    if self.streams[id] then
        self.streams[id][3] = vol
    end
end

function StreamCore:SetRadius( id, radius )
    if self.streams[id] then
        self.streams[id][4] = radius
    end
end

function StreamCore:SetTime( id, time )
    self:CallFunc( id, "SetTime", time, true )
end

function StreamCore:SetRate( id, rate )
    if not self.streams[id] then return end

    self.streams[id][7] = rate
    self:CallFunc( id, "SetPlaybackRate", rate )
end

function StreamCore:SetLoop( id, loop )
    if not self.streams[id] then return end

    self.streams[id][8] = loop
    self:CallFunc( id, "EnableLooping", loop )
end

function StreamCore:SetPaused( id, paused )
    if not self.streams[id] then return end

    self.streams[id][9] = paused

    if paused then
        self:CallFunc( id, "Pause" )
    else
        self:CallFunc( id, "Play" )
    end
end

function StreamCore:Think()
    local plyPos = LocalPlayer():EyePos()
    local parentPos, plyDist, halfRadius, volume

    for id, stream in pairs( self.streams ) do
        -- The sound channel is not ready yet 
        if stream[1] == nil then continue end

        -- The entity the stream was attached got removed
        if not IsValid( stream[5] ) then
            StreamCore:Stop( id )

        elseif IsValid( stream[1] ) then
            parentPos = stream[5]:GetPos()

            if stream[6] then
                stream[1]:SetPos( parentPos )
            end

            plyDist = plyPos:Distance( parentPos )
            halfRadius = stream[4] * 0.5
            volume = 1

            if plyDist > halfRadius then
                volume = ( stream[4] - plyDist ) / ( stream[4] - halfRadius )
            end

            if volume < 0.05 then
                volume = 0
            end

            stream[1]:SetVolume( volume * stream[3] )
        end
    end
end

concommand.Add( "streamc_list", function()
    StreamCore:PrintConsole( "############### Active streams ###############" )

    for id, stream in pairs( StreamCore.streams ) do
        print( "#" .. id .. "\t" .. stream[2] )
    end

    StreamCore:PrintConsole( "##############################################" )
end )

concommand.Add( "streamc_stop_id", function( _, _, args )
    if #args < 1 then return end
    local id = args[1]

    StreamCore:Stop( id )
end )

concommand.Add( "streamc_stop_all", function()
    StreamCore:StopAll()
    StreamCore:PrintConsole( "Purge done." )
end )

net.Receive( "streamcore.command", function()
    local cmd = net.ReadUInt( 3 )
    local id = net.ReadString()

    if cmd == 0 then
        StreamCore:Stop( id )

    elseif cmd == 1 then
        local url = net.ReadString()
        local vol = net.ReadFloat()
        local radius = net.ReadFloat()
        local parent = net.ReadEntity()
        local is3d = net.ReadBool()
        local owner = net.ReadEntity()
        local isPaused = net.ReadBool()
        StreamCore:Start( id, url, vol, radius, parent, is3d, owner, isPaused )

    elseif cmd == 2 then
        local vol = net.ReadFloat()
        StreamCore:SetVolume( id, vol )

    elseif cmd == 3 then
        local radius = net.ReadFloat()
        StreamCore:SetRadius( id, radius )

    elseif cmd == 4 then
        local time = net.ReadFloat()
        StreamCore:SetTime( id, time )

    elseif cmd == 5 then
        local rate = net.ReadFloat()
        StreamCore:SetRate( id, rate )

    elseif cmd == 6 then
        local loop = net.ReadFloat()
        StreamCore:SetLoop( id, loop > 0 )

    elseif cmd == 7 then
        local paused = net.ReadFloat()
        StreamCore:SetPaused( id, paused > 0 )
    end
end )

local function UpdateThinkHook()
    hook.Remove( "Think", "StreamCoreImp_ProcessStreams" )

    if StreamCore:IsDisabled() then
        StreamCore:StopAll()
        StreamCore:PrintConsole( "StreamCore disabled!" )

    else
        StreamCore:PrintConsole( "StreamCore enabled!" )

        hook.Add( "Think", "StreamCoreImp_ProcessStreams", function()
            StreamCore:Think()
        end )
    end
end

cvars.AddChangeCallback( "streamc_disabled", function()
    UpdateThinkHook()
end, "streamc_disabled_changed" )

UpdateThinkHook()
