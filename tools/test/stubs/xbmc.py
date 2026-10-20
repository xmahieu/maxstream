LOGDEBUG, LOGINFO, LOGWARNING, LOGERROR = 0, 1, 2, 3
LOG = []
BUILTINS = []
HAS = set()
RPC = []
PLAYED = []
def log(msg, level=0):
    LOG.append((level, msg))
    if level >= 3: print('KODI-ERR', msg)
def executebuiltin(cmd, wait=False):
    BUILTINS.append(cmd)
    if cmd == 'PlayerControl(Stop)':
        Player.playing = False
GUI_SETTINGS = {'filecache.memorysize': 20, 'filecache.readfactor': 400, 'filecache.buffermode': 4}
ALLOWED = {'filecache.readfactor': (100, 150, 200, 400, 800, 1000, 2000)}
INFO = {'System.Memory(total)': '32640MB'}
def getInfoLabel(name): return INFO.get(name, '')
def executeJSONRPC(q):
    import json
    RPC.append(q)
    req = json.loads(q)
    p = req.get('params', {})
    if req['method'] == 'Settings.GetSettingValue':
        return json.dumps({'result': {'value': GUI_SETTINGS.get(p['setting'])}})
    if req['method'] == 'Settings.SetSettingValue':
        if p['value'] not in ALLOWED.get(p['setting'], (p['value'],)):
            return json.dumps({'error': {'code': -32602}})
        GUI_SETTINGS[p['setting']] = p['value']
        return json.dumps({'result': True})
    if req['method'] == 'Player.GetActivePlayers':
        return json.dumps({'result': [{'playerid': 1, 'type': 'video'}] if STREAMS else []})
    if req['method'] == 'Player.GetProperties':
        return json.dumps({'result': STREAMS})
    if req['method'] == 'Player.SetAudioStream':
        STREAMS['currentaudiostream'] = STREAMS['audiostreams'][p['stream']]
    return json.dumps({'result': 'OK'})
STREAMS = {}
def getCondVisibility(cond):
    import re
    m = re.match(r'System.HasAddon\((.*)\)', cond)
    return bool(m and m.group(1) in HAS)
def sleep(ms): pass
class Monitor(object):
    def abortRequested(self): return True
    def waitForAbort(self, t=0): return True
class Player(object):
    playing = False
    def __init__(self): pass
    def play(self, item='', listitem=None, windowed=False, startpos=-1):
        PLAYED.append((item, listitem, windowed)); Player.playing = True
    def stop(self): Player.playing = False
    def isPlaying(self): return Player.playing
    def isPlayingVideo(self): return Player.playing
