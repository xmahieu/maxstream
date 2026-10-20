# -*- coding: utf-8 -*-
"""End-to-end checks of MaxStream with Kodi stubs and a fake Xtream / M3U server.

python tools/test/run_tests.py
"""
import json
import os
import re
import shutil
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.abspath(os.path.join(HERE, '..', '..', 'script.maxstream'))
ROOT = tempfile.mkdtemp()
os.environ['KODI_TEST_ROOT'] = ROOT
os.environ['KODI_ADDON_DIR'] = ADDON
sys.path[:0] = [os.path.join(HERE, 'stubs'), ADDON, HERE]

import xbmc  # noqa: E402
import xbmcaddon  # noqa: E402
import xbmcgui  # noqa: E402
import fake_server  # noqa: E402

BASE_URL = fake_server.start()

from resources.lib import actions, main, pvr, service, storage  # noqa: E402
from resources.lib.gui import base, detail, guide, home, live, vod  # noqa: E402
from resources.lib.provider import build_catchup_url, normalize_server, parse_xtream_link  # noqa: E402

OK = [0]


def check(cond, msg):
    assert cond, msg
    OK[0] += 1


def answers(*values):
    xbmcgui.RESPONSES[:] = list(values)


def done():
    assert not xbmcgui.RESPONSES, 'unused answers %r' % xbmcgui.RESPONSES


def notes():
    return [d[1] for d in xbmcgui.DIALOGS if d[0] == 'notification']


def act(win, aid):
    win.onAction(xbmcgui.Action(aid))


def last(cls):
    return [w for w in xbmcgui.WINDOWS if isinstance(w, cls)][-1]


def played():
    return xbmc.PLAYED[-1]


def wait_prop(win, key, timeout=10):
    end = time.time() + timeout
    while time.time() < end:
        if win.getProperty(key):
            return win.getProperty(key)
        time.sleep(0.05)
    raise AssertionError('property %s never set' % key)


# ---------------------------------------------------------------- helpers
check(parse_xtream_link('http://h:8080/get.php?username=a&password=b&type=m3u_plus') == ('http://h:8080', 'a', 'b'), 'link')
check(normalize_server('h.com:80/player_api.php?x') == 'http://h.com:80', 'normalize')

# ---------------------------------------------------------------- first start: add account from the home screen
answers(0, BASE_URL, 'u', 'p', 'My IPTV', True)
home.open_home()
done()
check(xbmc.GUI_SETTINGS['filecache.memorysize'] == 256 and xbmc.GUI_SETTINGS['filecache.readfactor'] == 2000,
      'cache tuned %r' % xbmc.GUI_SETTINGS)
adv = open(os.path.join(ROOT, 'profile', 'advancedsettings.xml'), encoding='utf-8').read()
check('<curlretries>5</curlretries>' in adv, 'advancedsettings network retries')
check(any(d[0] == 'yesno' and 'Optimise' in d[1] for d in xbmcgui.DIALOGS), 'tuning offered once')
h = last(home.HomeWindow)
check(not h.closed and storage.active_playlist()['type'] == 'xtream', 'account added at first start')
check(wait_prop(h, 'live_sub').startswith('3 channels'), 'live tile count %r' % h.getProperty('live_sub'))
check(wait_prop(h, 'expiry') == 'Expires 01/01/2030', 'expiry %r' % h.getProperty('expiry'))
wait_prop(h, 'series_sub')
check(h.getProperty('movie_sub') == '2 titles' and h.getProperty('sc_201') == 'Channels (1)', 'tile subs')
check(xbmcgui._PROPS.get('script.maxstream.gui_open') == '', 'gui flag released')

# EPG
answers()
check(actions.epg_update() and any('TV guide updated (3' in n for n in notes()), 'epg update')

