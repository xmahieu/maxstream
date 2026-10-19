# -*- coding: utf-8 -*-
"""Shared pieces of the graphical interface: session, window factory, item builders."""
import re
import threading
import time

import xbmc
import xbmcgui

from .. import net, storage, ui
from ..common import ADDON_PATH, L, fmt_duration, fmt_time, fold, log_error, notify
from ..provider import get_provider

ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN = 1, 2, 3, 4
ACTION_PAGE_UP, ACTION_PAGE_DOWN = 5, 6
BACK_ACTIONS = (9, 10, 92)  # parent dir, previous menu, back
MOVE_ACTIONS = (1, 2, 3, 4, 5, 6, 104, 105, 159, 160)
CONTEXT_ACTIONS = (117,)


def create(cls, **attrs):
    """Instantiate a window from its XML and set attributes before showing it."""
    win = cls(cls.XML, ADDON_PATH, 'Default', '1080i')
    for key, value in attrs.items():
        setattr(win, key, value)
    return win


class Busy(object):
    def __enter__(self):
        xbmc.executebuiltin('ActivateWindow(busydialognocancel)')
        return self

    def __exit__(self, *exc):
        xbmc.executebuiltin('Dialog.Close(busydialognocancel,true)')
        return False


class Session(object):
    """Active playlist + provider, shared by all windows."""

    def __init__(self):
        self.lock = threading.RLock()
        self.pl = None
        self.prov = None
        self.reload()

    def reload(self):
        self.pl = storage.active_playlist()
        self.prov = get_provider(self.pl) if self.pl else None

    def favourites(self):
        return storage.favourites(self.pl['id'])

    def resume(self):
        return storage.Resume(self.pl['id'])

    def safe(self, func, *args, **kwargs):
        """Run a provider call; on network error notify and return None."""
        try:
            with self.lock:
                return func(*args, **kwargs)
        except net.NetError as err:
            log_error('provider error: %s' % err)
            notify(L(30041) % err)
            return None


SESSION = Session()


def initials(name):
    words = [w for w in (name or '').replace('|', ' ').split() if w[:1].isalnum()]
    return ''.join(w[0] for w in words[:2]).upper() or '?'


def set_progress(li, pos, total):
    if total and total > 0 and pos > 0:
        li.getVideoInfoTag().setResumePoint(float(pos), float(total))


def channel_item(ch, progs=None, fav=False):
    li = xbmcgui.ListItem(label=ch.get('name') or '', offscreen=True)
    if ch.get('icon'):
        li.setArt({'thumb': ch['icon'], 'icon': ch['icon']})
    li.setProperty('num', str(ch.get('num') or ''))
    li.setProperty('initials', initials(ch.get('name')))
    li.setProperty('catchup', '1' if ch.get('catchup') else '')
    li.setProperty('fav', '1' if fav else '')
    if progs:
        now = time.time()
        cur = progs[0]
        if cur['start'] <= now < cur['stop']:
            li.setProperty('now', '%s  %s' % (fmt_time(cur['start']), cur['title']))
            set_progress(li, now - cur['start'], cur['stop'] - cur['start'])
    return li


def poster_item(kind, item, resume_state=None, is_new=False):
    li = xbmcgui.ListItem(label=item.get('name') or item.get('title') or '', offscreen=True)
    art = item.get('icon') or ''
    if art:
        li.setArt({'poster': art, 'thumb': art, 'icon': art})
    meta = []
    if item.get('year'):
        meta.append(str(item['year']))
    if kind == 'series' and item.get('genre'):
        meta.append(item['genre'].split(',')[0])
    if kind == 'live':
        meta.append(L(30000))
    li.setLabel2(' · '.join(meta))
    if item.get('rating'):
        li.setProperty('rating', '%.1f' % float(item['rating']))
    li.setProperty('new', '1' if is_new else '')
    if resume_state and resume_state.get('pos'):
        set_progress(li, resume_state['pos'], resume_state.get('total', 0))
    return li


EP_CODE_RE = re.compile(r'\b[Ss]\d{1,2}\s*[Ee]\d{1,4}\b|\b\d{1,2}x\d{1,3}\b')


def episode_title(ep):
    """'The Show - S01E02 - The Title' -> 'The Title' ; nothing left -> 'Episode 2'."""
    title = ep.get('title') or ''
    show = ep.get('show') or ''
    if show and fold(title).startswith(fold(show)):
        title = title[len(show):]
    title = EP_CODE_RE.sub(' ', title)
    title = re.sub(r'^[\s\-|:._]+|[\s\-|:._]+$', '', re.sub(r'\s{2,}', ' ', title))
    return title or (L(30540) % (ep.get('episode') or 0))


def episode_item(ep, resume_state=None):
    li = xbmcgui.ListItem(label=episode_title(ep), offscreen=True)
    li.setProperty('epnum', '%02d' % (ep.get('episode') or 0))
    if ep.get('icon'):
        li.setArt({'thumb': ep['icon'], 'icon': ep['icon']})
    if resume_state and resume_state.get('pos'):
        set_progress(li, resume_state['pos'], resume_state.get('total', 0))
    return li


def continue_item(entry, state):
    item = entry['item']
    kind = entry['kind']
    if kind == 'episode':
        label = '%s S%02dE%02d' % (item.get('show') or '', item.get('season') or 0, item.get('episode') or 0)
        meta = L(30515) % fmt_duration(state['total'] - state['pos'])
    else:
        label = item.get('name') or ''
        meta = L(30514) % fmt_duration(state['total'] - state['pos'])
    li = xbmcgui.ListItem(label=label, label2=meta, offscreen=True)
    if item.get('icon'):
        li.setArt({'thumb': item['icon']})
    set_progress(li, state['pos'], state['total'])
    return li


def continue_entries(session):
    resume = session.resume()
    out = []
    for entry in storage.history(session.pl['id']).all():
        if entry['kind'] not in ('movie', 'episode'):
            continue
        state = resume.get(storage.item_key(entry['kind'], entry['item']['id']))
        if state and state.get('pos') and not state.get('watched'):
            out.append((entry, state))
    return out


def adult_filter(prov, kind, items):
    if not ui.parental_enabled() or ui.is_unlocked():
        return items
    adult = set(c['id'] for c in prov.categories(kind) if ui.is_adult(c['name']))
    return [i for i in items if i.get('cat') not in adult] if adult else items


def hidden_ids(session, kind):
    return set(c[0] for c in storage.hidden_categories(session.pl['id']).data[kind])


def fill(control, items, select=0):
    control.reset()
    if items:
        control.addItems(items)
        control.selectItem(max(0, min(select, len(items) - 1)))
