# -*- coding: utf-8 -*-
"""Generate the Kodi WindowXML layouts (1920x1080) of the graphical interface.

python tools/gen_skin.py script.maxstream
-> resources/skins/Default/1080i/script-maxstream-*.xml
"""
import os
import sys
import xml.dom.minidom

ADDON = 'script.maxstream'
OUT = os.path.join(sys.argv[1], 'resources', 'skins', 'Default', '1080i')

BG, PANEL, CARD, CARD_F, SEL = 'FF0B1220', 'FF121C2E', 'FF16213A', 'FF1D2A44', 'FF2A3A5C'
ACCENT, TEXT, MUTED, DARK = 'FF29B6F6', 'FFEAF1FB', 'FFA9B8D0', 'FF0B1220'
TRACK, LIVE, STAR, GOLD, TEAL, WHITE = 'FF26324A', 'FFE5484D', 'FFFF9F43', 'FFFFD58A', 'FF0E7C6E', 'FFFFFFFF'


def S(sid):
    return '$ADDON[%s %d]' % (ADDON, sid)


def P(name):
    return '$INFO[Window.Property(%s)]' % name


def esc(text):
    return str(text).replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def pos(l, t, w, h):
    return '<left>%d</left><top>%d</top><width>%d</width><height>%d</height>' % (l, t, w, h)


def vis(cond):
    return '<visible>%s</visible>' % esc(cond) if cond else ''


def img(l, t, w, h, tex, color=None, border=None, aspect=None, cond=None, diffuse=None, background=False, cid=None):
    attrs = ''
    if border:
        attrs += ' border="%d"' % border
    if color:
        attrs += ' colordiffuse="%s"' % color
    if diffuse:
        attrs += ' diffuse="%s"' % diffuse
    if background:
        attrs += ' background="true"'
    out = '<control type="image"%s>%s<texture%s>%s</texture>' % (
        ' id="%d"' % cid if cid else '', pos(l, t, w, h), attrs, esc(tex))
    if aspect:
        out += '<aspectratio>%s</aspectratio>' % aspect
    return out + vis(cond) + '</control>'


def lbl(l, t, w, h, text, font='font12', color=TEXT, align='left', aligny='center', cond=None, scroll=False,
        wrap=False):
    out = ('<control type="label">%s<font>%s</font><textcolor>%s</textcolor><align>%s</align>'
           '<aligny>%s</aligny><label>%s</label>' % (pos(l, t, w, h), font, color, align, aligny, esc(text)))
    if scroll:
        out += '<scroll>true</scroll>'
    if wrap:
        out += '<wrapmultiline>true</wrapmultiline>'
    return out + vis(cond) + '</control>'


def textbox(l, t, w, h, text, font='font10', color=TEXT, cond=None):
    return ('<control type="textbox">%s<font>%s</font><textcolor>%s</textcolor><label>%s</label>'
            '<autoscroll delay="6000" time="3000" repeat="10000">true</autoscroll>%s</control>'
            % (pos(l, t, w, h), font, color, esc(text), vis(cond)))


def nav(**dirs):
    return ''.join('<on%s>%s</on%s>' % (k, v, k) for k, v in dirs.items() if v is not None)


def button(cid, l, t, w, h, label='', font='font12', nofocus=CARD, focus=ACCENT, textcolor=TEXT,
           focusedcolor=DARK, align='center', radius='ms_r20.png', border=22, cond=None, offsetx=0, **navs):
    return ('<control type="button" id="%d">%s<label>%s</label><font>%s</font><textcolor>%s</textcolor>'
            '<focusedcolor>%s</focusedcolor><align>%s</align><aligny>center</aligny><textoffsetx>%d</textoffsetx>'
            '<texturefocus border="%d" colordiffuse="%s">%s</texturefocus>'
            '<texturenofocus border="%d" colordiffuse="%s">%s</texturenofocus>%s%s</control>'
            % (cid, pos(l, t, w, h), esc(label), font, textcolor, focusedcolor, align, offsetx,
               border, focus, radius, border, nofocus, radius, nav(**navs), vis(cond)))


def progress(l, t, w, h, info=None, cid=None, cond=None, color=ACCENT):
    return ('<control type="progress"%s>%s<texturebg border="3" colordiffuse="%s">ms_r4.png</texturebg>'
            '<midtexture border="3" colordiffuse="%s">ms_r4.png</midtexture>%s%s</control>'
            % (' id="%d"' % cid if cid else '', pos(l, t, w, h), TRACK, color,
               '<info>%s</info>' % info if info else '', vis(cond)))