# ---------------------------------------------------------------- live TV
h.onClick(home.TILE_LIVE)
lw = last(live.LiveWindow)
cats = lw.getControl(live.CATS).labels()
check(cats[:3] == ['All', 'Favourites', 'Recently watched'] and 'News' in cats and 'Empty' not in cats, 'live cats %r' % cats)
check(lw.getControl(live.CHANNELS).size() == 3 and lw.getFocusId() == live.CHANNELS, 'all channels')
lw.select_category(cats.index('News'))
chans = lw.getControl(live.CHANNELS)
check(chans.labels() == ['France 24'], 'news channels')
item = chans.items[0]
check(item.getProperty('catchup') == '1' and 'france24.fr show 0' in item.getProperty('now'), 'channel row %r' % item.props)
check(item.tag.data.get('resumepoint'), 'channel progress')
check(lw.getProperty('sel_now') == 'france24.fr show 0 & co' and 'show 1' in lw.getProperty('sel_next1'), 'info panel')
check(lw.getProperty('sel_catchup') == '1' and 0 <= lw.getControl(live.PROGRESS).percent <= 100, 'info extras')
lw.setFocusId(live.CHANNELS)
lw.onClick(live.CHANNELS)
path, li, windowed = played()
check(windowed and path.startswith(BASE_URL + '/live/u/p/101.ts|User-Agent='), 'preview windowed %s' % path)
lw.onClick(live.CHANNELS)
check(xbmc.BUILTINS[-1] == 'ActivateWindow(fullscreenvideo)', 'second OK = fullscreen')
lw.onClick(live.BTN_FAV)
check(storage.favourites(storage.active_playlist()['id']).contains('live', '101') and lw.getProperty('sel_fav') == '1', 'fav')
check(chans.items[0].getProperty('fav') == '1', 'fav star in row')
# guide + catch-up from the replay button
lw.onClick(live.BTN_REPLAY)
gd = last(guide.GuideDialog)
progs = gd.getControl(guide.PROGS)
check(progs.size() >= 1 and progs.items[0].getProperty('status') == 'replay', 'replay list %r' % progs.labels())
gd.onClick(guide.PROGS)
path = played()[0]
check('/timeshift/u/p/60/' in path and gd.closed, 'catch-up playback %s' % path)
lw.onClick(live.BTN_GUIDE)
gd = last(guide.GuideDialog)
check(any(i.getProperty('status') == 'live' for i in gd.getControl(guide.PROGS).items), 'guide shows live')
# search
answers('euro')
lw.onClick(live.SEARCH)
done()
check(lw.getControl(live.CATS).labels()[0].startswith('Search: euro') and lw.channels[0]['name'] == 'Euro Sport 1', 'live search')
# re-init after fullscreen keeps state
lw.doModal()
check(lw.getControl(live.CHANNELS).size() == 1, 're-init redraw')
act(lw, 92)
check(lw.closed and not xbmc.Player.playing, 'back stops preview and closes')

# favourites shortcut (Guide TV opens on favourites)
h.onClick(home.SC_GUIDE)
lw2 = last(live.LiveWindow)
check(lw2.cats[lw2.cat_index]['id'] == 'fav' and lw2.channels[0]['id'] == '101', 'guide shortcut -> favourites')

# replay shortcut = catch-up channels only, OK opens the replay guide
h.onClick(home.SC_REPLAY)
rw = last(live.LiveWindow)
check([c['name'] for c in rw.channels] == ['France 24'], 'catch-up mode channels')
rw.onClick(live.CHANNELS)
check(last(guide.GuideDialog).catchup, 'catch-up guide')

