# -*- coding: utf-8 -*-
"""Content providers. Both expose the same normalised API so the UI does not
care whether the playlist is an Xtream Codes account or an M3U playlist.

Normalised items
  live   : id, name, icon, cat, epg_id, num, catchup, catchup_days, added
  movie  : id, name, icon, cat, rating, added, year, ext, plot
  series : id, name, icon, cat, rating, added, year, plot, genre, backdrop
  episode: id, title, season, episode, icon, plot, duration, rating, ext, show, sid
"""
import base64
import math
import re
import time
from datetime import datetime
from urllib.parse import parse_qs, quote, urlencode, urlparse

import xbmcvfs

from . import m3u, net
from .common import fold, get_int, safe_float, safe_int
from .epg import EPGStore
from .storage import Cache

KINDS = ('live', 'movie', 'series')


def normalize_server(url):
    url = (url or '').strip()
    if not re.match(r'^https?://', url, re.I):
        url = 'http://' + url
    url = re.sub(r'/(player_api|get|xmltv|panel_api)\.php.*$', '', url, flags=re.I)
    return url.rstrip('/')


def parse_xtream_link(url):
    """http://host:port/get.php?username=u&password=p&type=m3u_plus -> (server, user, pass)"""
    parsed = urlparse((url or '').strip())
    if not parsed.path.lower().endswith('/get.php'):
        return None
    query = parse_qs(parsed.query)
    if 'username' not in query or 'password' not in query:
        return None
    base = '%s://%s%s' % (parsed.scheme or 'http', parsed.netloc, parsed.path[:-len('/get.php')])
    return base.rstrip('/'), query['username'][0], query['password'][0]


def get_provider(playlist):
    if playlist.get('type') == 'xtream':
        return XtreamProvider(playlist)
    return M3UProvider(playlist)


def _b64(value):
    if not value:
        return ''
    try:
        return base64.b64decode(value).decode('utf-8', 'replace')
    except (ValueError, TypeError):
        return value


def _year(value):
    match = re.search(r'(19|20)\d{2}', str(value or ''))
    return int(match.group(0)) if match else 0


def _ts_from_date(value):
    try:
        return int(time.mktime(time.strptime(str(value)[:19], '%Y-%m-%d %H:%M:%S')))
    except (ValueError, TypeError):
        return safe_int(value)


class BaseProvider(object):
    kind = 'base'

    def __init__(self, playlist):
        self.pl = playlist
        self.pid = playlist['id']
        self.cache = Cache(self.pid)
        self.ttl = max(1, get_int('cache_hours', 12)) * 3600
        self._epg = None

    @property
    def epg(self):
        if self._epg is None:
            self._epg = EPGStore(self.pid)
        return self._epg

    def items(self, kind, cat=None):
        items = self.all_items(kind)
        if cat in (None, '', 'all'):
            return items
        return [i for i in items if i.get('cat') == cat]

    def category_counts(self, kind):
        counts = {}
        for item in self.all_items(kind):
            counts[item.get('cat')] = counts.get(item.get('cat'), 0) + 1
        return counts

    def search(self, kind, query, limit=500):
        words = fold(query).split()
        out = []
        for item in self.all_items(kind):
            name = fold(item.get('name'))
            if all(w in name for w in words):
                out.append(item)
                if len(out) >= limit:
                    break
        return out

    def epg_programmes(self, channel, start=None, end=None):
        cid = self.epg.resolve(channel.get('epg_id'), channel.get('name'))
        return self.epg.programmes(cid, start, end) if cid else []

    def refresh(self):
        self.cache.clear()