def group(children, cond=None, anim=None):
    return '<control type="group">%s%s%s</control>' % (anim or '', vis(cond), ''.join(children))


def zoom_on_focus(cid, amount=104):
    return ('<animation effect="zoom" end="%d" center="auto" time="160" tween="sine" '
            'condition="Control.HasFocus(%d)">Conditional</animation>' % (amount, cid))


def scrolling(children):
    """Labels of the focused item scroll (marquee) when their text is too long."""
    out = []
    for child in children:
        if (child.startswith('<control type="label">') and '<scroll>' not in child
                and '<wrapmultiline>' not in child):
            child = child.replace('</label>', '</label><scroll>true</scroll><scrollspeed>50</scrollspeed>', 1)
        out.append(child)
    return out


def listc(cid, l, t, w, h, item, focused, orientation='vertical', ctype='list', cond=None, **navs):
    iw, ih, ichildren = item
    fw, fh, fchildren = focused
    fchildren = scrolling(fchildren)
    return ('<control type="%s" id="%d">%s<orientation>%s</orientation><scrolltime tween="quadratic">220</scrolltime>'
            '%s%s<itemlayout width="%d" height="%d">%s</itemlayout><focusedlayout width="%d" height="%d">%s</focusedlayout>'
            '</control>' % (ctype, cid, pos(l, t, w, h), orientation, nav(**navs), vis(cond), iw, ih, ''.join(ichildren),
                            fw, fh, ''.join(fchildren)))


def window(controls, default, dialog=False):
    head = '<window%s><defaultcontrol always="true">%d</defaultcontrol>' % (' type="dialog"' if dialog else '', default)
    if not dialog:
        head += '<backgroundcolor>%s</backgroundcolor>' % BG
    return head + '<controls>%s</controls></window>' % ''.join(controls)


def write(name, content):
    os.makedirs(OUT, exist_ok=True)
    pretty = xml.dom.minidom.parseString(content).toprettyxml(indent='    ', encoding='utf-8')
    with open(os.path.join(OUT, name), 'wb') as handle:
        handle.write(pretty)


# ---------------------------------------------------------------- shared pieces
def background():
    return img(0, 0, 1920, 1080, 'ms_white.png', BG)


def clock(left=1700, width=164):
    return lbl(left, 44, width, 64, '[B]$INFO[System.Time][/B]', 'font37', align='right')


def back_button(**navs):
    return [button(90, 56, 44, 64, 64, nofocus=CARD, focus=ACCENT, **navs),
            img(72, 60, 32, 32, 'ic_back.png', TEXT, cond='!Control.HasFocus(90)'),
            img(72, 60, 32, 32, 'ic_back.png', DARK, cond='Control.HasFocus(90)')]


def category_list(cid, left, top, width, height, **navs):
    item = (width, 66, [lbl(20, 0, width - 110, 62, '$INFO[ListItem.Label]', 'font12'),
                        lbl(width - 96, 0, 76, 62, '$INFO[ListItem.Label2]', 'font10', MUTED, align='right')])
    focused = (width, 66, [
        img(0, 0, width, 62, 'ms_r20.png', ACCENT, 22, cond='Control.HasFocus(%d)' % cid),
        img(0, 0, width, 62, 'ms_r20.png', SEL, 22, cond='!Control.HasFocus(%d)' % cid),
        lbl(20, 0, width - 110, 62, '[B]$INFO[ListItem.Label][/B]', 'font12', DARK, cond='Control.HasFocus(%d)' % cid,
            scroll=True),
        lbl(20, 0, width - 110, 62, '[B]$INFO[ListItem.Label][/B]', 'font12', TEXT, cond='!Control.HasFocus(%d)' % cid),
        lbl(width - 96, 0, 76, 62, '$INFO[ListItem.Label2]', 'font10', DARK, align='right', cond='Control.HasFocus(%d)' % cid),
        lbl(width - 96, 0, 76, 62, '$INFO[ListItem.Label2]', 'font10', MUTED, align='right', cond='!Control.HasFocus(%d)' % cid)])
    return listc(cid, left, top, width, height, item, focused, **navs)