# ---------------------------------------------------------------- movies
h.onClick(home.TILE_MOVIES)
vw = last(vod.VodWindow)
secs = vw.getControl(vod.CATS).labels()
check(secs[:3] == ['All', 'Favourites', 'Recently added'] and 'Action' in secs, 'movie sections %r' % secs)
grid = vw.getControl(vod.GRID)
check(grid.size() == 2 and vw.getProperty('subtitle') == 'All · 2 titles', 'grid %r' % vw.getProperty('subtitle'))
vw.onClick(vod.SORT_AZ)
check(grid.labels() == ['Big Movie (2021)', 'Le Dîner de cons'] and vw.getProperty('sort') == 'az', 'sort az')
vw.onClick(vod.SORT_RATING)
check(grid.items[0].getProperty('rating') == '7.5' and grid.items[0].label2 == '2021', 'rating badge/meta')
check(grid.items[0].getProperty('new') == '1', 'new badge')
grid.selectItem(0)
vw.onClick(vod.GRID)
dw = last(detail.DetailWindow)
check(dw.getProperty('title') == 'Big Movie' and 'Explosions.' in dw.getProperty('plot'), 'detail %r' % dw.props)
check('★ 7.5' in dw.getProperty('meta') and '1 h 40' in dw.getProperty('meta'), 'detail meta %r' % dw.getProperty('meta'))
check(dw.getProperty('btn_play') == 'Play' and dw.getProperty('has_resume') == '', 'no resume yet')
check(dw.getControl(detail.BTN_PLAY).nav == {'right': detail.BTN_FAV, 'down': detail.RELATED}, 'button chain %r' % dw.getControl(detail.BTN_PLAY).nav)
dw.onClick(detail.BTN_PLAY)
check(played()[0].startswith(BASE_URL + '/movie/u/p/201.mkv') and not played()[2], 'movie fullscreen')
player = service.Player()
player.seekTime = lambda t: None
player.onAVStarted()
player.pos, player.total = 1200, 6000
player.onPlayBackStopped()
dw.doModal()  # back from playback
check(dw.getProperty('btn_play') == 'Resume at 20:00' and dw.getProperty('has_resume') == '1', 'resume label')
check(abs(dw.getControl(detail.PROGRESS).percent - 20) < 0.1, 'resume bar')
check(dw.getControl(detail.BTN_FAV).nav.get('right') == detail.BTN_START, 'chain incl. from-start')
dw.onClick(detail.BTN_PLAY)
check(json.load(open(storage.PENDING_FILE))['seek'] == 1200, 'resume seek')
dw.onClick(detail.BTN_START)
check(json.load(open(storage.PENDING_FILE))['seek'] == 0, 'from start')
dw.onClick(detail.BTN_FAV)
check(dw.getProperty('fav') == '1', 'movie fav')
check(dw.getControl(detail.RELATED).size() == 0, 'no related (alone in category)')
# continue watching on home
h.doModal()
check(h.getControl(home.CONTINUE).labels() == ['Big Movie (2021)'] and 'left' in h.getControl(home.CONTINUE).items[0].label2,
      'continue row %r' % h.getControl(home.CONTINUE).labels())
answers(0)
h.onClick(home.CONTINUE)
done()
check(json.load(open(storage.PENDING_FILE))['seek'] == 1200, 'continue resumes')

# premature end of stream (connection dropped) must not mark the movie as watched
player.onAVStarted()
player.pos, player.total = 3000, 6000
player.onPlayBackEnded()
check(not storage.Resume(storage.active_playlist()['id']).get('movie:201').get('watched')
      and storage.Resume(storage.active_playlist()['id']).get('movie:201')['pos'] == 3000, 'early EOF keeps resume point')
player.onAVStarted()
player.pos, player.total = 1200, 6000
player.onPlayBackStopped()

