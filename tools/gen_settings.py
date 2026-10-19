# -*- coding: utf-8 -*-
"""Generate resources/settings.xml (Kodi settings format version 1)."""
import sys

RUN = 'RunScript(script.maxstream,action=%s)'


def boolean(sid, label, default, dep=None):
    return ('<setting id="%s" type="boolean" label="%d" help=""><level>0</level><default>%s</default>'
            '<control type="toggle"/>%s</setting>' % (sid, label, 'true' if default else 'false', dep or ''))


def spinner(sid, label, default, options, dep=None):
    opts = ''.join('<option label="%d">%d</option>' % (lab, val) for val, lab in options)
    return ('<setting id="%s" type="integer" label="%d" help=""><level>0</level><default>%d</default>'
            '<constraints><options>%s</options></constraints><control type="spinner" format="string"/>%s</setting>'
            % (sid, label, default, opts, dep or ''))


def slider(sid, label, default, lo, hi, step=1, dep=None):
    return ('<setting id="%s" type="integer" label="%d" help=""><level>0</level><default>%d</default>'
            '<constraints><minimum>%d</minimum><step>%d</step><maximum>%d</maximum></constraints>'
            '<control type="slider" format="integer"><popup>false</popup></control>%s</setting>'
            % (sid, label, default, lo, step, hi, dep or ''))


def text(sid, label, default, hidden=False, dep=None):
    return ('<setting id="%s" type="string" label="%d" help=""><level>0</level><default>%s</default>'
            '<constraints><allowempty>true</allowempty></constraints>'
            '<control type="edit" format="string"><heading>%d</heading>%s</control>%s</setting>'
            % (sid, label, default, label, '<hidden>true</hidden>' if hidden else '', dep or ''))


def action(sid, label, data, dep=None):
    return ('<setting id="%s" type="action" label="%d" help=""><level>0</level><data>%s</data>'
            '<constraints><allowempty>true</allowempty></constraints>'
            '<control type="button" format="action"><close>true</close></control>%s</setting>'
            % (sid, label, data, dep or ''))


def visible_if(setting):
    return ('<dependencies><dependency type="visible"><condition operator="is" setting="%s">true</condition>'
            '</dependency></dependencies>' % setting)


def group(gid, label, *settings):
    return '<group id="%s" label="%d">%s</group>' % (gid, label, ''.join(settings))


def category(cid, label, *groups):
    return '<category id="%s" label="%d" help="">%s</category>' % (cid, label, ''.join(groups))


UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
PARENTAL = visible_if('parental_enabled')

XML = ('<?xml version="1.0" encoding="utf-8" standalone="yes"?>'
       '<settings version="1"><section id="script.maxstream">'
       + category('general', 30100,
                  group('1', 30102,
                        action('act_playlists', 30120, RUN % 'playlists'),
                        action('act_add', 30121, RUN % 'playlist_add'),
                        action('act_hidden', 30122, RUN % 'manage_hidden'),
                        action('act_donate', 30630, RUN % 'donate')),
                  group('2', 30101,
                        spinner('sort_order', 30110, 0, [(0, 30111), (1, 30112), (2, 30113), (3, 30114)]),
                        boolean('show_all', 30118, True),
                        boolean('show_numbers', 30115, False),
                        boolean('show_epg_in_list', 30116, True),
                        boolean('time_24h', 30117, True)),
                  group('3', 30103,
                        slider('cache_hours', 30125, 12, 1, 72),
                        action('act_clear_cache', 30126, RUN % 'clear_cache')))
       + category('playback', 30200,
                  group('4', 30200,
                        spinner('live_format', 30201, 0, [(0, 30202), (1, 30203)]),
                        spinner('live_inputstream', 30204, 0, [(0, 30205), (1, 30206), (2, 30207)]),
                        boolean('resume_enabled', 30210, True),
                        boolean('stream_relay', 30624, True),
                        action('act_tuning', 30621, RUN % 'optimise_playback'),
                        slider('history_size', 30211, 50, 10, 200, 10)),
                  group('5', 30215,
                        text('user_agent', 30212, UA),
                        boolean('verify_ssl', 30213, True),
                        slider('timeout', 30214, 20, 5, 120, 5)),
                  group('lang', 30640,
                        spinner('audio_language', 30641, 0, [(0, 30645)] + [(i, 30650 + i) for i in range(1, 10)]),
                        spinner('subtitle_mode', 30642, 0, [(0, 30645), (1, 30646), (2, 30647), (3, 30648), (4, 30649)]),
                        spinner('subtitle_language', 30643, 1, [(i, 30650 + i) for i in range(1, 10)])))
       + category('epg', 30300,
                  group('6', 30300,
                        boolean('epg_enabled', 30301, True),
                        slider('epg_refresh_hours', 30302, 12, 1, 48),
                        slider('epg_offset', 30303, 0, -12, 12),
                        slider('epg_days_past', 30304, 7, 1, 14),
                        slider('epg_days_future', 30305, 2, 1, 7),
                        action('act_epg', 30306, RUN % 'epg_update')))
       + category('pvr', 30600,
                  group('8', 30600,
                        boolean('pvr_sync', 30601, False),
                        boolean('pvr_exclude_locked', 30602, True, dep=visible_if('pvr_sync')),
                        action('act_pvr', 30603, RUN % 'pvr_sync')))
       + category('parental', 30400,
                  group('7', 30400,
                        boolean('parental_enabled', 30401, False),
                        text('parental_pin', 30402, '0000', hidden=True, dep=PARENTAL),
                        text('parental_keywords', 30403, 'adult,xxx,18+,+18,porn,for adults,adultes', dep=PARENTAL),
                        boolean('parental_hide', 30404, False, dep=PARENTAL),
                        action('act_lock', 30405, RUN % 'lock', dep=PARENTAL)))
       + '</section></settings>')

if __name__ == '__main__':
    import xml.dom.minidom
    pretty = xml.dom.minidom.parseString(XML).toprettyxml(indent='    ', encoding='utf-8')
    with open(sys.argv[1], 'wb') as out:
        out.write(pretty)
