#!/usr/bin/env python3
"""Capture the installed modal_corner_preview entry point on an iOS simulator."""
import argparse
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', required=True, help='Simulator UDID')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
bundle = 'com.keplr.vizor'


def simctl(*command):
    return subprocess.run(['xcrun', 'simctl', *command], check=True,
                          capture_output=True, text=True).stdout.strip()


container = Path(simctl('get_app_container', args.device, bundle, 'data'))
exchange = container / 'tmp' / 'vizor-modal-corners'
exchange.mkdir(parents=True, exist_ok=True)
for name in ('ready.json', 'ack.txt', 'results.json'):
    (exchange / name).unlink(missing_ok=True)
simctl('launch', '--terminate-running-process', args.device, bundle)
seen = set()
deadline = time.monotonic() + 120
while time.monotonic() < deadline:
    results = exchange / 'results.json'
    if results.exists():
        data = json.loads(results.read_text())
        (args.output / 'results.json').write_text(json.dumps(data, indent=2))
        if isinstance(data, dict):
            raise RuntimeError(data)
        by_id = {record['id']: record for record in data}
        assert set(by_id) == {'dark-sheet', 'keyboard', 'keyboard-closed',
                              'centered-dialog', 'light-tall-sheet'}, data
        for name, record in by_id.items():
            assert len(record['surfaces']) == 1, record
            surface = record['surfaces'][0]
            assert surface['tl'] == 32, record
            if name in ('keyboard', 'centered-dialog'):
                assert surface['bl'] == surface['br'] == 32, record
            else:
                assert surface['bl'] > 32 and surface['br'] > 32, record
                assert surface['frame'][0] == 16, record
        assert by_id['keyboard']['keyboard'] > 0, 'Enable the software keyboard'
        assert by_id['keyboard-closed']['keyboard'] == 0
        assert (by_id['dark-sheet']['surfaces'][0]['bl'] ==
                by_id['keyboard-closed']['surfaces'][0]['bl'])
        print(json.dumps(data, indent=2))
        break
    ready = exchange / 'ready.json'
    if ready.exists():
        try:
            record = json.loads(ready.read_text())
        except json.JSONDecodeError:
            time.sleep(0.05)
            continue
        name = record['id']
        if name not in seen:
            simctl('io', args.device, 'screenshot', '--mask=black',
                   str(args.output / f'{name}.png'))
            seen.add(name)
            (exchange / 'ack.txt').write_text(name)
    time.sleep(0.1)
else:
    raise TimeoutError('Modal preview did not finish within 120 seconds')
