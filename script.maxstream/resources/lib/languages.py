# -*- coding: utf-8 -*-
"""Audio / subtitle language preferences, applied when a MaxStream video starts.

Kodi exposes the streams of the playing video through JSON-RPC
(Player.GetProperties: audiostreams, subtitles) with an ISO 639 code and a
name; IPTV files often only carry tags such as "VFF", "VOSTFR" or "English"
in the name, so both are checked."""
import json
import re

import xbmc

from . import common
from .common import get_int, log

# index used in settings.xml -> (ISO 639 codes, words found in stream names)
LANGS = {
    1: ({'fr', 'fre', 'fra'}, ('french', 'francais', 'français', 'vff', 'vfq', 'vfi', 'truefrench', 'vf')),
    2: ({'en', 'eng'}, ('english', 'anglais')),
    3: ({'nl', 'dut', 'nld'}, ('dutch', 'nederlands', 'flemish', 'vlaams', 'néerlandais')),
    4: ({'de', 'ger', 'deu'}, ('german', 'deutsch', 'allemand')),
    5: ({'es', 'spa'}, ('spanish', 'español', 'espanol', 'castellano', 'espagnol')),
    6: ({'it', 'ita'}, ('italian', 'italiano', 'italien')),
    7: ({'ar', 'ara'}, ('arabic', 'arabe')),
    8: ({'pt', 'por'}, ('portuguese', 'português', 'portugais')),
    9: ({'tr', 'tur'}, ('turkish', 'türkçe', 'turc')),
}
SUB_KODI, SUB_OFF, SUB_ALWAYS, SUB_FOREIGN, SUB_FORCED = 0, 1, 2, 3, 4
SKIP_WORDS = ('commentary', 'commentaire', 'audio description', 'audiodescription', 'description audio')


def rpc(method, **params):
    try:
        return json.loads(xbmc.executeJSONRPC(json.dumps(
            {'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}))).get('result')
    except (TypeError, ValueError):
        return None


def matches(stream, lang):
    if lang not in LANGS:
        return False
    codes, words = LANGS[lang]
    code = (stream.get('language') or '').lower().split('-')[0]
    if code in codes:
        return True
    name = (stream.get('name') or '').lower()
    tokens = set(re.split(r'[^\wçéèêäöüñ]+', name))
    return any((w in tokens) if len(w) <= 4 else (w in name) for w in words)


def pick(streams, lang, forced=None):
    found = [s for s in streams if matches(s, lang)]
    if forced is not None:
        found = [s for s in found if bool(s.get('isforced')) == forced or
                 (forced and 'forc' in (s.get('name') or '').lower())]
    clean = [s for s in found if not any(w in (s.get('name') or '').lower() for w in SKIP_WORDS)]
    best = (clean or found)
    return best[0] if best else None


def video_player_id():
    for player in rpc('Player.GetActivePlayers') or []:
        if player.get('type') == 'video':
            return player.get('playerid')
    return None


def apply():
    """Select audio / subtitle streams according to the MaxStream settings."""
    common.reload_addon()  # the service is long-running: pick up changed settings
    audio_pref = get_int('audio_language', 0)
    sub_mode = get_int('subtitle_mode', SUB_KODI)
    sub_lang = get_int('subtitle_language', 1)
    if not audio_pref and sub_mode == SUB_KODI:
        return
    pid = video_player_id()
    if pid is None:
        return
    props = rpc('Player.GetProperties', playerid=pid,
                properties=['audiostreams', 'currentaudiostream', 'subtitles']) or {}
    audios = props.get('audiostreams') or []
    current = props.get('currentaudiostream') or {}
    if audio_pref and audios:
        chosen = pick(audios, audio_pref)
        if chosen and chosen.get('index') != current.get('index'):
            rpc('Player.SetAudioStream', playerid=pid, stream=chosen['index'])
            log('languages: audio stream %s (%s)' % (chosen.get('index'), chosen.get('language')), xbmc.LOGINFO)
        current = chosen or current
    if sub_mode == SUB_KODI:
        return
    subs = props.get('subtitles') or []
    target = None
    if sub_mode == SUB_ALWAYS:
        target = pick(subs, sub_lang)
    elif sub_mode == SUB_FOREIGN:
        if not matches(current, sub_lang):
            target = pick(subs, sub_lang, forced=False) or pick(subs, sub_lang)
    elif sub_mode == SUB_FORCED:
        target = pick(subs, sub_lang, forced=True)
    if target is not None:
        rpc('Player.SetSubtitle', playerid=pid, subtitle=target['index'], enable=True)
        log('languages: subtitle %s (%s)' % (target.get('index'), target.get('language')), xbmc.LOGINFO)
    else:
        rpc('Player.SetSubtitle', playerid=pid, subtitle='off')
