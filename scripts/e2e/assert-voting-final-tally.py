#!/usr/bin/env python3
"""Check every share and the exact decrypted tally of the desktop voting fixture."""
import argparse
import json
import time
import urllib.request
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--api-url', required=True)
    parser.add_argument('--round-id', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    url = f'{args.api_url}/shielded-vote/v1/vote-summary/{args.round_id}'
    deadline = time.monotonic() + 900
    last_status = None
    while time.monotonic() < deadline:
        with urllib.request.urlopen(url, timeout=15) as response:
            summary = json.load(response)
        status = summary['status']
        if status != last_status:
            print(f'round {args.round_id}: {status}', flush=True)
            last_status = status
        if status == 3:
            break
        time.sleep(3)
    else:
        raise AssertionError(f'Round did not finalize: {summary}')
    args.output.write_text(json.dumps(summary, indent=2) + '\n')
    proposals = summary['proposals']
    assert sorted(int(p['id']) for p in proposals) == [1, 2, 3, 4], summary
    for proposal in proposals:
        options = proposal['options']
        assert sum(int(o.get('index', 0)) == 0 for o in options) == 1, proposal
        for option in options:
            selected = int(option.get('index', 0)) == 0
            # One bundle has 16 shares totalling one ballot (12,500,000 zatoshi).
            assert int(option.get('ballot_count', 0)) == (16 if selected else 0), proposal
            assert int(option.get('total_value', 0)) == (1 if selected else 0), proposal
    print('Final tally verified: all 64 shares; decision 0 = 1 ballot for proposals 1–4; other decisions = 0.', flush=True)


if __name__ == '__main__':
    main()