# ---------------------------------------------------------------- home
def home():
    c = [background(),
         img(72, 52, 64, 64, 'ms_r20.png', ACCENT, 22), img(90, 70, 28, 28, 'ic_play.png', DARK),
         lbl(156, 52, 300, 64, '[B]MaxStream[/B]', 'font37'),
         lbl(470, 52, 620, 64, P('playlist'), 'font12', MUTED),
         lbl(980, 40, 430, 56, '[B]$INFO[System.Time][/B]', 'font45', align='right'),
         lbl(980, 94, 430, 30, '$INFO[System.Date]', 'font10', MUTED, align='right'),
         img(1428, 52, 260, 64, 'ms_r20.png', CARD, 22, cond='!String.IsEmpty(Window.Property(expiry))'),
         lbl(1428, 52, 260, 64, P('expiry'), 'font10', MUTED, align='center', cond='!String.IsEmpty(Window.Property(expiry))'),
         button(111, 1704, 52, 64, 64, nofocus=CARD, focus=ACCENT, down=103, right=110),
         img(1720, 68, 32, 32, 'ic_fav.png', STAR, cond='!Control.HasFocus(111)'),
         img(1720, 68, 32, 32, 'ic_fav.png', DARK, cond='Control.HasFocus(111)'),
         button(110, 1784, 52, 64, 64, nofocus=CARD, focus=ACCENT, down=103, left=111),
         img(1800, 68, 32, 32, 'ic_settings.png', TEXT, cond='!Control.HasFocus(110)'),
         img(1800, 68, 32, 32, 'ic_settings.png', DARK, cond='Control.HasFocus(110)')]

    tiles = [(101, 72, 'FFB3283A', 'ic_live.png', 30000, 'live_sub', dict(right=102, down=201, up=110)),
             (102, 676, 'FF5B32A8', 'ic_movie.png', 30001, 'movie_sub', dict(left=101, right=103, down=203, up=110)),
             (103, 1280, 'FF1C62C0', 'ic_series.png', 30002, 'series_sub', dict(left=102, right=110, down=205, up=110))]
    for cid, left, color, icon, title, sub, navs in tiles:
        parts = [button(cid, left, 156, 568, 380, nofocus=color, focus=color, radius='ms_r28.png', border=30, **navs),
                 img(left - 12, 144, 592, 404, 'ms_ring28.png', WHITE, 40, cond='Control.HasFocus(%d)' % cid),
                 img(left + 40, 196, 96, 96, icon, WHITE),
                 lbl(left + 40, 380, 500, 72, '[B]%s[/B]' % S(title), 'font45', WHITE),
                 lbl(left + 40, 452, 500, 40, P(sub), 'font12', 'E6FFFFFF')]
        if cid == 101:
            parts += [img(left + 388, 204, 140, 44, 'ms_r20.png', WHITE, 22),
                      lbl(left + 388, 204, 140, 44, '[B]%s[/B]' % S(30027), 'font10', 'FFB3283A', align='center')]
        c.append(group(parts, anim=zoom_on_focus(cid, 103)))

    shortcuts = [(201, 'ic_catchup.png', 'FF0E7C6E', 30003), (202, 'ic_epg.png', 'FFB0306A', 30015),
                 (203, 'ic_fav.png', 'FFC26A12', 30004), (204, 'ic_search.png', 'FF3949AB', 30539),
                 (205, 'ic_lists.png', 'FF6D4C41', 30538), (206, 'ic_account.png', 'FF00838F', 30537)]
    ups = {201: 101, 202: 101, 203: 102, 204: 102, 205: 103, 206: 103}
    for idx, (cid, icon, tint, title) in enumerate(shortcuts):
        left = 72 + idx * 300
        navs = dict(up=ups[cid], down=600, left=cid - 1 if idx else None, right=cid + 1 if idx < 5 else None)
        c.append(group([
            button(cid, left, 572, 276, 130, nofocus=CARD, focus=CARD_F, **navs),
            img(left - 8, 564, 292, 146, 'ms_ring20.png', WHITE, 30, cond='Control.HasFocus(%d)' % cid),
            img(left + 20, 605, 64, 64, 'ms_r20.png', tint, 22),
            img(left + 34, 619, 36, 36, icon, WHITE),
            lbl(left + 100, 598, 166, 40, '[B]%s[/B]' % S(title), 'font12'),
            lbl(left + 100, 638, 166, 34, P('sc_%d' % cid), 'font10', MUTED)], anim=zoom_on_focus(cid, 104)))

    card = [img(0, 0, 420, 148, 'ms_r20.png', PANEL, 22),
            img(16, 18, 200, 112, 'ms_r12.png', CARD_F, 14),
            img(96, 54, 40, 40, 'ic_play.png', MUTED, cond='String.IsEmpty(ListItem.Art(thumb))'),
            img(16, 18, 200, 112, '$INFO[ListItem.Art(thumb)]', aspect='scale', diffuse='ms_mask_thumb.png', background=True),
            lbl(234, 22, 172, 36, '[B]$INFO[ListItem.Label][/B]', 'font10', scroll=False),
            lbl(234, 60, 172, 32, '$INFO[ListItem.Label2]', 'font10', MUTED),
            progress(234, 112, 166, 6, info='ListItem.PercentPlayed')]
    c += [lbl(72, 730, 900, 48, '[B]%s[/B]' % S(30072), 'font13'),
          lbl(72, 800, 900, 48, S(30503), 'font12', MUTED, cond='!Integer.IsGreater(Container(600).NumItems,0)'),
          listc(600, 72, 790, 1776, 170, (444, 160, card),
                (444, 160, card + [img(-6, -6, 432, 160, 'ms_ring20.png', WHITE, 30, cond='Control.HasFocus(600)')]),
                orientation='horizontal', up=201)]
    write('script-maxstream-home.xml', window(c, 101))


