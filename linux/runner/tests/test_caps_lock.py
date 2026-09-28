"""Exercise the production Caps Lock channel against real GDK backends.

Only the Flutter messenger is substituted. X11 input to nested Weston is
translated by Weston into native Wayland keyboard/modifier events for GTK.
"""
import os
import re
from pathlib import Path
import subprocess
import sys
import time

output = Path(sys.argv[1])
runtime = output / 'runtime'
runtime.mkdir(mode=0o700)
env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime))


def wait_for(check, description):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.025)
    raise AssertionError(description)


def xdo(*args):
    return subprocess.check_output(['xdotool', *args], text=True).strip()


def test_backend(backend, host_window=None):
    events = output / (backend + '.events')
    control = output / (backend + '.control')
    test_env = dict(env, GDK_BACKEND=backend, WAYLAND_DISPLAY='vizor-test',
                    VIZOR_TEST_EVENTS=str(events), VIZOR_TEST_CONTROL=str(control))
    # Enable before launch to verify that no keypress in the app is required.
    xdo('key', 'Caps_Lock')
    with (output / (backend + '.log')).open('w') as log:
        app = subprocess.Popen([str(output / 'runner')], env=test_env,
                               stdout=log, stderr=log)
    try:
        def rows(kind):
            if not events.exists():
                return []
            return [line.split('\t')[-1] for line in events.read_text().splitlines()
                    if line.startswith(kind + '\t')]

        def command(text):
            wait_for(lambda: not control.exists(), 'previous command consumed')
            control.write_text(text)

        def query(expected):
            count = len(rows('caps-state'))
            command('caps-state')
            wait_for(lambda: len(rows('caps-state')) > count, 'native query response')
            assert rows('caps-state')[-1] == expected, (backend, rows('caps-state'))

        wait_for(lambda: rows('first-frame'), 'first frame')
        if backend == 'x11':
            window = xdo('search', '--pid', str(app.pid)).splitlines()[-1]
            xdo('windowactivate', '--sync', window)
        else:
            window = host_window
        wait_for(lambda: rows('caps-changed') and rows('caps-changed')[-1] == 'true',
                 backend + ' initial Caps Lock on')
        query('true')
        xdo('key', 'Caps_Lock')
        wait_for(lambda: rows('caps-changed')[-1] == 'false', 'Caps Lock off event')
        query('false')
        xdo('key', 'Shift_L')
        query('false')
        xdo('key', 'Caps_Lock')
        wait_for(lambda: rows('caps-changed')[-1] == 'true', 'Caps Lock on event')
        query('true')
        # Moving focus outside the application must publish unknown, not leave
        # the last on-state visible. Return without typing in the app.
        xdo('windowminimize', window)
        wait_for(lambda: rows('caps-changed')[-1] == 'null', 'inactive state')
        query('null')
        xdo('key', 'Caps_Lock')
        xdo('windowmap', window)
        xdo('windowactivate', '--sync', window)
        wait_for(lambda: rows('caps-changed')[-1] == 'false', 'refocus state refresh')
        query('false')
        command('close')
        assert app.wait(timeout=10) == 0
        print('PASS', backend, 'initial state, on/off events, Shift, blur, refocus, teardown', flush=True)
    finally:
        if app.poll() is None:
            app.terminate()
            app.wait(timeout=5)


with (output / 'openbox.log').open('w') as log:
    wm = subprocess.Popen(['openbox'], env=env, stdout=log, stderr=log)
weston = None
try:
    wait_for(lambda: subprocess.run(['xdotool', 'getwindowfocus'],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0,
             'window manager')
    test_backend('x11')
    with (output / 'weston.log').open('w') as log:
        weston = subprocess.Popen(['weston', '--backend=x11-backend.so',
                                   '--socket=vizor-test', '--width=1280', '--height=800',
                                   '--idle-time=0', '--no-config'], env=env, stdout=log, stderr=log)
    wait_for(lambda: (runtime / 'vizor-test').exists(), 'Weston socket')
    wait_for(lambda: re.search(r'window id (\d+)', (output / 'weston.log').read_text()),
             'Weston X11 host window')
    window = re.search(r'window id (\d+)', (output / 'weston.log').read_text()).group(1)
    xdo('windowactivate', '--sync', window)
    test_backend('wayland', window)
finally:
    if weston is not None:
        weston.terminate()
        weston.wait(timeout=5)
    wm.terminate()
    wm.wait(timeout=5)
