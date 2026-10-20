# -*- coding: utf-8 -*-
"""Live TV screen: categories | channels | preview + programme info.
OK once on a channel starts the preview, OK again goes fullscreen."""
import threading
import time

import xbmc
import xbmcgui

from .. import actions, playback, storage, ui
from ..playback import stop_playback
from ..common import L, fmt_time, get_bool
from .base import (BACK_ACTIONS, CONTEXT_ACTIONS, MOVE_ACTIONS, SESSION, Busy, adult_filter, channel_item, create,
                   fill, hidden_ids)
from .guide import GuideDialog

BACK, SEARCH, CATS, CHANNELS = 90, 91, 100, 200
BTN_FULL, BTN_GUIDE, BTN_REPLAY, BTN_FAV, PROGRESS = 301, 302, 303, 304, 410


class LiveWindow(xbmcgui.WindowXML):
    XML = 'script-maxstream-live.xml'
    catchup_mode = False
    start_category = None  # 'fav' to open on favourites

    # ------------------------------------------------------------ lifecycle
    def onInit(self):  # pylint: disable=invalid-name
        if not getattr(self, '_ready', False):
            self._ready = True
            self.player = xbmc.Player()
            self.preview_id = None
            self.cats, self.channels, self.epg = [], [], {}
            self.cat_index = -1
            self._timer = None
            self.setProperty('title', L(30003) if self.catchup_mode else L(30000))
            with Busy():
                self.load_categories()
            start = 0
            if self.start_category:
                start = next((i for i, c in enumerate(self.cats) if c['id'] == self.start_category), 0)
            fill(self.getControl(CATS), self.cat_items(), start)
            self.select_category(start)
            self.setFocusId(CHANNELS if self.channels else CATS)
        else:
            # back from fullscreen / another window: redraw from memory
            fill(self.getControl(CATS), self.cat_items(), self.cat_index)
            pos = self.getControl(CHANNELS).getSelectedPosition() if self.channels else 0
            self.render_channels(max(0, pos))

    def close_window(self):
        if self._timer:
            self._timer.cancel()
        if self.preview_id and self.player.isPlaying():
            stop_playback(self.player)
        self.close()

    # ------------------------------------------------------------ categories
    def load_categories(self):
        session = SESSION
        prov = session.prov
        all_live = session.safe(prov.all_items, 'live') or []
        if self.catchup_mode:
            all_live = [c for c in all_live if c.get('catchup')]
        hidden = hidden_ids(session, 'live')
        counts = {}
        for ch in all_live:
            counts[ch.get('cat')] = counts.get(ch.get('cat'), 0) + 1
        cats = [{'id': 'all', 'name': L(30011), 'count': len(all_live)}]
        if not self.catchup_mode:
            favs = session.favourites().all('live')
            recent = storage.history(session.pl['id']).all('live')
            cats.append({'id': 'fav', 'name': L(30004), 'count': len(favs)})
            cats.append({'id': 'recent', 'name': L(30005), 'count': len(recent)})
        for cat in session.safe(prov.categories, 'live') or []:
            if not counts.get(cat['id']) or cat['id'] in hidden:
                continue
            if ui.is_adult(cat['name']) and ui.hide_locked():
                continue
            cats.append({'id': cat['id'], 'name': cat['name'], 'count': counts[cat['id']]})
        self.all_live = all_live
        self.cats = cats

    def cat_items(self):
        items = []
        for cat in self.cats:
            label = cat['name']
            if ui.is_adult(cat['name']) and not ui.is_unlocked():
                label = '%s  [%s]' % (label, L(30078))
            items.append(xbmcgui.ListItem(label=label, label2=str(cat.get('count', '')), offscreen=True))
        return items

    def channels_for(self, cat):
        session = SESSION
        if cat['id'] == 'all':
            return adult_filter(session.prov, 'live', self.all_live)
        if cat['id'] == 'fav':
            return [e['item'] for e in session.favourites().all('live')]
        if cat['id'] == 'recent':
            return [e['item'] for e in storage.history(session.pl['id']).all('live')]
        if cat['id'] == 'search':
            return cat['items']
        return [c for c in self.all_live if c.get('cat') == cat['id']]

    def select_category(self, index, interactive=False):
        if index < 0 or index >= len(self.cats):
            return
        cat = self.cats[index]
        self.cat_index = index
        if ui.is_adult(cat['name']) and not ui.is_unlocked():
            if not interactive or not ui.unlock(cat['name']):
                self.channels = []
                self.render_channels(0, empty=L(30527))
                return
            fill(self.getControl(CATS), self.cat_items(), index)
        self.channels = self.channels_for(cat)
        self.load_epg()
        self.render_channels(0)

    def schedule_category(self):
        """Debounced category change while the user scrolls the category list."""
        if self._timer:
            self._timer.cancel()
        index = self.getControl(CATS).getSelectedPosition()
        if index == self.cat_index:
            return
        self._timer = threading.Timer(0.35, self.select_category, [index])
        self._timer.start()

    # ------------------------------------------------------------ channels
    def load_epg(self):
        self.epg = {}
        if not get_bool('epg_enabled', True):
            return
        store = SESSION.prov.epg
        if not store.exists():
            return
        ids = dict((ch['id'], store.resolve(ch.get('epg_id'), ch.get('name'))) for ch in self.channels)
        data = store.now_next([v for v in ids.values() if v], limit=3)
        self.epg = dict((cid, data.get(eid) or []) for cid, eid in ids.items())

    def render_channels(self, select=0, empty=None):
        favs = SESSION.favourites().keys()
        items = [channel_item(ch, self.epg.get(ch['id']), storage.item_key('live', ch['id']) in favs)
                 for ch in self.channels]
        fill(self.getControl(CHANNELS), items, select)
        self.setProperty('empty_text', empty or ('' if items else L(30528)))
        self.update_info()

    def selected_channel(self):
        if not self.channels:
            return None
        pos = self.getControl(CHANNELS).getSelectedPosition()
        return self.channels[pos] if 0 <= pos < len(self.channels) else None

    def update_info(self):
        ch = self.selected_channel()
        keys = ('sel_logo', 'sel_numname', 'sel_now', 'sel_time', 'sel_desc', 'sel_next1', 'sel_next2',
                'sel_catchup', 'sel_fav')
        if ch is None:
            for key in keys:
                self.setProperty(key, '')
            self.getControl(PROGRESS).setPercent(0)
            return
        self.setProperty('sel_logo', ch.get('icon') or '')
        self.setProperty('sel_numname', '%s · %s' % (ch.get('num') or '', ch['name']) if ch.get('num') else ch['name'])
        self.setProperty('sel_catchup', '1' if ch.get('catchup') else '')
        self.setProperty('sel_fav', '1' if SESSION.favourites().contains('live', ch['id']) else '')
        progs = self.epg.get(ch['id']) or []
        now = time.time()
        cur = progs[0] if progs and progs[0]['start'] <= now < progs[0]['stop'] else None
        upcoming = [p for p in progs if p['start'] > now][:2]
        self.setProperty('sel_now', cur['title'] if cur else ch['name'])
        self.setProperty('sel_time', '%s - %s' % (fmt_time(cur['start']), fmt_time(cur['stop'])) if cur else '')
        self.setProperty('sel_desc', (cur or {}).get('desc') or '')
        for idx in range(2):
            prog = upcoming[idx] if idx < len(upcoming) else None
            self.setProperty('sel_next%d' % (idx + 1), '%s     %s' % (fmt_time(prog['start']), prog['title']) if prog else '')
        pct = (now - cur['start']) * 100.0 / max(1, cur['stop'] - cur['start']) if cur else 0
        self.getControl(PROGRESS).setPercent(pct)

    # ------------------------------------------------------------ actions
    def play(self, ch, fullscreen):
        if self.preview_id == ch['id'] and self.player.isPlayingVideo():
            if fullscreen:
                xbmc.executebuiltin('ActivateWindow(fullscreenvideo)')
            return
        li = SESSION.safe(playback.build, SESSION.pl, SESSION.prov, 'live', ch)
        if li is None:
            return
        playback.start(li, windowed=not fullscreen)
        self.preview_id = ch['id']

    def open_guide(self, ch, catchup=False):
        dialog = create(GuideDialog, channel=ch, catchup=catchup)
        dialog.doModal()
        del dialog

    def toggle_fav(self, ch):
        favs = SESSION.favourites()
        if favs.contains('live', ch['id']):
            favs.remove('live', ch['id'])
        else:
            favs.add('live', ch, front=False)
        pos = self.getControl(CHANNELS).getSelectedPosition()
        if self.cats[self.cat_index]['id'] == 'fav':
            self.channels = self.channels_for(self.cats[self.cat_index])
        self.render_channels(pos)

    def search(self):
        query = xbmcgui.Dialog().input(L(30504)).strip()
        if not query:
            return
        results = adult_filter(SESSION.prov, 'live', SESSION.prov.search('live', query))
        if self.catchup_mode:
            results = [c for c in results if c.get('catchup')]
        self.cats = [c for c in self.cats if c['id'] != 'search']
        self.cats.insert(0, {'id': 'search', 'name': L(30071) % query, 'count': len(results), 'items': results})
        fill(self.getControl(CATS), self.cat_items(), 0)
        self.select_category(0)
        self.setFocusId(CHANNELS if results else CATS)

    def context_menu(self):
        ch = self.selected_channel()
        if ch is None:
            return
        fav = SESSION.favourites().contains('live', ch['id'])
        entries = [(L(30017) if fav else L(30016), lambda: self.toggle_fav(ch)),
                   (L(30015), lambda: self.open_guide(ch))]
        if ch.get('catchup'):
            entries.append((L(30003), lambda: self.open_guide(ch, True)))
        idx = xbmcgui.Dialog().contextmenu([e[0] for e in entries])
        if idx >= 0:
            entries[idx][1]()

    def category_menu(self):
        cat = self.cats[self.getControl(CATS).getSelectedPosition()]
        if cat['id'] in ('all', 'fav', 'recent', 'search'):
            return
        if xbmcgui.Dialog().contextmenu([L(30018)]) == 0:
            actions.hide_category('live', cat['id'], cat['name'])
            self.cats.remove(cat)
            fill(self.getControl(CATS), self.cat_items(), 0)
            self.select_category(0)

    # ------------------------------------------------------------ events
    def onAction(self, action):  # pylint: disable=invalid-name
        action_id = action.getId()
        focus = self.getFocusId()
        if action_id in BACK_ACTIONS:
            self.close_window()
        elif action_id in CONTEXT_ACTIONS:
            if focus == CHANNELS:
                self.context_menu()
            elif focus == CATS:
                self.category_menu()
        elif action_id in MOVE_ACTIONS:
            if focus == CATS:
                self.schedule_category()
            elif focus == CHANNELS:
                self.update_info()

    def onClick(self, control_id):  # pylint: disable=invalid-name
        if control_id == BACK:
            self.close_window()
        elif control_id == SEARCH:
            self.search()
        elif control_id == CATS:
            if self._timer:
                self._timer.cancel()
            index = self.getControl(CATS).getSelectedPosition()
            if index != self.cat_index or not self.channels:
                self.select_category(index, interactive=True)
            if self.channels:
                self.setFocusId(CHANNELS)
        else:
            ch = self.selected_channel()
            if ch is None:
                return
            if control_id == CHANNELS:
                if self.catchup_mode:
                    self.open_guide(ch, catchup=True)
                else:
                    self.play(ch, fullscreen=self.preview_id == ch['id'])
            elif control_id == BTN_FULL:
                self.play(ch, fullscreen=True)
            elif control_id == BTN_GUIDE:
                self.open_guide(ch)
            elif control_id == BTN_REPLAY:
                self.open_guide(ch, catchup=True)
            elif control_id == BTN_FAV:
                self.toggle_fav(ch)