# ======================================================================= Xtream
class XtreamProvider(BaseProvider):
    kind = 'xtream'
    ACTIONS = {
        'live': ('get_live_categories', 'get_live_streams'),
        'movie': ('get_vod_categories', 'get_vod_streams'),
        'series': ('get_series_categories', 'get_series'),
    }

    def __init__(self, playlist):
        BaseProvider.__init__(self, playlist)
        self.server = normalize_server(playlist.get('server'))
        self.user = playlist.get('username', '')
        self.pwd = playlist.get('password', '')

    def _api(self, action=None, **params):
        query = {'username': self.user, 'password': self.pwd}
        if action:
            query['action'] = action
        query.update(params)
        return net.fetch_json('%s/player_api.php?%s' % (self.server, urlencode(query)))

    def _cached(self, key, func, ttl=None):
        data = self.cache.get(key, self.ttl if ttl is None else ttl)
        if data is None:
            data = func()
            if data is None:
                data = []
            self.cache.set(key, data)
        return data

    # ------------------------------------------------------------ account
    def account(self):
        return self._api() or {}

    def check(self):
        info = self.account()
        user = info.get('user_info') if isinstance(info, dict) else None
        if not user or str(user.get('auth', 1)) == '0':
            raise net.NetError('authentication failed')
        return info

    def account_lines(self):
        info = self.account()
        user = info.get('user_info', {}) or {}
        server = info.get('server_info', {}) or {}
        exp = user.get('exp_date')
        return {
            'username': user.get('username', self.user),
            'status': user.get('status', ''),
            'exp': datetime.fromtimestamp(int(exp)).strftime('%d/%m/%Y') if safe_int(exp) else None,
            'trial': str(user.get('is_trial', '0')) == '1',
            'active': user.get('active_cons', ''),
            'max': user.get('max_connections', ''),
            'created': datetime.fromtimestamp(int(user['created_at'])).strftime('%d/%m/%Y')
            if safe_int(user.get('created_at')) else '',
            'timezone': server.get('timezone', ''),
            'server': self.server,
        }

    # ------------------------------------------------------------ catalogue
    def categories(self, kind):
        action = self.ACTIONS[kind][0]

        def load():
            data = self._api(action) or []
            return [{'id': str(c.get('category_id')), 'name': c.get('category_name') or ''}
                    for c in data if isinstance(c, dict)]
        return self._cached('cats_' + kind, load)

    def all_items(self, kind):
        action = self.ACTIONS[kind][1]
        norm = getattr(self, '_norm_' + kind)

        def load():
            data = self._api(action) or []
            if isinstance(data, dict):
                data = list(data.values())
            return [norm(i) for i in data if isinstance(i, dict)]
        return self._cached('items_' + kind, load)

    @staticmethod
    def _norm_live(i):
        return {'id': str(i.get('stream_id')), 'name': i.get('name') or '', 'icon': i.get('stream_icon') or '',
                'cat': str(i.get('category_id')), 'epg_id': i.get('epg_channel_id') or '',
                'num': safe_int(i.get('num')), 'catchup': safe_int(i.get('tv_archive')) == 1,
                'catchup_days': safe_int(i.get('tv_archive_duration')), 'added': safe_int(i.get('added'))}

    @staticmethod
    def _norm_movie(i):
        return {'id': str(i.get('stream_id')), 'name': i.get('name') or '', 'icon': i.get('stream_icon') or '',
                'cat': str(i.get('category_id')), 'rating': safe_float(i.get('rating')),
                'added': safe_int(i.get('added')), 'year': _year(i.get('year') or i.get('name')),
                'ext': i.get('container_extension') or 'mp4', 'plot': i.get('plot') or ''}

    @staticmethod
    def _norm_series(i):
        backdrop = i.get('backdrop_path') or ''
        if isinstance(backdrop, list):
            backdrop = backdrop[0] if backdrop else ''
        return {'id': str(i.get('series_id')), 'name': i.get('name') or '', 'icon': i.get('cover') or '',
                'cat': str(i.get('category_id')), 'rating': safe_float(i.get('rating')),
                'added': safe_int(i.get('last_modified')), 'year': _year(i.get('releaseDate') or i.get('release_date')),
                'plot': i.get('plot') or '', 'genre': i.get('genre') or '', 'backdrop': backdrop}

    def series_detail(self, sid):
        raw = self._cached('series_%s' % sid, lambda: self._api('get_series_info', series_id=sid), ttl=self.ttl)
        if not isinstance(raw, dict):
            raw = {}
        info = raw.get('info') or {}
        if not isinstance(info, dict):
            info = {}
        backdrop = info.get('backdrop_path') or ''
        if isinstance(backdrop, list):
            backdrop = backdrop[0] if backdrop else ''
        show = info.get('name') or ''
        seasons_meta = {}
        for season in raw.get('seasons') or []:
            if isinstance(season, dict):
                seasons_meta[safe_int(season.get('season_number'))] = season
        episodes = {}
        groups = raw.get('episodes') or {}
        if isinstance(groups, list):
            groups = dict((str(i + 1), g) for i, g in enumerate(groups))
        for key, eps in groups.items():
            for ep in eps or []:
                ep_info = ep.get('info') if isinstance(ep.get('info'), dict) else {}
                snum = safe_int(ep.get('season'), safe_int(key))
                episodes.setdefault(snum, []).append({
                    'id': str(ep.get('id')), 'title': ep.get('title') or '', 'season': snum,
                    'episode': safe_int(ep.get('episode_num')), 'icon': ep_info.get('movie_image') or '',
                    'plot': ep_info.get('plot') or '', 'duration': safe_int(ep_info.get('duration_secs')),
                    'rating': safe_float(ep_info.get('rating')), 'ext': ep.get('container_extension') or 'mp4',
                    'show': show, 'sid': str(sid)})
        seasons = []
        for snum in sorted(episodes):
            meta = seasons_meta.get(snum, {})
            seasons.append({'num': snum, 'name': meta.get('name') or '', 'icon': meta.get('cover') or info.get('cover') or '',
                            'count': len(episodes[snum])})
            episodes[snum].sort(key=lambda e: e['episode'])
        return {'info': {'name': show, 'plot': info.get('plot') or '', 'icon': info.get('cover') or '',
                         'backdrop': backdrop, 'genre': info.get('genre') or '', 'cast': info.get('cast') or '',
                         'director': info.get('director') or '', 'rating': safe_float(info.get('rating')),
                         'year': _year(info.get('releaseDate'))},
                'seasons': seasons, 'episodes': episodes}

    def movie_detail(self, vid):
        raw = self._cached('vod_%s' % vid, lambda: self._api('get_vod_info', vod_id=vid))
        info = raw.get('info') if isinstance(raw, dict) and isinstance(raw.get('info'), dict) else {}
        backdrop = info.get('backdrop_path') or ''
        if isinstance(backdrop, list):
            backdrop = backdrop[0] if backdrop else ''
        trailer = info.get('youtube_trailer') or ''
        return {'name': info.get('name') or info.get('o_name') or '', 'plot': info.get('plot') or info.get('description') or '',
                'cast': info.get('cast') or info.get('actors') or '', 'director': info.get('director') or '',
                'genre': info.get('genre') or '', 'year': _year(info.get('releasedate') or info.get('release_date')),
                'duration': safe_int(info.get('duration_secs')), 'rating': safe_float(info.get('rating')),
                'icon': info.get('movie_image') or info.get('cover_big') or '', 'backdrop': backdrop,
                'trailer': trailer}

    # ------------------------------------------------------------ urls
    def _cred(self):
        return quote(self.user, safe=''), quote(self.pwd, safe='')

    def stream_url(self, kind, item_id, ext=None):
        user, pwd = self._cred()
        if kind == 'live':
            fmt = 'm3u8' if get_int('live_format', 0) == 1 else 'ts'
            return '%s/live/%s/%s/%s.%s' % (self.server, user, pwd, item_id, fmt)
        if kind == 'movie':
            return '%s/movie/%s/%s/%s.%s' % (self.server, user, pwd, item_id, ext or 'mp4')
        return '%s/series/%s/%s/%s.%s' % (self.server, user, pwd, item_id, ext or 'mp4')

    def epg_urls(self):
        return ['%s/xmltv.php?%s' % (self.server, urlencode({'username': self.user, 'password': self.pwd}))]

    # ------------------------------------------------------------ guide / catch-up
    def channel_programmes(self, channel):
        """Full listing for one channel (archive flags included)."""
        progs = []
        try:
            raw = self._api('get_simple_data_table', stream_id=channel['id']) or {}
            listings = raw.get('epg_listings') if isinstance(raw, dict) else None
            for p in listings or []:
                start = safe_int(p.get('start_timestamp')) or _ts_from_date(p.get('start'))
                stop = safe_int(p.get('stop_timestamp')) or _ts_from_date(p.get('end'))
                progs.append({'start': start, 'stop': stop, 'title': _b64(p.get('title')),
                              'desc': _b64(p.get('description')), 'archive': safe_int(p.get('has_archive')) == 1,
                              'server_start': p.get('start') or ''})
        except net.NetError:
            progs = []
        if not progs:
            progs = self.epg_programmes(channel)
        progs.sort(key=lambda p: p['start'])
        return progs

    def catchup_url(self, channel, start, stop, server_start=''):
        user, pwd = self._cred()
        minutes = max(1, int(math.ceil((stop - start) / 60.0)))
        if server_start:
            try:
                stamp = datetime.strptime(server_start[:19], '%Y-%m-%d %H:%M:%S').strftime('%Y-%m-%d:%H-%M')
            except ValueError:
                stamp = time.strftime('%Y-%m-%d:%H-%M', time.localtime(start))
        else:
            stamp = time.strftime('%Y-%m-%d:%H-%M', time.localtime(start))
        return '%s/timeshift/%s/%s/%d/%s/%s.ts' % (self.server, user, pwd, minutes, stamp, channel['id'])


