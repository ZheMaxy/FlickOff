#!/usr/bin/env python3
"""Embed the pinned framework, preserve signatures, and reject non-native helpers."""
from pathlib import Path
import subprocess
import sys

app = Path(sys.argv[1])
arch = sys.argv[2]
candidates = sorted(Path('.build/artifacts').rglob('Sparkle.framework'))
if len(candidates) != 1:
    raise SystemExit(f'Expected one pinned Sparkle framework; found {len(candidates)}')
target = app / 'Contents/Frameworks/Sparkle.framework'
target.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(['ditto', str(candidates[0]), str(target)], check=True)
checked = set()
for path in target.rglob('*'):
    if not path.is_file() or path.is_symlink():
        continue
    kind = subprocess.check_output(['file', '-b', str(path)], text=True)
    if 'Mach-O' not in kind:
        continue
    # Apple lipo treats everything after -verify_arch as an architecture list.
    subprocess.run(['lipo', str(path), '-verify_arch', arch], check=True)
    checked.add(str(path.relative_to(target)))
if not checked:
    raise SystemExit('Sparkle framework contains no executable code')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(target)], check=True)
print(f'Sparkle embedded: {len(checked)} Mach-O components support {arch}; vendor signatures verified')