# ---------------------------------------------------------------- live
def live():
    c = [background()] + back_button(right=91, down=100) + [
        lbl(140, 44, 900, 64, '[B]%s[/B]' % P('title'), 'font37'),
        button(91, 1160, 44, 520, 64, label=S(30504), font='font12', nofocus=CARD, focus=ACCENT,
               textcolor=MUTED, align='left', offsetx=64, left=90, down=200),
        img(1182, 62, 28, 28, 'ic_search.png', MUTED, cond='!Control.HasFocus(91)'),
        img(1182, 62, 28, 28, 'ic_search.png', DARK, cond='Control.HasFocus(91)'),
        clock(),
        img(56, 148, 340, 884, 'ms_r28.png', PANEL, 30),
        category_list(100, 70, 168, 312, 844, right=200, up=90),
        img(424, 148, 660, 884, 'ms_r28.png', PANEL, 30),
        lbl(440, 520, 628, 60, P('empty_text'), 'font12', MUTED, align='center',
            cond='!String.IsEmpty(Window.Property(empty_text))')]
    row = [lbl(10, 0, 56, 88, '$INFO[ListItem.Property(num)]', 'font10', MUTED, align='center'),
           img(76, 12, 64, 64, 'ms_r12.png', CARD_F, 14),
           lbl(76, 12, 64, 64, '[B]$INFO[ListItem.Property(initials)][/B]', 'font10', TEXT, align='center',
               cond='String.IsEmpty(ListItem.Art(thumb))'),
           img(80, 16, 56, 56, '$INFO[ListItem.Art(thumb)]', aspect='keep', background=True),
           lbl(158, 6, 312, 38, '[B]$INFO[ListItem.Label][/B]', 'font12'),
           img(478, 14, 112, 28, 'ms_r4.png', TEAL, 5, cond='String.IsEqual(ListItem.Property(catchup),1)'),
           lbl(478, 14, 112, 28, '[B]%s[/B]' % S(30522), 'font10', WHITE, align='center',
               cond='String.IsEqual(ListItem.Property(catchup),1)'),
           img(598, 16, 22, 22, 'ic_fav.png', STAR, cond='String.IsEqual(ListItem.Property(fav),1)'),
           lbl(158, 44, 440, 30, '$INFO[ListItem.Property(now)]', 'font10', MUTED),
           progress(158, 78, 440, 4, info='ListItem.PercentPlayed', cond='Integer.IsGreater(ListItem.PercentPlayed,0)')]
    c.append(listc(200, 440, 164, 628, 852, (628, 94, row),
                   (628, 94, [img(0, 0, 628, 90, 'ms_r20.png', CARD_F, 22),
                              img(0, 0, 628, 90, 'ms_ring20.png', ACCENT, 30, cond='Control.HasFocus(200)')] + row),
                   left=100, right=301, up=91))
    # preview + info
    c += [img(1112, 148, 752, 423, 'ms_r28.png', 'FF05080F', 30),
          img(1452, 290, 72, 72, 'ic_live.png', 'FF55657F', cond='!Player.HasVideo'),
          lbl(1112, 380, 752, 40, S(30506), 'font12', 'FF8A99B4', align='center', cond='!Player.HasVideo'),
          '<control type="videowindow">%s%s</control>' % (pos(1112, 148, 752, 423), vis('Player.HasVideo')),
          img(1136, 172, 140, 40, 'ms_r20.png', LIVE, 22, cond='Player.HasVideo'),
          lbl(1136, 172, 140, 40, '[B]%s[/B]' % S(30027), 'font10', WHITE, align='center', cond='Player.HasVideo'),
          img(1112, 595, 752, 437, 'ms_r28.png', PANEL, 30),
          img(1144, 623, 64, 64, 'ms_r12.png', CARD_F, 14),
          img(1148, 627, 56, 56, P('sel_logo'), aspect='keep', background=True),
          lbl(1224, 619, 430, 30, P('sel_numname'), 'font10', MUTED),
          lbl(1224, 649, 386, 44, '[B]%s[/B]' % P('sel_now'), 'font13', scroll=True),
          lbl(1616, 634, 224, 44, '[B]%s[/B]' % P('sel_time'), 'font12', align='right'),
          progress(1144, 707, 688, 6, cid=410),
          textbox(1144, 727, 688, 112, P('sel_desc'), 'font10', 'FFC4D0E3'),
          lbl(1144, 845, 400, 30, '[B]%s[/B]' % S(30507), 'font10', MUTED,
              cond='!String.IsEmpty(Window.Property(sel_next1))'),
          lbl(1144, 877, 688, 32, P('sel_next1'), 'font10'),
          lbl(1144, 911, 688, 32, P('sel_next2'), 'font10'),
          button(301, 1144, 956, 230, 60, label='[B]%s[/B]' % S(30505), nofocus=ACCENT, focus=ACCENT,
                 textcolor=DARK, left=200, right=302),
          img(1136, 948, 246, 76, 'ms_ring20.png', WHITE, 30, cond='Control.HasFocus(301)'),
          button(302, 1390, 956, 180, 60, label='[B]%s[/B]' % S(30015), nofocus=CARD_F, left=301, right=304),
          button(304, 1586, 956, 60, 60, nofocus=CARD_F, left=302, right=303),
          img(1601, 971, 30, 30, 'ic_fav.png', STAR, cond='String.IsEqual(Window.Property(sel_fav),1)'),
          img(1601, 971, 30, 30, 'ic_fav_o.png', STAR, cond='!String.IsEqual(Window.Property(sel_fav),1)'),
          button(303, 1662, 956, 170, 60, label='[B]%s[/B]' % S(30003), nofocus=CARD_F, left=304,
                 cond='String.IsEqual(Window.Property(sel_catchup),1)')]
    write('script-maxstream-live.xml', window(c, 100))