# ======================================================================= M3U
class M3UProvider(BaseProvider):
    kind = 'm3u'

    def __init__(self, playlist):
        BaseProvider.__init__(self, playlist)
        self._db = None

    def _load_text(self):
        source = self.pl.get('m3u_url') or ''
        if self.pl.get('type') == 'm3u_file':
            handle = xbmcvfs.File(self.pl.get('m3u_path'))
            try:
                data = handle.readBytes()
            finally:
                handle.close()
            data = bytes(data)
            for enc in ('utf-8-sig', 'latin-1'):
                try:
                    return data.decode(enc)
                except UnicodeDecodeError:
                    continue
        return net.fetch_text(source, timeout=max(get_int('timeout', 20), 60))

    def db(self, force=False):
        if self._db is not None and not force:
            return self._db
        data = None if force else self.cache.get('m3u_db', self.ttl)
        if data is None:
            text = self._load_text()
            data = self.build(text)
            if not data['entries']:
                raise net.NetError('empty playlist')
            self.cache.set('m3u_db', data)
        self._db = data
        return data

    def check(self):
        return self.db(force=True)

    @staticmethod
    def build(text):
        header, entries = m3u.parse(text)
        db = {'header': header, 'entries': [], 'cats': {k: [] for k in KINDS},
              'items': {k: [] for k in KINDS}}
        cat_ids = {k: {} for k in KINDS}
        shows = {}

        def cat_for(kind, name):
            name = name or 'Uncategorised'
            mapping = cat_ids[kind]
            if name not in mapping:
                mapping[name] = 'c%d' % len(mapping)
                db['cats'][kind].append({'id': mapping[name], 'name': name})
            return mapping[name]

        def_catchup = header.get('catchup') or header.get('catchup-type') or ''
        def_source = header.get('catchup-source') or ''
        def_days = safe_int(header.get('catchup-days'))
        live_num = 0
        for idx, entry in enumerate(entries):
            attrs = entry['attrs']
            kind = m3u.classify(entry)
            db['entries'].append({'url': entry['url'], 'props': entry['props']})
            item_id = str(idx)
            icon = attrs.get('tvg-logo') or attrs.get('logo') or ''
            name = entry['name']
            if kind == 'live':
                live_num += 1
                mode = attrs.get('catchup') or attrs.get('catchup-type') or def_catchup
                source = attrs.get('catchup-source') or def_source
                days = safe_int(attrs.get('catchup-days') or attrs.get('timeshift') or attrs.get('tvg-rec')) or def_days
                db['items']['live'].append({
                    'id': item_id, 'name': name, 'icon': icon, 'cat': cat_for('live', entry['group']),
                    'epg_id': attrs.get('tvg-id') or attrs.get('tvg-name') or '', 'num': safe_int(attrs.get('tvg-chno')) or live_num,
                    'catchup': bool(mode or source or days), 'catchup_days': days or (7 if (mode or source) else 0),
                    'catchup_mode': mode, 'catchup_source': source, 'added': 0})
            elif kind == 'movie':
                db['items']['movie'].append({
                    'id': item_id, 'name': name, 'icon': icon, 'cat': cat_for('movie', entry['group']),
                    'rating': 0.0, 'added': idx, 'year': _year(name), 'ext': '', 'plot': ''})
            else:
                parts = m3u.split_episode(name) or (name, 1, 1)
                show_name, season, episode = parts
                cat = cat_for('series', entry['group'])
                key = (cat, fold(show_name))
                show = shows.get(key)
                if show is None:
                    show = {'id': 's%d' % len(shows), 'name': show_name, 'icon': icon, 'cat': cat, 'rating': 0.0,
                            'added': idx, 'year': _year(show_name), 'plot': '', 'genre': '', 'backdrop': '', 'episodes': []}
                    shows[key] = show
                    db['items']['series'].append(show)
                show['episodes'].append({'id': item_id, 'title': name, 'season': season, 'episode': episode,
                                         'icon': icon, 'plot': '', 'duration': 0, 'rating': 0.0, 'ext': '',
                                         'show': show_name, 'sid': show['id']})
                show['added'] = idx
        return db

    # ------------------------------------------------------------ catalogue
    def categories(self, kind):
        return self.db()['cats'][kind]

    def all_items(self, kind):
        return self.db()['items'][kind]

    def series_detail(self, sid):
        show = next((s for s in self.all_items('series') if s['id'] == sid), None)
        if show is None:
            return {'info': {}, 'seasons': [], 'episodes': {}}
        episodes = {}
        for ep in show['episodes']:
            episodes.setdefault(ep['season'], []).append(ep)
        seasons = []
        for snum in sorted(episodes):
            episodes[snum].sort(key=lambda e: e['episode'])
            seasons.append({'num': snum, 'name': '', 'icon': show['icon'], 'count': len(episodes[snum])})
        return {'info': {'name': show['name'], 'plot': '', 'icon': show['icon'], 'backdrop': '', 'genre': '',
                         'cast': '', 'director': '', 'rating': 0.0, 'year': show['year']},
                'seasons': seasons, 'episodes': episodes}

    def movie_detail(self, vid):
        item = next((m for m in self.all_items('movie') if m['id'] == vid), {})
        return {'name': item.get('name', ''), 'plot': '', 'cast': '', 'director': '', 'genre': '',
                'year': item.get('year', 0), 'duration': 0, 'rating': 0.0, 'icon': item.get('icon', ''),
                'backdrop': '', 'trailer': ''}

    def entry(self, item_id):
        entries = self.db()['entries']
        idx = safe_int(item_id, -1)
        return entries[idx] if 0 <= idx < len(entries) else None

    def stream_url(self, kind, item_id, ext=None):
        entry = self.entry(item_id)
        return entry['url'] if entry else None

    def kodi_props(self, item_id):
        entry = self.entry(item_id)
        return entry.get('props', []) if entry else []

    def live_item(self, item_id):
        return next((c for c in self.all_items('live') if c['id'] == item_id), None)

    def epg_urls(self):
        urls = []
        if self.pl.get('epg_url'):
            urls.append(self.pl['epg_url'])
        header = self.db()['header']
        for key in ('url-tvg', 'x-tvg-url', 'tvg-url'):
            for url in (header.get(key) or '').split(','):
                url = url.strip()
                if url and url not in urls:
                    urls.append(url)
        if not urls:
            creds = parse_xtream_link(self.pl.get('m3u_url'))
            if creds:
                urls.append('%s/xmltv.php?%s' % (creds[0], urlencode({'username': creds[1], 'password': creds[2]})))
        return urls

    def account_lines(self):
        return None

    # ------------------------------------------------------------ guide / catch-up
    def channel_programmes(self, channel):
        progs = self.epg_programmes(channel)
        if channel.get('catchup'):
            now = time.time()
            limit = now - max(1, channel.get('catchup_days') or 7) * 86400
            for p in progs:
                p['archive'] = limit <= p['start'] and p['stop'] <= now
        return progs

    def catchup_url(self, channel, start, stop, server_start=''):
        full = self.live_item(channel['id']) or channel
        url = self.stream_url('live', channel['id'])
        return build_catchup_url(url, full.get('catchup_mode', ''), full.get('catchup_source', ''), start, stop)


