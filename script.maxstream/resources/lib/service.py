# -*- coding: utf-8 -*-
"""Background service: resume-point tracking (continue watching) and
automatic EPG refresh for the active playlist."""
import os
import time

import xbmc

from . import common, languages, net, pvr, storage
from .stream_proxy import Relay
from .common import get_bool, log, log_error, home_prop, read_json
from .provider import get_provider

EPG_CHECK_EVERY = 15 * 60


class Player(xbmc.Player):
    def __init__(self):
        xbmc.Player.__init__(self)
        self.current = None
        self.pos = 0
        self.total = 0

    def onAVStarted(self):  # pylint: disable=invalid-name
        pending = read_json(storage.PENDING_FILE, None)
        if not pending or time.time() - pending.get('ts', 0) > 120:
            self.current = None
            return
        try:
            os.remove(storage.PENDING_FILE)
        except OSError:
            pass
        self.current = pending if pending.get('key') else None
        self.pos, self.total = 0, 0
        if pending.get('seek'):
            xbmc.sleep(300)
            try:
                self.seekTime(float(pending['seek']))
            except RuntimeError:
                pass
        try:
            xbmc.sleep(500)  # let Kodi list every audio / subtitle stream first
            languages.apply()
        except Exception as err:  # pylint: disable=broad-except
            log_error('language preferences: %r' % err)

    def poll(self):
        if self.current and self.isPlayingVideo():
            try:
                self.pos = self.getTime()
                self.total = self.getTotalTime()
            except RuntimeError:
                pass

    def _save(self):
        if not self.current:
            return
        if self.current.get('kind') in ('movie', 'episode') and self.total > 0:
            storage.Resume(self.current['pid']).update(self.current['key'], self.pos, self.total)
        self.current = None

    def onPlayBackStopped(self):  # pylint: disable=invalid-name
        self._save()

    def onPlayBackEnded(self):  # pylint: disable=invalid-name
        # Keep the last polled position: an IPTV connection that drops can make
        # Kodi end the video early, which must not mark it as watched.
        self._save()

    def onPlayBackError(self):  # pylint: disable=invalid-name
        self.current = None


def refresh_epg(force=False):
    common.reload_addon()
    if not get_bool('epg_enabled', True) and not pvr.enabled():
        return
    playlist = storage.active_playlist()
    if not playlist:
        return
    prov = get_provider(playlist)
    if not force and not prov.epg.is_stale():
        return
    try:
        urls = prov.epg_urls()
        if urls:
            count = prov.epg.update(urls, keep_first=pvr.EPG_PATH if pvr.enabled() else None)
            log('EPG refreshed: %d channels' % count, xbmc.LOGINFO)
        if pvr.enabled():
            pvr.export_m3u(playlist, prov)
    except net.NetError as err:
        log_error('EPG refresh failed: %s' % err)
    except Exception as err:  # pylint: disable=broad-except
        log_error('EPG refresh error: %r' % err)
    finally:
        prov.epg.close()


def run():
    monitor = xbmc.Monitor()
    player = Player()
    relay = Relay()
    try:
        home_prop('relay_port', str(relay.start()))
    except OSError as err:
        log_error('relay could not start: %s' % err)
        home_prop('relay_port', '')
    last_check = time.time() - EPG_CHECK_EVERY + 60  # first check one minute after start
    while not monitor.abortRequested():
        if monitor.waitForAbort(1):
            break
        player.poll()
        kicked = home_prop('epg_kick') == '1'
        if kicked or time.time() - last_check > EPG_CHECK_EVERY:
            if player.isPlaying():
                # never parse a big TV guide during playback: it competes with the stream relay
                last_check = time.time()
                continue
            home_prop('epg_kick', '')
            last_check = time.time()
            refresh_epg(force=kicked)
    relay.stop()
    home_prop('relay_port', '')