# ---------------------------------------------------------------- series
h.onClick(home.TILE_SERIES)
sw = last(vod.VodWindow)
sw.select_section(sw.getControl(vod.CATS).labels().index('Drama'))
grid = sw.getControl(vod.GRID)
grid.selectItem([i['name'] for i in sw.view].index('The Show'))
sw.onClick(vod.GRID)
ds = last(detail.DetailWindow)
check(ds.getProperty('mode') == 'series' and ds.getControl(detail.SEASONS).labels() == ['Season 1', 'Season 2'], 'seasons')
check(ds.getControl(detail.EPISODES).labels() == ['Episode 1', 'Episode 2'] and ds.getControl(detail.EPISODES).items[1].getProperty('epnum') == '02', 'episodes %r' % ds.getControl(detail.EPISODES).labels())
check(ds.getProperty('btn_play') == 'Play S01E01', 'play first ep %r' % ds.getProperty('btn_play'))
ds.onClick(detail.BTN_PLAY)
check(played()[0].startswith(BASE_URL + '/series/u/p/4000.mkv'), 'episode url')
player.onAVStarted()
player.pos, player.total = 600, 2700
player.onPlayBackStopped()
ds.doModal()
check(ds.getProperty('btn_play') == 'Resume S01E01', 'resume ep label %r' % ds.getProperty('btn_play'))
ds.getControl(detail.SEASONS).selectItem(1)   # mouse click on the second season tab: no move action
ds.onClick(detail.SEASONS)
check(ds.getControl(detail.EPISODES).labels() == ['Episode 1'] and ds.getFocusId() == detail.EPISODES, 'season click shows its episodes')
ds.getControl(detail.SEASONS).selectItem(0)
ds.setFocusId(detail.SEASONS)
act(ds, 1)
check(len(ds.getControl(detail.EPISODES).labels()) == 2, 'season switch with the remote')
ds.getControl(detail.SEASONS).selectItem(1)
act(ds, 2)
ds.getControl(detail.EPISODES).selectItem(0)
ds.onClick(detail.EPISODES)
check(played()[0].startswith(BASE_URL + '/series/u/p/4010.mp4'), 'episode from list')

# ---------------------------------------------------------------- favourites + search screens
h.onClick(home.SC_FAV)
fw = last(vod.VodWindow)
check(fw.getControl(vod.CATS).labels() == ['Movies', 'Series', 'Live TV'] and fw.getControl(vod.GRID).labels() == ['Big Movie (2021)'],
      'favourites screen')
fw.select_section(2)
fw.getControl(vod.GRID).selectItem(0)
fw.onClick(vod.GRID)
check(played()[0].startswith(BASE_URL + '/live/u/p/101.ts') and not played()[2], 'fav channel plays fullscreen')
answers('show')
h.onClick(home.SC_SEARCH)
done()
srw = last(vod.VodWindow)
check(srw.getControl(vod.CATS).labels() == ['Movies (0)', 'Series (1)', 'Live TV' if False else 'Channels (0)'], 'search sections %r' % srw.getControl(vod.CATS).labels())

# ---------------------------------------------------------------- parental control
xbmcaddon.SETTINGS['parental_enabled'] = 'true'
h.onClick(home.TILE_LIVE)
pw = last(live.LiveWindow)
check(not any(c['name'] == 'Night Channel' for c in pw.channels), 'adult filtered from All')
adult = [i for i, c in enumerate(pw.cats) if c['name'] == 'XXX Adult'][0]
check('[Locked]' in pw.getControl(live.CATS).labels()[adult], 'locked label')
pw.select_category(adult)
check(pw.getProperty('empty_text') == 'Locked - press OK to unlock', 'locked on focus')
pw.getControl(live.CATS).selectItem(adult)
answers('1234')
pw.onClick(live.CATS)
done()
check('Wrong PIN' in notes() and not pw.channels, 'wrong pin')
answers('0000')
pw.onClick(live.CATS)
done()
check([c['name'] for c in pw.channels] == ['Night Channel'], 'pin ok')
actions.lock()
xbmcaddon.SETTINGS['parental_enabled'] = 'false'

# hide a category from the live screen
h.onClick(home.TILE_LIVE)
hw = last(live.LiveWindow)
hw.getControl(live.CATS).selectItem([c['name'] for c in hw.cats].index('Sports'))
hw.setFocusId(live.CATS)
answers(0)
act(hw, 117)
done()
check('Sports' not in [c['name'] for c in hw.cats], 'category hidden')
answers([0])
actions.manage_hidden()
done()