# ======================================================================= catch-up templates
def _fill_template(template, start, stop):
    now = int(time.time())
    duration = int(stop - start)
    values = {
        'utc': start, 'start': start, 'utcend': stop, 'end': stop, 'lutc': now, 'now': now,
        'timestamp': now, 'duration': duration, 'offset': now - start,
    }
    utc_start = time.gmtime(start)

    def fmt_date(spec, ts):
        t = time.gmtime(ts)
        out = spec
        for code in ('Y', 'm', 'd', 'H', 'M', 'S'):
            out = out.replace(code, time.strftime('%' + code, t))
        return out

    def repl(match):
        name, arg = match.group(1), match.group(2)
        if name in ('utc', 'start', 'utcend', 'end') and arg and not arg.isdigit():
            return fmt_date(arg, start if name in ('utc', 'start') else stop)
        if name in ('duration', 'offset') and arg and arg.isdigit():
            return str(values[name] // max(1, int(arg)))
        if name in values:
            return str(values[name])
        if name in ('Y', 'm', 'd', 'H', 'M', 'S'):
            return time.strftime('%' + name, utc_start)
        return match.group(0)

    return re.sub(r'\$?\{(\w+)(?::([^}]*))?\}', repl, template)


def build_catchup_url(url, mode, source, start, stop):
    base, sep, headers = url.partition('|')
    mode = (mode or '').lower()
    duration = int(stop - start)
    xc = re.match(r'^(https?://[^/]+(?:/[^/]+)*?)/(?:live/)?([^/]+)/([^/]+)/(\d+)(\.\w+)?$', base)
    if mode in ('xc',) or (not mode and not source and xc):
        if xc:
            stamp = time.strftime('%Y-%m-%d:%H-%M', time.localtime(start))
            new = '%s/timeshift/%s/%s/%d/%s/%s.ts' % (xc.group(1), xc.group(2), xc.group(3),
                                                      max(1, duration // 60), stamp, xc.group(4))
            return new + sep + headers
    if mode == 'append':
        new = base + _fill_template(source, start, stop)
    elif mode in ('shift', 'timeshift'):
        new = base + ('&' if '?' in base else '?') + 'utc=%d&lutc=%d' % (start, int(time.time()))
    elif mode in ('flussonic', 'flussonic-hls', 'flussonic-ts', 'fs'):
        if '/mpegts' in base:
            new = base.replace('/mpegts', '/timeshift_abs-%d.ts' % start, 1)
        else:
            new = re.sub(r'/([\w\-]+)\.m3u8', r'/\1-%d-%d.m3u8' % (start, duration), base, count=1)
    elif source:
        if source.startswith('http'):
            new = _fill_template(source, start, stop)
        else:
            new = base + _fill_template(source, start, stop)
    else:
        new = base + ('&' if '?' in base else '?') + 'utc=%d&lutc=%d' % (start, int(time.time()))
    return new + sep + headers