# ---------------------------------------------------------------- movies / series grid
def vod():
    c = [background()] + back_button(right=301, down=100) + [
        lbl(140, 34, 820, 54, '[B]%s[/B]' % P('title'), 'font37', scroll=True),
        lbl(140, 86, 820, 32, P('subtitle'), 'font10', MUTED),
        img(1000, 48, 568, 64, 'ms_r20.png', CARD, 22)]
    sorts = [(301, 1006, 210, 30086, 'recent'), (302, 1224, 140, 30112, 'az'), (303, 1372, 190, 30509, 'rating')]
    for cid, left, width, label, key in sorts:
        c += [img(left, 54, width, 52, 'ms_r12.png', SEL, 14, cond='String.IsEqual(Window.Property(sort),%s)' % key),
              button(cid, left, 54, width, 52, label='[B]%s[/B]' % S(label), font='font10', nofocus='00000000',
                     radius='ms_r12.png', border=14, left=cid - 1 if cid > 301 else 90,
                     right=cid + 1 if cid < 303 else 304, down=200)]
    c += [button(304, 1588, 48, 64, 64, nofocus=CARD, left=303, down=200),
          img(1606, 66, 28, 28, 'ic_search.png', TEXT, cond='!Control.HasFocus(304)'),
          img(1606, 66, 28, 28, 'ic_search.png', DARK, cond='Control.HasFocus(304)'),
          clock(),
          img(56, 148, 320, 884, 'ms_r28.png', PANEL, 30),
          category_list(100, 70, 168, 292, 844, right=200, up=90),
          lbl(404, 520, 1460, 60, P('empty_text'), 'font12', MUTED, align='center',
              cond='!String.IsEmpty(Window.Property(empty_text))')]
    poster = [img(0, 0, 216, 324, 'ms_r20.png', CARD_F, 22),
              lbl(14, 210, 188, 100, '[B]$INFO[ListItem.Label][/B]', 'font10', TEXT, aligny='bottom', wrap=True,
                  cond='String.IsEmpty(ListItem.Art(poster))'),
              img(0, 0, 216, 324, '$INFO[ListItem.Art(poster)]', aspect='scale', diffuse='ms_mask_poster.png',
                  background=True),
              img(142, 8, 66, 30, 'ms_r4.png', 'C805080F', 5, cond='!String.IsEmpty(ListItem.Property(rating))'),
              lbl(142, 8, 66, 30, '[B]$INFO[ListItem.Property(rating)][/B]', 'font10', GOLD, align='center',
                  cond='!String.IsEmpty(ListItem.Property(rating))'),
              img(8, 8, 128, 30, 'ms_r4.png', ACCENT, 5, cond='String.IsEqual(ListItem.Property(new),1)'),
              lbl(8, 8, 128, 30, '[B]%s[/B]' % S(30521), 'font10', DARK, align='center',
                  cond='String.IsEqual(ListItem.Property(new),1)'),
              progress(0, 318, 216, 6, info='ListItem.PercentPlayed', cond='Integer.IsGreater(ListItem.PercentPlayed,0)'),
              lbl(0, 334, 216, 34, '[B]$INFO[ListItem.Label][/B]', 'font10'),
              lbl(0, 366, 216, 30, '$INFO[ListItem.Label2]', 'font10', MUTED)]
    c.append(listc(200, 404, 148, 1460, 920, (240, 432, poster),
                   (240, 432, poster + [img(-8, -8, 232, 340, 'ms_ring20.png', WHITE, 30, cond='Control.HasFocus(200)')]),
                   ctype='panel', left=100, up=301))
    write('script-maxstream-vod.xml', window(c, 100))