# ---------------------------------------------------------------- Kodi TV menu (IPTV Simple)
xbmc.HAS.add('pvr.iptvsimple')
answers()
check(actions.pvr_sync(), 'pvr sync')
m3u = open(pvr.M3U_PATH, encoding='utf-8').read()
check('tvg-id="france24.fr"' in m3u and 'catchup="xc" catchup-days="3"' in m3u and '/live/u/p/101.ts' in m3u, 'pvr m3u')
check(os.path.getsize(pvr.EPG_PATH) > 1000, 'pvr epg copy')
inst_dir = os.path.join(ROOT, 'profile', 'addon_data', 'pvr.iptvsimple')
inst = open(os.path.join(inst_dir, 'instance-settings-1.xml'), encoding='utf-8').read()
check('<setting id="m3uPath">%s</setting>' % pvr.M3U_PATH in inst and '<setting id="catchupEnabled">true</setting>' in inst,
      'instance settings')
check(any('SetAddonEnabled' in r for r in xbmc.RPC), 'pvr addon restarted')
check(xbmcaddon.SETTINGS.get('pvr_sync') == 'true', 'sync enabled')
answers()
actions.pvr_sync()
check(sorted(os.listdir(inst_dir)) == ['instance-settings-1.xml'], 'instance reused')
xbmcaddon.SETTINGS['parental_enabled'] = 'true'
pvr.export_m3u(storage.active_playlist(), base.SESSION.prov)
check('Night Channel' not in open(pvr.M3U_PATH, encoding='utf-8').read(), 'locked excluded from TV menu')
xbmcaddon.SETTINGS['parental_enabled'] = 'false'
os.remove(pvr.M3U_PATH)
service.refresh_epg(force=True)
check(os.path.exists(pvr.M3U_PATH), 'service keeps TV menu in sync')

# ---------------------------------------------------------------- M3U playlist through the menus
answers(len(storage.playlists()), 1, BASE_URL + '/plain.m3u', '', 'Plain')
h.onClick(home.SC_LISTS)
done()
check(base.SESSION.pl['name'] == 'Plain' and h.getProperty('playlist') == 'Plain', 'switch to new m3u playlist')
h.onClick(home.TILE_LIVE)
mw = last(live.LiveWindow)
check([c['name'] for c in mw.channels][:2] == ['Arte HD', 'France 24'], 'm3u channels %r' % [c['name'] for c in mw.channels])
mw.onClick(live.CHANNELS)
check(played()[0] == 'http://stream.example/arte/index.m3u8|User-Agent=MyUA/1.0', 'm3u headers')
h.onClick(home.TILE_SERIES)
msw = last(vod.VodWindow)
check(msw.getControl(vod.GRID).labels() == ['Cool Show', 'Other.Show'], 'm3u series')
msw.getControl(vod.GRID).selectItem(0)
msw.onClick(vod.GRID)
mds = last(detail.DetailWindow)
check(mds.getControl(detail.SEASONS).size() == 2, 'm3u seasons')
# switch back with the playlist menu (pick first, Activate)
answers(0, 0)
h.onClick(home.SC_LISTS)
done()
check(base.SESSION.pl['name'] == 'My IPTV', 'switch back')

# ---------------------------------------------------------------- script entry points & settings buttons
main.run(['default.py', 'action=clear_cache'])
check('Cache cleared' in notes(), 'RunScript action')
answers(-1)
h.onClick(home.SETTINGS)
done()
answers()
h.onClick(home.SC_ACCOUNT)
check(any(d[0] == 'textviewer' and '01/01/2030' in d[2] for d in xbmcgui.DIALOGS), 'account')
h.onClick(home.DONATE)
from resources.lib.gui import donate as donate_mod  # noqa: E402
dd = last(donate_mod.DonateDialog)
check(dd.getControl(donate_mod.OPEN) and dd.getFocusId() is None, 'donate dialog opens')
dd.onClick(donate_mod.CLOSE)
check(dd.closed, 'donate dialog closes')
check(xbmcaddon.Addon().getSetting('act_donate') == '' and 'paypal.me/MaxStreamKodi/5EUR' in open(os.path.join(
    ADDON, 'resources/skins/Default/1080i/script-maxstream-donate.xml'), encoding='utf-8').read(), 'donate link shown')
