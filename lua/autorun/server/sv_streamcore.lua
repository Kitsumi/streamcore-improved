--[[
    When networking with "streamcore.command", the first value
    is a number that tells clients what to do. It can be:

    0 - Stops a existing stream
    1 - Start a new stream
    2 - Set volume
    3 - Set radius
    4 - Set time
    5 - Set playback rate
    6 - Set looping
    7 - Set paused
]]

util.AddNetworkString( "streamcore.command" )

StreamCore = {
    config = {
        adminonly = CreateConVar( "streamc_adminonly", 0, FCVAR_SERVER_CAN_EXECUTE, "", 0, 1 ),
        maxradius = CreateConVar( "streamc_maxradius", 1500, FCVAR_SERVER_CAN_EXECUTE, "", 200, 4000 ),
        maxstreams = CreateConVar( "streamc_maxstreams", 6, FCVAR_SERVER_CAN_EXECUTE, "", 1, 10 ),
        ap_seconds = CreateConVar( "streamc_antispam_seconds", 1.0, FCVAR_SERVER_CAN_EXECUTE, "", 0.5, 5.0 ),
        whitelist_enabled = CreateConVar( "streamc_whitelist_enabled", 1, FCVAR_SERVER_CAN_EXECUTE, "", 0, 1 )
    }
}

--[[
    Whitelist code partially taken from StarfallEx / Vurv78"s WebAudio

    You can make pull requests to add more URLs here, but it must follow some rules:

    - Must be a website capable of streaming audio (obviously)
    - Sites cannot track users, unless if they are a well-known corporation.
    - Do not request to add your own website
]]

local function pattern( str ) return { str, true } end
local function simple( str ) return { string.PatternSafe( str ), false } end

local whitelist = {
    -- Soundcloud
    pattern [[%w+%.sndcdn%.com/.+]],

    -- Discord
    pattern [[cdn[%w-_]*%.discordapp%.com/.+]],
    pattern [[media%.discordapp%.net/attachments/(.+)]],

    -- Reddit
    simple [[i.redditmedia.com]],
    simple [[i.redd.it]],
    simple [[preview.redd.it]],

    -- Shoutcast
    simple [[yp.shoutcast.com]],

    -- Dropbox
    simple [[dl.dropboxusercontent.com]],
    pattern [[%w+%.dl%.dropboxusercontent%.com/(.+)]],
    simple [[www.dropbox.com]],
    simple [[dl.dropbox.com]],

    -- Github
    simple [[raw.githubusercontent.com]],
    simple [[gist.githubusercontent.com]],
    simple [[raw.github.com]],
    simple [[api.github.com]],
    simple [[cloud.githubusercontent.com]],
    simple [[user-images.githubusercontent.com]],
    pattern [[avatars(%d*)%.githubusercontent%.com/(.+)]],

    -- Steam
    simple [[images.akamai.steamusercontent.com]],
    simple [[steamuserimages-a.akamaihd.net]],
    simple [[steamcdn-a.akamaihd.net]],

    -- Gitlab
    simple [[gitlab.com]],

    -- Bitbucket
    simple [[bitbucket.org]],

    -- Onedrive
    simple [[onedrive.live.com/redir]],
    simple [[onedrive.live.com]],
    simple [[api.onedrive.com]],

    -- Google Search
    simple [[google.com]],
    simple [[www.google.com]],

    -- Google Drive
    simple [[docs.google.com]],
    simple [[drive.google.com]],

    -- Google Translate Api
    simple [[translate.google.com]],

    -- calzoneman"s aeiou
    simple [[tts.cyzon.us]],

    -- Steam
    simple [[steamcommunity.com]],
    simple [[steamcdn-a.akamaihd.net]],

    -- Puu.sh
    simple [[puu.sh]],

    -- Facepunch
    simple [[facepunch.com]]

    -- internet-radio.com
    simple [[www.internet-radio.com]]
}

function StreamCore:IsURLWhitelisted( url )
    if not isstring( url ) then return false end
    if StreamCore.config.whitelist_enabled:GetInt() == 0 then return true end
    url = string.Trim( url )

    local relative = url:match( "^https?://(.*)" )
    if not relative then return false end

    for _, data in ipairs( whitelist ) do
        local match, is_pattern = data[1], data[2]
        local haystack = is_pattern and relative or ( relative:match( "(.-)/.*" ) or relative )

        if haystack:find( string.format( "^%s%s", match, is_pattern and "" or "$" ), 1 ) then
            return true
        end
    end

    return false
end
