import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

OUTPUT = Path(sys.argv[1])
APP_ID = 'app.keplr.vizor'
EVENTS = OUTPUT / 'events.tsv'
ENV = dict(os.environ, XDG_RUNTIME_DIR=str(OUTPUT / 'runtime'),
           VIZOR_TEST_EVENTS=str(EVENTS))
Path(ENV['XDG_RUNTIME_DIR']).mkdir(mode=0o700, exist_ok=True)
RESULTS = []
RUNNERS = []


def passed(name):
    RESULTS.append(name)
    print(f'PASS {name}', flush=True)


def wait_for(callback, description, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = callback()
        if result:
            return result
        time.sleep(0.02)
    raise AssertionError(f'Timed out: {description}')


def events(name, pid=None):
    rows = [line.split('\t') for line in EVENTS.read_text().splitlines()]
    return [row for row in rows if row[0] == name and
            (pid is None or row[1] == str(pid))]


def probe(mode='once', identity=APP_ID, env=ENV):
    return subprocess.Popen([str(OUTPUT / 'guard-probe'), identity, mode],
                            env=env, text=True, stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def once(expected, **kwargs):
    process = probe(**kwargs)
    stdout, stderr = process.communicate(timeout=8)
    assert process.returncode == expected, (stdout, stderr)


def guard_tests():
    owner = probe('hold')
    assert owner.stdout.readline().strip() == 'primary'
    try:
        once(3)
        once(0, identity=APP_ID + '.testnet')
        passed('OS lock excludes same identity; testnet remains independent')
    finally:
        owner.communicate('close\n', timeout=8)
    path = Path(ENV['XDG_RUNTIME_DIR']) / 'vizor-instance-locks' / (APP_ID + '.lock')
    inode = path.stat().st_ino
    once(0)
    assert path.stat().st_ino == inode
    passed('normal exit releases lock without deleting its file')

    owner = probe('hold')
    assert owner.stdout.readline().strip() == 'primary'
    owner.communicate('exit-without-dispose\n', timeout=8)
    once(0)
    passed('process exit releases lock without destructor cleanup')

    owner = probe('exec-child')
    assert owner.stdout.readline().strip() == 'primary'
    def acquired_after_exec():
        candidate = probe()
        candidate.communicate(timeout=3)
        return candidate.returncode == 0
    try:
        wait_for(acquired_after_exec, 'close-on-exec lock release', timeout=1)
        assert owner.poll() is None
    finally:
        owner.wait(timeout=5)
    passed('executed helper cannot retain the wallet process lock')

    other = path.with_name(APP_ID + '.symlink.lock')
    sentinel = OUTPUT / 'sentinel'
    sentinel.write_text('preserve me')
    other.symlink_to(sentinel)
    once(1, identity=APP_ID + '.symlink')
    assert sentinel.read_text() == 'preserve me'
    passed('symlink lock rejected without changing its target')


class Runner:
    def __init__(self, name, binary='runner', args=(), fresh_bus=False, extra=None):
        self.control = OUTPUT / (name + '.control')
        self.log = OUTPUT / (name + '.log')
        env = dict(ENV, VIZOR_TEST_CONTROL=str(self.control))
        env.update(extra or {})
        command = [str(OUTPUT / binary), *args]
        if fresh_bus:
            command = ['dbus-run-session', '--', *command]
        with self.log.open('w') as log:
            self.process = subprocess.Popen(command, env=env, stdout=log, stderr=log)
        RUNNERS.append(self)

    def wait(self, code=0):
        actual = self.process.wait(timeout=10)
        assert actual == code, (actual, self.log.read_text())

    def send(self, command):
        self.control.write_text(command)

    def state(self):
        output = Path(str(self.control) + '.state')
        output.unlink(missing_ok=True)
        self.send('state')
        wait_for(output.exists, 'window state')
        return json.loads(output.read_text())

    def ready(self):
        wait_for(lambda: events('first-frame', self.process.pid), 'first frame')

    def close(self):
        if self.process.poll() is None:
            self.send('close')
            self.wait()


def runner_tests():
    bitcoin_request = 'bitcoin:bc1qfixture?amount=0.01&label=Coffee%20shop'
    evm_request = 'ethereum:0xToken@8453/transfer?address=0xPayee&uint256=25000000'
    primary = Runner('primary', args=('zcash:test-fixture', bitcoin_request,
                                      'argument with spaces'),
                     extra={'VIZOR_TEST_FRAME_DELAY_MS': '1800'})
    wait_for(lambda: events('plugins', primary.process.pid), 'plugin registration')
    secondary = Runner('during-startup', args=(evm_request,))
    secondary.wait()
    assert len(events('engine')) == 1
    assert not events('first-frame')
    assert primary.state()['visible'] is False
    primary.ready()
    assert events('engine', primary.process.pid)[0][2:] == [
        'zcash:test-fixture', bitcoin_request, 'argument with spaces']
    passed('startup reactivation creates one engine and waits for first frame')
    passed('cold-start Dart arguments remain intact')

    primary.send('payment-ready')
    wait_for(lambda: events('payment-ready', primary.process.pid),
             'Dart payment URI readiness')
    assert [row[2] for row in events('payment-uri', primary.process.pid)] == [
        'zcash:test-fixture', bitcoin_request, evm_request]
    passed('cold and forwarded links survive the wait for Dart readiness')

    warm_requests = (
        'zcash:warm-fixture',
        'litecoin:ltc1qfixture?amount=1.5',
        'solana:Payee?amount=25&spl-token=Mint&reference=Order',
        'BITCOIN:bc1quppercase?amount=2',
    )
    for index, uri in enumerate(warm_requests):
        secondary = Runner(f'warm-payment-link-{index}', args=(uri,))
        secondary.wait()
        wait_for(lambda: any(row[2] == uri
                             for row in events('payment-uri', primary.process.pid)),
                 'warm link forwarding')
    assert len(events('engine')) == 1
    assert len(events('payment-uri', primary.process.pid)) == 7
    passed('all payment schemes reach the primary without another engine')

    # A different executable path models another extracted AppImage directory.
    shutil.copy2(OUTPUT / 'runner', OUTPUT / 'runner-copy')
    secondary = Runner('copied-executable', binary='runner-copy')
    secondary.wait()
    assert not events('engine', secondary.process.pid)
    assert primary.state()['windows'] == 1
    passed('another executable path activates the same window')

    window_ids = subprocess.check_output(
        ['xdotool', 'search', '--pid', str(primary.process.pid)], text=True).split()
    window_id = window_ids[-1]
    subprocess.check_call(['xdotool', 'windowminimize', window_id])
    wait_for(lambda: primary.state()['iconified'], 'minimized window')
    secondary = Runner('minimized-reactivation')
    secondary.wait()
    wait_for(lambda: not primary.state()['iconified'], 'restored window')
    wait_for(lambda: primary.state()['active'], 'focused window')
    assert primary.state()['windows'] == 1
    assert len(events('engine')) == 1
    primary.send('capture')
    wait_for(lambda: Path(str(primary.control) + '.png').exists(), 'capture')
    passed('second launch restores and focuses the minimized original window')

    secondary = Runner('different-session', fresh_bus=True)
    secondary.wait(1)
    assert len(events('engine')) == 1
    assert 'already running in another session' in secondary.log.read_text()
    assert events('dialog')
    passed('another D-Bus session is blocked before engine or plugins start')

    testnet = Runner('testnet', binary='runner-testnet')
    testnet.ready()
    assert len(events('engine')) == 2
    assert testnet.state()['windows'] == 1
    testnet.close()
    primary.close()
    passed('mainnet and testnet windows coexist and close normally')

    reopened = Runner('reopened')
    reopened.ready()
    assert len(events('engine', reopened.process.pid)) == 1
    reopened.close()
    passed('closing the primary allows a fresh launch')

    count = len(events('engine'))
    racers = [Runner(f'race-{i}') for i in range(6)]
    wait_for(lambda: len(events('first-frame')) == count + 1, 'raced primary')
    wait_for(lambda: sum(r.process.poll() is None for r in racers) == 1,
             'secondary launchers to exit')
    assert len(events('engine')) == count + 1
    for runner in racers:
        runner.close()
        runner.wait()
    passed('six simultaneous launches leave exactly one live engine')

    count = len(events('engine'))
    bad_runtime = OUTPUT / 'runtime-is-file'
    bad_runtime.write_text('not a directory')
    denied = Runner('lock-error', extra={'XDG_RUNTIME_DIR': str(bad_runtime)})
    denied.wait(1)
    assert len(events('engine')) == count
    assert 'could not safely open wallet storage' in denied.log.read_text()
    passed('unavailable lock directory shows an error without starting Flutter')

    # A session-bus outage must never allow two independent wallet engines.
    disconnected = Runner('no-bus', extra={
        'DBUS_SESSION_BUS_ADDRESS': 'unix:path=' + str(OUTPUT / 'missing-bus')})
    wait_for(lambda: disconnected.process.poll() is not None or
             events('first-frame', disconnected.process.pid), 'no-bus outcome')
    if disconnected.process.poll() is None:
        second = Runner('no-bus-second', extra={
            'DBUS_SESSION_BUS_ADDRESS': 'unix:path=' + str(OUTPUT / 'missing-bus')})
        second.wait(1)
        assert not events('engine', second.process.pid)
        disconnected.close()
    else:
        disconnected.wait(1)
        assert not events('engine', disconnected.process.pid)
    passed('missing D-Bus cannot bypass process exclusion')


EVENTS.write_text('')
try:
    guard_tests()
    runner_tests()
finally:
    for runner in RUNNERS:
        runner.close()

(OUTPUT / 'result.json').write_text(json.dumps(
    {'passed': len(RESULTS), 'checks': RESULTS,
     'scope': 'Production native runner, real GTK/D-Bus/flock; Flutter content substituted'},
    indent=2) + '\n')
print(f'{len(RESULTS)} checks passed', flush=True)
