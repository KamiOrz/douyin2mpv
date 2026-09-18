-- MIT License. Refresh expiring Douyin URLs inside the existing mpv window.
local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'
local opts = { room = '', quality = 'FULL_HD1', format = 'HLS' }
options.read_options(opts, 'douyin2mpv')
if not opts.room:match('^%d+$') then return end

local attempts, generation = 0, 0
local pending, stable, request
local recovering = false
local limit = 5
local recover

local function cancel()
    generation = generation + 1
    if pending then pending:kill(); pending = nil end
    if stable then stable:kill(); stable = nil end
    if request then mp.abort_async_command(request); request = nil end
    recovering = false
end

local function stream_url(page)
    local text = page:gsub('\\"', '"')
    local key = opts.format == 'FLV' and 'flv_pull_url' or 'hls_pull_url_map'
    local raw = text:match('"' .. key .. '"%s*:%s*(%b{})')
    local map = raw and utils.parse_json(raw)
    if type(map) ~= 'table' then return nil end
    local function valid(value)
        return type(value) == 'string' and value:match('^https?://')
    end
    if valid(map[opts.quality]) then return map[opts.quality] end
    for _, quality in ipairs({'FULL_HD1', 'HD1', 'SD2', 'SD1'}) do
        if valid(map[quality]) then return map[quality] end
    end
end

recover = function()
    if attempts >= limit then
        recovering = false
        mp.osd_message('直播恢复失败，可能已下播。请稍后重新播放。', 15)
        mp.msg.warn('Auto recovery stopped after ' .. limit .. ' attempts')
        return
    end
    attempts = attempts + 1
    recovering = true
    local token = generation
    local delay = math.min(2 ^ attempts, 20)
    mp.osd_message('直播断开，' .. delay .. ' 秒后重连（' .. attempts .. '/' .. limit .. '）', delay)
    pending = mp.add_timeout(delay, function()
        pending = nil
        if token ~= generation then return end
        request = mp.command_native_async({
            name = 'subprocess', playback_only = false, capture_stdout = true,
            capture_stderr = true,
            args = {'/usr/bin/curl', '--fail', '--silent', '--show-error',
                '--location', '--max-time', '20', '--max-filesize', '8388608',
                '--user-agent', 'Mozilla/5.0', 'https://live.douyin.com/' .. opts.room}
        }, function(success, result)
            request = nil
            if token ~= generation then return end
            local url = success and result and result.status == 0 and stream_url(result.stdout or '')
            if not url then
                recover()
                return
            end
            recovering = false
            mp.osd_message('正在恢复直播…', 5)
            mp.commandv('loadfile', url, 'replace')
        end)
    end)
end

mp.register_event('end-file', function(event)
    if event.reason == 'eof' or event.reason == 'error' then
        if stable then stable:kill(); stable = nil end
        if not recovering then recover() end
    elseif event.reason == 'stop' or event.reason == 'quit' then
        cancel()
    end
end)
mp.register_event('file-loaded', function()
    if stable then stable:kill() end
    -- Reset the budget only after sustained playback, not just a successful open.
    stable = mp.add_timeout(60, function() attempts = 0; stable = nil end)
end)
mp.register_event('shutdown', cancel)
