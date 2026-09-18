#!/usr/bin/env python3
"""Run deterministic recovery tests with mpv's real Lua and JSON runtime (no network)."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
mpv = os.environ.get('MPV') or shutil.which('mpv') or '/Applications/mpv.app/Contents/MacOS/mpv'
harness = r'''
local real = require 'mp'
local utils = require 'mp.utils'
local function run()
    local function setup()
        local state = {events={}, timers={}, calls={}, requests={}, aborted=0}
        local fake = {msg={warn=function() end}, osd_message=function() end}
        fake.add_timeout = function(delay, fn)
            local timer = {delay=delay, fn=fn, dead=false}
            function timer:kill() self.dead=true end
            table.insert(state.timers,timer)
            return timer
        end
        fake.register_event = function(name,fn) state.events[name]=fn end
        fake.command_native_async = function(args,cb)
            table.insert(state.requests,{args=args,cb=cb})
            return #state.requests
        end
        fake.abort_async_command = function() state.aborted=state.aborted+1 end
        fake.commandv = function(...) table.insert(state.calls,{...}) end
        package.loaded['mp'] = fake
        package.loaded['mp.options'] = {read_options=function(o) o.room='640145788197'; o.quality='FULL_HD1'; o.format='HLS' end}
        dofile(SCRIPT)
        function state:tick()
            for _,timer in ipairs(self.timers) do
                if not timer.dead then timer.dead=true; timer.fn(); return timer.delay end
            end
            error('No pending timer')
        end
        return state
    end
    local function page()
        return [[{"hls_pull_url_map":{"FULL_HD1":"https://example.com/fresh.m3u8?a=1\u0026b=2"}}]]
    end
    local s=setup()
    s.events['end-file']({reason='eof'})
    assert(s:tick()==2)
    assert(s.requests[1].args.args[#s.requests[1].args.args]=='https://live.douyin.com/640145788197')
    s.requests[1].cb(true,{status=0,stdout=page()})
    assert(s.calls[1][1]=='loadfile' and s.calls[1][2]=='https://example.com/fresh.m3u8?a=1&b=2')
    s.events['end-file']({reason='error'})
    assert(s:tick()==4) -- an immediate failure does not reset the retry budget
    print('PASS fresh URL and retry backoff')

    s=setup()
    s.events['end-file']({reason='error'})
    for _,delay in ipairs({2,4,8,16,20}) do
        assert(s:tick()==delay)
        s.requests[#s.requests].cb(true,{status=0,stdout='verification page'})
    end
    assert(#s.timers==5 and #s.requests==5 and #s.calls==0)
    print('PASS bounded retries on parsing failure')

    for _,reason in ipairs({'stop','quit'}) do
        s=setup()
        s.events['end-file']({reason='eof'})
        s.events['end-file']({reason=reason})
        assert(s.timers[1].dead and #s.requests==0)
    end
    s=setup()
    s.events['end-file']({reason='error'})
    s:tick()
    s.events['shutdown']()
    s.requests[1].cb(true,{status=0,stdout=page()})
    assert(s.aborted==1 and #s.calls==0)
    print('PASS manual stop, quit, and in-flight cancellation')

    s=setup()
    s.events['end-file']({reason='eof'}); s:tick()
    s.requests[1].cb(true,{status=0,stdout=page()})
    s.events['file-loaded'](); assert(s:tick()==60)
    s.events['end-file']({reason='eof'}); assert(s:tick()==2)
    print('PASS retry budget reset after stable load')
end
local ok,err=xpcall(run,debug.traceback)
if not ok then print(err) end
real.commandv('quit',ok and '0' or '1')
'''
with tempfile.TemporaryDirectory(prefix='douyin2mpv-test-') as tmp:
    script = Path(tmp) / 'test.lua'
    # Lua long-string literal avoids shell interpolation entirely.
    script.write_text('local SCRIPT = [=[' + str(root / 'resources/live-reconnect.lua') + ']=]\n' + harness)
    subprocess.run([mpv, '--no-config', '--idle=yes', '--vo=null', '--ao=null', '--script=' + str(script)], check=True, timeout=15)
