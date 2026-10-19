# -*- coding: utf-8 -*-
"""Movie page (backdrop, poster, synopsis, resume/play/trailer/favourite, related)
and series page (same header + season tabs + episodes)."""
import xbmc
import xbmcgui

from .. import playback, storage
from ..common import L, fmt_duration, has_addon, notify
from .base import BACK_ACTIONS, MOVE_ACTIONS, SESSION, Busy, episode_item, fill, poster_item

BACK, BTN_PLAY, BTN_START, BTN_TRAILER, BTN_FAV, PROGRESS = 90, 301, 302, 303, 304, 410
SEASONS, RELATED, EPISODES = 400, 500, 510


def duration_text(seconds):
    seconds = int(seconds or 0)
    if not seconds:
        return ''
    hours, minutes = seconds // 3600, (seconds % 3600) // 60
    return '%d h %02d' % (hours, minutes) if hours else '%d min' % minutes


class DetailWindow(xbmcgui.WindowXML):
    XML = 'script-maxstream-detail.xml'
    kind = 'movie'
    item = None
    siblings = ()

    def onInit(self):  # pylint: disable=invalid-name
        if not getattr(self, '_ready', False):
            self._ready = True
            self.season_index = 0
            with Busy():
                self.load()
        self.render()
        self.setFocusId(BTN_PLAY)

    # ------------------------------------------------------------ data
    def load(self):
        session = SESSION
        if self.kind == 'movie':
            self.detail = session.safe(session.prov.movie_detail, self.item['id']) or {}
            self.seasons, self.episodes = [], {}
        else:
            self.detail = session.safe(session.prov.series_detail, self.item['id']) or {
                'info': {}, 'seasons': [], 'episodes': {}}
            self.seasons = self.detail.get('seasons') or []
            self.episodes = self.detail.get('episodes') or {}
            self.detail = dict(self.detail.get('info') or {})

    def season_eps(self, index=None):
        index = self.season_index if index is None else index
        if not self.seasons:
            return []
        num = self.seasons[index]['num']
        return self.episodes.get(num) or self.episodes.get(str(num)) or []

    def next_episode(self):
        """(season index, episode, resume state) to start with."""
        resume = SESSION.resume()
        fallback = None
        for s_idx in range(len(self.seasons)):
            for ep in self.season_eps(s_idx):
                state = resume.get(storage.item_key('episode', ep['id']))
                if state and state.get('pos') and not state.get('watched'):
                    return s_idx, ep, state
                if fallback is None and not (state and state.get('watched')):
                    fallback = (s_idx, ep, None)
        if fallback:
            return fallback
        eps = self.season_eps(0)
        return (0, eps[0], None) if eps else (0, None, None)

    # ------------------------------------------------------------ view
    def render(self):
        item, det = self.item, self.detail
        title = det.get('name') or item.get('name') or ''
        self.setProperty('mode', self.kind)
        self.setProperty('title', title)
        self.setProperty('crumb', '%s  ›  %s' % (L(30001 if self.kind == 'movie' else 30002), title))
        self.setProperty('poster', det.get('icon') or item.get('icon') or '')
        self.setProperty('fanart', det.get('backdrop') or item.get('backdrop') or '')
        meta = []
        rating = det.get('rating') or item.get('rating')
        if rating:
            meta.append('[COLOR FFFFD58A][B]★ %.1f[/B][/COLOR]' % float(rating))
        year = det.get('year') or item.get('year')
        if year:
            meta.append(str(year))
        if det.get('duration'):
            meta.append(duration_text(det['duration']))
        genre = det.get('genre') or item.get('genre')
        if genre:
            meta.append(genre)
        if self.kind == 'series' and self.seasons:
            meta.append('%d %s' % (len(self.seasons), L(30533).lower()))
        self.setProperty('meta', '   •   '.join(meta))
        self.setProperty('plot', det.get('plot') or item.get('plot') or '')
        self.setProperty('director_line', '[COLOR FFA9B8D0]%s[/COLOR]   %s' % (L(30610), det['director'])
                         if det.get('director') else '')
        self.setProperty('cast_line', '[COLOR FFA9B8D0]%s[/COLOR]   %s' % (L(30611), det['cast']) if det.get('cast') else '')
        self.setProperty('fav', '1' if SESSION.favourites().contains(self.kind, item['id']) else '')
        self.setProperty('has_trailer', '1' if self.kind == 'movie' and det.get('trailer') else '')
        if self.kind == 'movie':
            self.render_movie()
        else:
            self.render_series()
        self.chain_buttons()

    def render_movie(self):
        state = playback.resume_state(SESSION.pl, 'movie', self.item)
        if state:
            pct = 100.0 * state['pos'] / max(1, state['total'])
            self.setProperty('has_resume', '1')
            self.setProperty('btn_play', L(30518) % fmt_duration(state['pos']))
            self.setProperty('resume_text', L(30516) % ('%d %%' % pct))
            self.setProperty('resume_left', L(30517) % fmt_duration(state['total'] - state['pos']))
            self.getControl(PROGRESS).setPercent(pct)
        else:
            self.setProperty('has_resume', '')
            self.setProperty('btn_play', L(30510))
        self.setProperty('bottom_title', L(30513) if self.siblings else '')
        resume = SESSION.resume()
        fill(self.getControl(RELATED), [poster_item('movie', s, resume.get(storage.item_key('movie', s['id'])))
                                        for s in self.siblings])

    def render_series(self):
        self.setProperty('has_resume', '')
        self.setProperty('bottom_title', '')
        s_idx, ep, state = self.next_episode() if self.seasons else (0, None, None)
        if ep is None:
            self.setProperty('btn_play', L(30510))
        else:
            code = 'S%02dE%02d' % (ep.get('season') or 0, ep.get('episode') or 0)
            self.setProperty('btn_play', (L(30520) if state else L(30519)) % code)
        self.play_target = ep
        seasons = [xbmcgui.ListItem(label=s.get('name') or (L(30022) % s['num']), offscreen=True) for s in self.seasons]
        if not getattr(self, '_season_chosen', False):
            self.season_index = s_idx
        fill(self.getControl(SEASONS), seasons, self.season_index)
        self.render_episodes()

    def render_episodes(self, select=0):
        resume = SESSION.resume()
        eps = self.season_eps()
        if self.play_target is not None and select == 0:
            select = next((i for i, e in enumerate(eps) if e['id'] == self.play_target['id']), 0)
        fill(self.getControl(EPISODES), [episode_item(e, resume.get(storage.item_key('episode', e['id']))) for e in eps],
             select)

    def chain_buttons(self):
        """Link visible buttons left/right and down to the bottom row."""
        order = [BTN_PLAY, BTN_FAV]
        if self.kind == 'movie' and self.getProperty('has_resume') == '1':
            order.append(BTN_START)
        if self.getProperty('has_trailer') == '1':
            order.append(BTN_TRAILER)
        controls = [self.getControl(cid) for cid in order]
        bottom = self.getControl(RELATED if self.kind == 'movie' else SEASONS)
        for idx, ctrl in enumerate(controls):
            if idx > 0:
                ctrl.controlLeft(controls[idx - 1])
            if idx < len(controls) - 1:
                ctrl.controlRight(controls[idx + 1])
            ctrl.controlDown(bottom)

    # ------------------------------------------------------------ actions
    def play_movie(self, from_start=False):
        state = playback.resume_state(SESSION.pl, 'movie', self.item)
        seek = 0 if from_start or not state else state['pos']
        li = SESSION.safe(playback.build, SESSION.pl, SESSION.prov, 'movie', self.item, seek)
        if li is not None:
            playback.start(li)

    def play_episode(self, ep, ask=True):
        ep = dict(ep)
        ep.setdefault('show', self.detail.get('name') or self.item.get('name'))
        ep.setdefault('icon', self.item.get('icon'))
        li = SESSION.safe(playback.build, SESSION.pl, SESSION.prov, 'episode', ep, None if ask else 0)
        if li is not None:
            playback.start(li)

    def play_trailer(self):
        trailer = self.detail.get('trailer')
        if not trailer or not has_addon('plugin.video.youtube'):
            notify(L(30531))
            return
        xbmc.Player().play('plugin://plugin.video.youtube/play/?video_id=%s' % trailer)

    def toggle_fav(self):
        favs = SESSION.favourites()
        if favs.contains(self.kind, self.item['id']):
            favs.remove(self.kind, self.item['id'])
            self.setProperty('fav', '')
        else:
            favs.add(self.kind, playback.slim(self.item), front=False)
            self.setProperty('fav', '1')

    def onAction(self, action):  # pylint: disable=invalid-name
        if action.getId() in BACK_ACTIONS:
            self.close()
        elif action.getId() in MOVE_ACTIONS and self.getFocusId() == SEASONS:
            self.select_season(self.getControl(SEASONS).getSelectedPosition())

    def select_season(self, index):
        if 0 <= index < len(self.seasons) and index != self.season_index:
            self.season_index = index
            self._season_chosen = True
            self.render_episodes(-1)

    def onClick(self, control_id):  # pylint: disable=invalid-name
        if control_id == BACK:
            self.close()
        elif control_id == BTN_PLAY:
            if self.kind == 'movie':
                self.play_movie()
            elif self.play_target is not None:
                state = SESSION.resume().get(storage.item_key('episode', self.play_target['id']))
                self.play_episode(self.play_target, ask=False) if not state else self._resume_episode(state)
        elif control_id == BTN_START:
            self.play_movie(from_start=True)
        elif control_id == BTN_TRAILER:
            self.play_trailer()
        elif control_id == BTN_FAV:
            self.toggle_fav()
        elif control_id == SEASONS:
            self.select_season(self.getControl(SEASONS).getSelectedPosition())
            if self.season_eps():
                self.setFocusId(EPISODES)
        elif control_id == EPISODES:
            eps = self.season_eps()
            pos = self.getControl(EPISODES).getSelectedPosition()
            if 0 <= pos < len(eps):
                self.play_episode(eps[pos])
        elif control_id == RELATED:
            pos = self.getControl(RELATED).getSelectedPosition()
            if 0 <= pos < len(self.siblings):
                current = self.item
                self.item = self.siblings[pos]
                self.siblings = [s for s in self.siblings if s['id'] != self.item['id']] + [current]
                with Busy():
                    self.load()
                self.render()
                self.setFocusId(BTN_PLAY)

    def _resume_episode(self, state):
        ep = dict(self.play_target)
        ep.setdefault('show', self.detail.get('name') or self.item.get('name'))
        li = SESSION.safe(playback.build, SESSION.pl, SESSION.prov, 'episode', ep, state['pos'])
        if li is not None:
            playback.start(li)
