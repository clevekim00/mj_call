#!/usr/bin/env python3
"""Verify exact historical copies; no access to user data or original checkout."""
import hashlib
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
entries = json.loads((root / 'docs/history/migration-manifest.json').read_text())
for entry in entries:
    file = root / entry['archive']
    assert file.is_file(), f'Missing: {file}'
    assert hashlib.sha256(file.read_bytes()).hexdigest() == entry['sha256'], f'Changed historical source: {file}'
print(f'Historical migration verified: {len(entries)} files')