# ---------------------------------------------------------------- movie / series detail
def detail():
    c = [background(),
         img(680, 0, 1240, 720, P('fanart'), aspect='scale', background=True),
         img(680, 0, 900, 720, 'ms_fade_h.png', BG),
         img(680, 420, 1240, 300, 'ms_fade_v.png', BG)] + back_button(down=301, right=301) + [
        lbl(140, 44, 1200, 64, P('crumb'), 'font12', MUTED, scroll=True),
        clock(),
        img(56, 148, 373, 560, 'ms_r28.png', CARD_F, 30),
        lbl(76, 560, 333, 130, '[B]%s[/B]' % P('title'), 'font13', aligny='bottom', wrap=True,
            cond='String.IsEmpty(Window.Property(poster))'),
        img(56, 148, 373, 560, P('poster'), aspect='scale', diffuse='ms_mask_poster_big.png', background=True),
        lbl(485, 150, 1380, 90, '[B]%s[/B]' % P('title'), 'font45', scroll=True),
        lbl(485, 244, 1300, 44, P('meta'), 'font12', 'FFC4D0E3', scroll=True),
        textbox(485, 300, 860, 170, P('plot'), 'font12', 'FFD2DCEB'),
        lbl(485, 482, 860, 34, P('director_line'), 'font10'),
        lbl(485, 516, 860, 34, P('cast_line'), 'font10'),
        lbl(485, 560, 520, 30, P('resume_text'), 'font10', MUTED, cond='String.IsEqual(Window.Property(has_resume),1)'),
        lbl(485, 560, 520, 30, P('resume_left'), 'font10', MUTED, align='right',
            cond='String.IsEqual(Window.Property(has_resume),1)'),
        progress(485, 596, 520, 6, cid=410, cond='String.IsEqual(Window.Property(has_resume),1)'),
        button(301, 485, 630, 380, 68, label='[B]%s[/B]' % P('btn_play'), font='font12', nofocus=ACCENT, focus=ACCENT,
               textcolor=DARK, up=90, right=304, down=500),
        img(477, 622, 396, 84, 'ms_ring20.png', WHITE, 30, cond='Control.HasFocus(301)'),
        button(304, 885, 630, 68, 68, nofocus=CARD_F, left=301, right=302, up=90, down=500),
        img(902, 647, 34, 34, 'ic_fav.png', STAR, cond='String.IsEqual(Window.Property(fav),1)'),
        img(902, 647, 34, 34, 'ic_fav_o.png', STAR, cond='!String.IsEqual(Window.Property(fav),1)'),
        button(302, 973, 630, 290, 68, label='[B]%s[/B]' % S(30511), nofocus=CARD_F, left=304, right=303, up=90,
               down=500, cond='String.IsEqual(Window.Property(has_resume),1)'),
        button(303, 1283, 630, 260, 68, label='[B]%s[/B]' % S(30512), nofocus=CARD_F, left=302, up=90, down=500,
               cond='String.IsEqual(Window.Property(has_trailer),1)'),
        lbl(56, 744, 900, 44, '[B]%s[/B]' % P('bottom_title'), 'font13')]
    related = [img(0, 0, 150, 225, 'ms_r20.png', CARD_F, 22),
               lbl(10, 120, 130, 95, '$INFO[ListItem.Label]', 'font10', aligny='bottom', wrap=True,
                   cond='String.IsEmpty(ListItem.Art(poster))'),
               img(0, 0, 150, 225, '$INFO[ListItem.Art(poster)]', aspect='scale', diffuse='ms_mask_poster.png',
                   background=True)]
    c.append(listc(500, 56, 796, 1808, 250, (172, 250, related),
                   (172, 250, related + [img(-7, -7, 164, 239, 'ms_ring20.png', WHITE, 30, cond='Control.HasFocus(500)')]),
                   orientation='horizontal', cond='String.IsEqual(Window.Property(mode),movie)', up=301))
    season = [img(0, 0, 196, 56, 'ms_r20.png', CARD, 22),
              lbl(0, 0, 196, 56, '$INFO[ListItem.Label]', 'font12', align='center')]
    season_f = [img(0, 0, 196, 56, 'ms_r20.png', ACCENT, 22, cond='Control.HasFocus(400)'),
                img(0, 0, 196, 56, 'ms_r20.png', SEL, 22, cond='!Control.HasFocus(400)'),
                lbl(0, 0, 196, 56, '[B]$INFO[ListItem.Label][/B]', 'font12', DARK, align='center', cond='Control.HasFocus(400)'),
                lbl(0, 0, 196, 56, '[B]$INFO[ListItem.Label][/B]', 'font12', TEXT, align='center', cond='!Control.HasFocus(400)')]
    c.append(listc(400, 56, 740, 1808, 56, (212, 56, season), (212, 56, season_f), orientation='horizontal',
                   cond='String.IsEqual(Window.Property(mode),series)', up=301, down=510))
    episode = [img(0, 0, 288, 162, 'ms_r20.png', CARD_F, 22),
               lbl(0, 30, 288, 70, '[B]E$INFO[ListItem.Property(epnum)][/B]', 'font45', 'FF55657F', align='center',
                   cond='String.IsEmpty(ListItem.Art(thumb))'),
               img(124, 104, 40, 40, 'ic_play.png', 'FF55657F', cond='String.IsEmpty(ListItem.Art(thumb))'),
               img(0, 0, 288, 162, '$INFO[ListItem.Art(thumb)]', aspect='scale', diffuse='ms_mask_thumb.png', background=True),
               img(8, 8, 66, 30, 'ms_r4.png', 'C805080F', 5, cond='!String.IsEmpty(ListItem.Art(thumb))'),
               lbl(8, 8, 66, 30, '[B]E$INFO[ListItem.Property(epnum)][/B]', 'font10', TEXT, align='center',
                   cond='!String.IsEmpty(ListItem.Art(thumb))'),
               progress(0, 156, 288, 6, info='ListItem.PercentPlayed', cond='Integer.IsGreater(ListItem.PercentPlayed,0)'),
               lbl(0, 168, 288, 34, '$INFO[ListItem.Label]', 'font10')]
    c.append(listc(510, 56, 816, 1808, 210, (312, 210, episode),
                   (312, 210, episode + [img(-7, -7, 302, 176, 'ms_ring20.png', WHITE, 30, cond='Control.HasFocus(510)')]),
                   orientation='horizontal', cond='String.IsEqual(Window.Property(mode),series)', up=400))
    write('script-maxstream-detail.xml', window(c, 301))


