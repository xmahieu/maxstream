# -*- coding: utf-8 -*-
"""Playable ListItem building, shared by the plugin (setResolvedUrl) and the
graphical interface (xbmc.Player().play)."""
import json
import time
from urllib.parse import quote

import xbmc
import xbmcgui

from . import net, storage, ui
from .common import L, fmt_duration, get_bool, get_int, has_addon, home_prop, write_json
from .stream_proxy import relay_url


def slim(item):
    out = {k: v for k, v in item.items() if k != 'episodes'}
    if len(out.get('plot') or '') > 600:
        out['plot'] = out['plot'][:600] + '...'
    return json.loads(json.dumps(out))


def add_headers(url):
    if '|' in url:
        return url
    ua = net.user_agent()
    return '%s|User-Agent=%s' % (url, quote(ua)) if ua else url


def play_item(url, kind, item, prov):
    path = add_headers(url)
    li = xbmcgui.ListItem(path=path, offscreen=True)
    title = item.get('name') or item.get('title') or ''
    li.setLabel(title)
    li.setArt({'thumb': item.get('icon'), 'icon': item.get('icon')})
    ui.set_info(li, {'mediatype': 'episode' if kind == 'episode' else ('movie' if kind == 'movie' else 'video'),
                     'title': title, 'plot': item.get('plot'), 'tvshowtitle': item.get('show'),
                     'season': item.get('season'), 'episode': item.get('episode')})
    base = url.split('|')[0].split('?')[0].lower()
    is_hls = base.endswith('.m3u8')
    mode = get_int('live_inputstream', 0) if kind in ('live', 'catchup') else 0
    props = prov.kodi_props(item.get('id')) if hasattr(prov, 'kodi_props') and kind != 'catchup' else []
    if props:
        for key, value in props:
            li.setProperty(key, value)
    elif mode == 2 and is_hls and has_addon('inputstream.adaptive'):
        li.setProperty('inputstream', 'inputstream.adaptive')
        if '|' in path:
            li.setProperty('inputstream.adaptive.manifest_headers', path.split('|', 1)[1])
            li.setProperty('inputstream.adaptive.stream_headers', path.split('|', 1)[1])
    elif mode == 1 and has_addon('inputstream.ffmpegdirect'):
        li.setProperty('inputstream', 'inputstream.ffmpegdirect')
        li.setProperty('inputstream.ffmpegdirect.is_realtime_stream', 'true' if kind == 'live' else 'false')
        li.setProperty('inputstream.ffmpegdirect.stream_mode', 'timeshift' if kind == 'live' else 'none')
        if is_hls:
            li.setProperty('inputstream.ffmpegdirect.manifest_type', 'hls')
    relay_port = home_prop('relay_port')
    if (relay_port and get_bool('stream_relay', True) and not is_hls and not props
            and li.getProperty('inputstream') == ''):
        li.setPath(relay_url(int(relay_port), path, 'live' if kind == 'live' else ('catchup' if kind == 'catchup' else 'vod')))
    if is_hls:
        li.setMimeType('application/vnd.apple.mpegurl')
    elif kind in ('live', 'catchup'):
        li.setMimeType('video/mp2t')
    elif base.endswith('.mkv'):
        li.setMimeType('video/x-matroska')
    elif base.endswith('.mp4'):
        li.setMimeType('video/mp4')
    li.setContentLookup(False)
    return li


def resume_state(playlist, kind, item):
    if kind not in ('movie', 'episode'):
        return None
    state = storage.Resume(playlist['id']).get(storage.item_key(kind, item['id']))
    return state if state and state.get('pos', 0) > 30 else None


def build(playlist, prov, kind, item, seek=None):
    """Return a ready-to-play ListItem, or None if cancelled / unavailable.
    seek=None asks the resume question when a resume point exists."""
    url = prov.stream_url(kind, item['id'], item.get('ext'))
    if not url:
        return None
    key = storage.item_key(kind, item['id'])
    if seek is None:
        seek = 0
        state = resume_state(playlist, kind, item) if get_bool('resume_enabled', True) else None
        if state:
            choice = xbmcgui.Dialog().contextmenu([L(30023) % fmt_duration(state['pos']), L(30024)])
            if choice < 0:
                return None
            if choice == 0:
                seek = state['pos']
    li = play_item(url, kind, item, prov)
    storage.history(playlist['id']).add(kind, slim(item))
    write_json(storage.PENDING_FILE, {'pid': playlist['id'], 'key': key, 'kind': kind, 'seek': seek,
                                      'ts': time.time()})
    return li


def build_catchup(playlist, prov, channel, start, stop, server_start='', title=''):
    url = prov.catchup_url(channel, int(start), int(stop), server_start or '')
    item = dict(channel, name='%s - %s' % (channel.get('name'), title))
    li = play_item(url, 'catchup', item, prov)
    write_json(storage.PENDING_FILE, {'pid': playlist['id'], 'key': '', 'kind': 'catchup', 'seek': 0,
                                      'ts': time.time()})
    return li


def start(li, windowed=False):
    xbmc.Player().play(li.getPath(), li, windowed)


def stop_playback(player=None, wait=4.0):
    """Stop the video without blocking Kodi's GUI thread.

    xbmc.Player().stop() waits for the GUI thread; calling it while a window
    with a video preview closes can freeze Kodi. PlayerControl(Stop) is queued
    instead and we wait (bounded) until playback has really ended."""
    player = player or xbmc.Player()
    xbmc.executebuiltin('PlayerControl(Stop)')
    monitor = xbmc.Monitor()
    deadline = wait
    while deadline > 0 and player.isPlaying():
        if monitor.waitForAbort(0.1):
            break
        deadline -= 0.1