act(h, 10)
check(h.closed, 'home closes on back')

# ---------------------------------------------------------------- episode titles
check(base.episode_title({'title': 'The Show - S01E02 - Le retour', 'show': 'The Show', 'episode': 2}) == 'Le retour', 'title clean 1')
check(base.episode_title({'title': 'FR - Big Series S03 E10', 'show': 'Big Series', 'episode': 10}) == 'FR - Big Series', 'title clean 2')
check(base.episode_title({'title': '', 'show': 'X', 'episode': 4}) == 'Episode 4', 'title fallback')

# ---------------------------------------------------------------- catch-up url templates
st, en = 1700000000, 1700003600
check(build_catchup_url('http://h/ch/index.m3u8?t=1', 'flussonic', '', st, en) == 'http://h/ch/index-1700000000-3600.m3u8?t=1', 'flussonic')
check(build_catchup_url('http://h/a.m3u8', 'append', '?s={utc}&d={duration:60}', st, en) == 'http://h/a.m3u8?s=1700000000&d=60', 'append')
check(build_catchup_url('http://h/a|User-Agent=x', 'default', 'http://h/arc/${start}/{Y}-{m}-{d}', st, en) ==
      'http://h/arc/1700000000/2023-11-14|User-Agent=x', 'default')

# ---------------------------------------------------------------- every control id used in Python exists in its XML
for module, xml in ((home, 'home'), (live, 'live'), (vod, 'vod'), (detail, 'detail'), (guide, 'guide'), (donate_mod, 'donate')):
    ids = set(int(i) for i in re.findall(r'id="(\d+)"', open(os.path.join(
        ADDON, 'resources/skins/Default/1080i/script-maxstream-%s.xml' % xml), encoding='utf-8').read()))
    used = set(v for k, v in vars(module).items() if k.isupper() and isinstance(v, int) and 90 <= v < 1000)
    check(used <= ids, '%s: ids missing in XML: %s' % (xml, sorted(used - ids)))

# ---------------------------------------------------------------- stream relay (auto-reconnect)
import urllib.request  # noqa: E402
from resources.lib import playback, stream_proxy  # noqa: E402
stream_proxy.STALL_TIMEOUT = 1
relay = stream_proxy.Relay()
port = relay.start()
t0 = time.time()
data = urllib.request.urlopen(stream_proxy.relay_url(port, BASE_URL + '/vodfile.mkv|User-Agent=Test', 'vod'), timeout=30).read()
check(data == fake_server.VOD_DATA, 'relay rebuilt the file after a stall and a drop (%d bytes)' % len(data))
check(fake_server.STATE['vod_conn'] == 3 and time.time() - t0 < 10, 'relay reconnected twice quickly')
req = urllib.request.Request(stream_proxy.relay_url(port, BASE_URL + '/vodfile.mkv', 'vod'), headers={'Range': 'bytes=1000000-'})
resp = urllib.request.urlopen(req, timeout=30)
check(resp.status == 206 and resp.read() == fake_server.VOD_DATA[1000000:], 'relay passes seeking ranges')
live_resp = urllib.request.urlopen(stream_proxy.relay_url(port, BASE_URL + '/live.ts', 'live'), timeout=30)
got = 0
while got < 700000:
    got += len(live_resp.read(65536))