# ---------------------------------------------------------------- guide / replay dialog
def guide():
    c = [img(0, 0, 1920, 1080, 'ms_white.png', 'E6000000'),
         img(160, 90, 1600, 900, 'ms_r28.png', PANEL, 30),
         img(200, 124, 64, 64, 'ms_r12.png', CARD_F, 14),
         img(204, 128, 56, 56, P('logo'), aspect='keep', background=True),
         lbl(284, 118, 1300, 44, '[B]%s[/B]' % P('title'), 'font13'),
         lbl(284, 160, 1300, 32, P('subtitle'), 'font10', MUTED),
         category_list(100, 200, 220, 320, 740, right=200)]
    prog = [lbl(20, 0, 210, 72, '$INFO[ListItem.Label2]', 'font12', MUTED),
            lbl(240, 0, 720, 72, '$INFO[ListItem.Label]', 'font12',
                cond='!String.IsEqual(ListItem.Property(status),past)'),
            lbl(240, 0, 720, 72, '$INFO[ListItem.Label]', 'font12', 'FF6F7E98',
                cond='String.IsEqual(ListItem.Property(status),past)'),
            img(990, 20, 150, 32, 'ms_r4.png', LIVE, 5, cond='String.IsEqual(ListItem.Property(status),live)'),
            lbl(990, 20, 150, 32, '[B]%s[/B]' % S(30027), 'font10', WHITE, align='center',
                cond='String.IsEqual(ListItem.Property(status),live)'),
            img(990, 20, 150, 32, 'ms_r4.png', TEAL, 5, cond='String.IsEqual(ListItem.Property(status),replay)'),
            lbl(990, 20, 150, 32, '[B]%s[/B]' % S(30522), 'font10', WHITE, align='center',
                cond='String.IsEqual(ListItem.Property(status),replay)')]
    c.append(listc(200, 560, 220, 1160, 560, (1160, 76, prog),
                   (1160, 76, [img(0, 0, 1160, 72, 'ms_r20.png', CARD_F, 22),
                               img(0, 0, 1160, 72, 'ms_ring20.png', ACCENT, 30, cond='Control.HasFocus(200)')] + prog),
                   left=100))
    c += [img(560, 796, 1160, 164, 'ms_r20.png', CARD, 22),
          textbox(584, 810, 1112, 136, '[B]$INFO[Container(200).ListItem.Label][/B][CR]'
                                       '$INFO[Container(200).ListItem.Property(desc)]', 'font10', 'FFD2DCEB')]
    write('script-maxstream-guide.xml', window(c, 200, dialog=True))


