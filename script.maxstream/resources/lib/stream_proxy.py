# -*- coding: utf-8 -*-
"""Local stream relay (127.0.0.1) run by the MaxStream service.

Kodi only reconnects after a stream has delivered nothing for 20 seconds, so a
stalling IPTV server shows up as a frozen picture. The relay sits between Kodi
and the provider: when the provider stops sending for STALL_TIMEOUT seconds or
drops the connection, it reconnects at once and resumes at the exact byte
(HTTP Range) for movies / episodes, or re-opens the channel for live TV. Kodi
keeps playing from its own cache meanwhile, so the hiccup is invisible."""
import re
import select
import socket
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote, unquote, urlparse

from .common import DEFAULT_UA, log, log_error

STALL_TIMEOUT = 5        # seconds without data before reconnecting (also the connect timeout)
GIVE_UP_AFTER = 180      # seconds without any data before giving up
MAX_RECONNECTS = 6       # per minute: more looks like flooding and gets the account / IP banned
CHUNK = 256 * 1024
PASS_HEADERS = ('Content-Type', 'Content-Length', 'Content-Range', 'Accept-Ranges', 'Last-Modified', 'ETag')


def split_headers(url):
    """'http://x/y.ts|User-Agent=a%20b&Referer=c' -> (url, {headers})"""
    base, _, raw = url.partition('|')
    headers = {}
    for part in raw.split('&') if raw else []:
        key, _, value = part.partition('=')
        if key:
            headers[key] = unquote(value)
    headers.setdefault('User-Agent', DEFAULT_UA)
    return base, headers


def parse_range(value):
    match = re.match(r'bytes=(\d+)-(\d*)', value or '')
    if not match:
        return None, None
    return int(match.group(1)), int(match.group(2)) if match.group(2) else None


class RelayHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'MaxStreamRelay/1.0'

    def log_message(self, fmt, *args):  # quiet: Kodi log only gets our own lines
        pass

    def client_gone(self):
        """True when Kodi has closed its side (stop, channel change)."""
        try:
            readable, _, _ = select.select([self.connection], [], [], 0)
            if readable:
                return self.connection.recv(1, socket.MSG_PEEK) == b''
        except (OSError, ValueError):
            return True
        return False

    # ------------------------------------------------------------ upstream
    def _open(self, url, headers, start=None, end=None, method='GET'):
        hdrs = dict(headers)
        hdrs['Accept-Encoding'] = 'identity'
        if start is not None:
            hdrs['Range'] = 'bytes=%d-%s' % (start, '' if end is None else end)
        req = urllib.request.Request(url, headers=hdrs, method=method)
        return urllib.request.urlopen(req, timeout=STALL_TIMEOUT)

    def _params(self):
        query = parse_qs(urlparse(self.path).query)
        target = query.get('u', [''])[0]
        kind = query.get('k', ['vod'])[0]
        return target, kind

    def do_HEAD(self):  # noqa: N802
        target, _kind = self._params()
        url, headers = split_headers(target)
        try:
            resp = self._open(url, headers, method='HEAD')
            self.send_response(resp.status)
            for key in PASS_HEADERS:
                if resp.headers.get(key):
                    self.send_header(key, resp.headers[key])
            self.end_headers()
            resp.close()
        except (urllib.error.URLError, OSError, ValueError):
            self.send_error(502)

    def do_GET(self):  # noqa: N802
        target, kind = self._params()
        if not target:
            self.send_error(400)
            return
        url, headers = split_headers(target)
        start, end = parse_range(self.headers.get('Range'))
        try:
            resp = self._open(url, headers, start, end)
        except urllib.error.HTTPError as err:
            self.send_error(err.code)
            return
        except (urllib.error.URLError, OSError, ValueError) as err:
            log_error('relay: cannot open stream: %s' % err)
            self.send_error(502)
            return

        status = resp.status
        length = resp.headers.get('Content-Length')
        seekable = status == 206 or (resp.headers.get('Accept-Ranges', '').lower() == 'bytes')
        offset = start if status == 206 and start else 0
        expected_end = None  # exclusive end offset of what Kodi asked for
        if length is not None:
            expected_end = offset + int(length)

        self.send_response(status)
        for key in PASS_HEADERS:
            if resp.headers.get(key):
                self.send_header(key, resp.headers[key])
        if length is None:
            self.send_header('Connection', 'close')
        self.end_headers()
        self.close_connection = length is None

        self._pump(resp, url, headers, kind, offset, expected_end, end, seekable)

    def _pump(self, resp, url, headers, kind, offset, expected_end, end, seekable):
        reconnects = 0
        recent = []
        last_data = time.time()
        live = kind == 'live'
        resumable = seekable and kind != 'live'
        try:
            while True:
                try:
                    if resp is None:
                        raise socket.timeout('reconnect')
                    chunk = resp.read1(CHUNK) if hasattr(resp, 'read1') else resp.read(CHUNK)
                except (socket.timeout, OSError, ValueError, urllib.error.URLError) as err:
                    chunk = None
                    reason = str(err) or err.__class__.__name__
                else:
                    reason = 'connection closed early'
                if chunk:
                    self.wfile.write(chunk)
                    offset += len(chunk)
                    last_data = time.time()
                    continue
                # no data: finished, or stalled / dropped
                if chunk == b'' and (expected_end is None and not live or
                                     expected_end is not None and offset >= expected_end):
                    return  # real end of file
                if not (resumable or live):
                    return  # cannot resume this stream without restarting it
                if self.client_gone():
                    return  # Kodi stopped or switched channel: never reconnect for nobody
                if time.time() - last_data > GIVE_UP_AFTER:
                    log_error('relay: provider silent for %ds, giving up' % GIVE_UP_AFTER)
                    return
                if resp is not None:
                    try:
                        resp.close()
                    except OSError:
                        pass
                    resp = None
                reconnects += 1
                recent = [t for t in recent if time.time() - t < 60] + [time.time()]
                if len(recent) > MAX_RECONNECTS:
                    log_error('relay: %d reconnections in a minute, stopping to protect the account' % len(recent))
                    return
                log('relay: %s at byte %d, reconnecting (%d)' % (reason, offset, reconnects), 1)
                try:
                    if live:
                        resp = self._open(url, headers)
                    else:
                        resp = self._open(url, headers, offset, end)
                        if resp.status != 206 and offset > 0:
                            resp.close()
                            resp = None
                            log_error('relay: server refused to resume, stopping')
                            return
                except urllib.error.HTTPError as err:
                    # the provider refuses (401/403 = connection limit or ban, 404 = gone):
                    # insisting only makes it worse
                    log_error('relay: provider refused the reconnection (HTTP %s), stopping' % err.code)
                    return
                except (urllib.error.URLError, OSError, ValueError) as err:
                    log_error('relay: reconnect failed: %s' % err)
                    resp = None
                    pause = time.time() + min(5, 0.5 * reconnects)
                    while time.time() < pause:
                        if self.client_gone():
                            return
                        time.sleep(0.2)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass  # Kodi closed the connection (stop, seek, next item)
        finally:
            if resp is not None:
                try:
                    resp.close()
                except OSError:
                    pass


class Relay(object):
    def __init__(self):
        self.server = None
        self.thread = None

    @property
    def port(self):
        return self.server.server_address[1] if self.server else 0

    def start(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), RelayHandler)
        server.daemon_threads = True
        self.server = server
        self.thread = threading.Thread(target=server.serve_forever, name='MaxStreamRelay')
        self.thread.daemon = True
        self.thread.start()
        log('relay listening on 127.0.0.1:%d' % self.port, 1)
        return self.port

    def stop(self):
        if self.server:
            self.server.shutdown()
            self.server.server_close()
            self.server = None


def relay_url(port, url, kind):
    return 'http://127.0.0.1:%d/stream?k=%s&u=%s' % (port, kind, quote(url, safe=''))