live_resp.close()
check(fake_server.STATE['live_conn'] >= 4, 'live channel re-opened when the server closes it')
time.sleep(1.5)
conns = fake_server.STATE['live_conn']
time.sleep(3)
check(fake_server.STATE['live_conn'] == conns, 'relay stops reconnecting once Kodi has left the channel (%d -> %d)'
      % (conns, fake_server.STATE['live_conn']))
xbmcgui._PROPS['script.maxstream.relay_port'] = str(port)
li = playback.build(storage.active_playlist(), base.SESSION.prov, 'movie', {'id': '201', 'name': 'x', 'ext': 'mkv'}, seek=0)
check(li.getPath().startswith('http://127.0.0.1:%d/stream?k=vod&u=' % port) and li.mime == 'video/x-matroska', 'movies go through the relay')
xbmcaddon.SETTINGS['stream_relay'] = 'false'
li = playback.build(storage.active_playlist(), base.SESSION.prov, 'movie', {'id': '201', 'name': 'x', 'ext': 'mkv'}, seek=0)
check(li.getPath().startswith(BASE_URL), 'relay can be switched off')
relay.stop()

# ---------------------------------------------------------------- audio / subtitle languages
import copy  # noqa: E402
from resources.lib import languages  # noqa: E402
FILM = {'audiostreams': [{'index': 0, 'language': 'eng', 'name': 'English 5.1'},
                         {'index': 1, 'language': '', 'name': 'VFF AC3'},
                         {'index': 2, 'language': 'fre', 'name': 'Commentaire'}],
        'subtitles': [{'index': 0, 'language': 'fre', 'name': 'Forcés', 'isforced': True},
                      {'index': 1, 'language': 'fre', 'name': 'Français'},
                      {'index': 2, 'language': 'eng', 'name': 'English SDH'}]}


def lang_run(audio, mode, sub_lang=1):
    xbmc.STREAMS.clear()
    xbmc.STREAMS.update(copy.deepcopy(FILM))
    xbmc.STREAMS['currentaudiostream'] = xbmc.STREAMS['audiostreams'][0]
    xbmcaddon.SETTINGS.update({'audio_language': str(audio), 'subtitle_mode': str(mode), 'subtitle_language': str(sub_lang)})
    del xbmc.RPC[:]
    languages.apply()
    calls = [json.loads(q) for q in xbmc.RPC]
    return ([c['params'] for c in calls if c['method'] == 'Player.SetAudioStream'],
            [c['params'] for c in calls if c['method'] == 'Player.SetSubtitle'])


aud, sub = lang_run(0, 0)
check(not aud and not sub, 'language: Kodi defaults leave streams alone')
aud, sub = lang_run(1, 1)
check(aud == [{'playerid': 1, 'stream': 1}] and sub == [{'playerid': 1, 'subtitle': 'off'}],
      'language: French audio found by the VFF tag, commentary skipped, subtitles off')
aud, sub = lang_run(2, 2, 1)
check(not aud and sub == [{'playerid': 1, 'subtitle': 0, 'enable': True}], 'language: English kept, French subtitles always')
aud, sub = lang_run(2, 3, 1)
check(sub == [{'playerid': 1, 'subtitle': 1, 'enable': True}], 'language: full subtitles when the audio is foreign')
aud, sub = lang_run(1, 3, 1)
check(sub == [{'playerid': 1, 'subtitle': 'off'}], 'language: no subtitles when the audio is already French')
aud, sub = lang_run(1, 4, 1)
check(sub == [{'playerid': 1, 'subtitle': 0, 'enable': True}], 'language: forced subtitles only')
aud, sub = lang_run(4, 4, 4)
check(not aud and sub == [{'playerid': 1, 'subtitle': 'off'}], 'language: missing language changes nothing, no forced track -> off')
xbmc.STREAMS.clear()

print('ALL %d CHECKS PASSED' % OK[0])
errors = [m for lvl, m in xbmc.LOG if lvl >= 3]
print('kodi errors logged:', errors)
shutil.rmtree(ROOT)