# ---------------------------------------------------------------- donation dialog
def donate():
    c = [img(0, 0, 1920, 1080, 'ms_white.png', 'E6000000'),
         img(410, 250, 1100, 580, 'ms_r28.png', PANEL, 30),
         img(460, 300, 400, 400, 'ms_r20.png', WHITE, 22),
         img(480, 320, 360, 360, 'donate_qr.png'),
         lbl(460, 712, 400, 40, 'paypal.me/MaxStreamKodi/5EUR', 'font10', MUTED, align='center'),
         img(910, 300, 64, 64, 'ms_r20.png', 'FFC26A12', 22),
         img(924, 314, 36, 36, 'ic_fav.png', WHITE),
         lbl(994, 300, 486, 64, '[B]%s[/B]' % S(30630), 'font13', scroll=True),
         textbox(910, 390, 560, 220, S(30631), 'font12', 'FFD2DCEB'),
         button(301, 910, 690, 380, 64, label='[B]%s[/B]' % S(30632), nofocus=ACCENT, focus=ACCENT, textcolor=DARK,
                right=302),
         img(902, 682, 396, 80, 'ms_ring20.png', WHITE, 30, cond='Control.HasFocus(301)'),
         button(302, 1306, 690, 170, 64, label='[B]%s[/B]' % S(30633), nofocus=CARD_F, left=301)]
    write('script-maxstream-donate.xml', window(c, 301, dialog=True))


if __name__ == '__main__':
    home()
    live()
    vod()
    detail()
    guide()
    donate()
    print('skin xml written to', OUT)
