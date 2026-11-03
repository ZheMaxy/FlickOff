#!/usr/bin/env python3
"""Check what the repository hooks let through. Fixtures are assembled at runtime so the hooks don't catch this file."""
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PRE_COMMIT = ROOT / '.githooks/pre-commit'
COMMIT_MSG = ROOT / '.githooks/commit-msg'
LABEL = 'PA' + 'SS'
WORD = 'PASS' + 'WORD'
VALUE = 'hunter' + 'hunter'
ASSISTANT = 'cla' + 'ude'


def pre_commit_refuses(line):
    with tempfile.TemporaryDirectory(prefix='flickoff-hooks-') as temp:
        subprocess.run(['git', 'init', '-q', temp], check=True)
        (Path(temp) / 'staged.txt').write_text(line + '\n')
        subprocess.run(['git', '-C', temp, 'add', 'staged.txt'], check=True)
        return subprocess.run(['bash', str(PRE_COMMIT)], cwd=temp, capture_output=True, check=False).returncode != 0


def commit_msg_refuses(message):
    with tempfile.TemporaryDirectory(prefix='flickoff-hooks-') as temp:
        file = Path(temp) / 'message'
        file.write_text(message + '\n')
        return subprocess.run(['bash', str(COMMIT_MSG), str(file)], capture_output=True, check=False).returncode != 0


def main():
    for line in (
        f"print('{LABEL}: channels and phased rollout reach the feed only when asked for')",
        f"print('{LABEL}: publishing rewrites the download links and the cask')",
        f'{LABEL}: v1.2.0-beta.1 installs over the previous build',
        f'  echo "{LABEL}: everything restored after the probe"',
        'A plain sentence about a password and a token.',
    ):
        assert not pre_commit_refuses(line), line
    print(f'{LABEL}: test results and ordinary text get through')

    for line in (
        f'{LABEL}: {VALUE}',
        f'{LABEL}: "{VALUE}"',
        f'{LABEL}={VALUE}',
        f'DB_{LABEL}: {VALUE}',
        f'{WORD}={VALUE}',
        f'{WORD}: {VALUE}',
        f'export {LABEL}={VALUE}',
        'pass' + f'word = "{VALUE}"',
        'pass' + ': hunter2hunter',
        f'{LABEL}: all good, but {WORD}={VALUE}',
        'SEC' + f'RET_KEY={VALUE}',
        'gh' + 'p_' + 'a' * 36,
        '-----BEGIN RSA PRIVATE' + ' KEY-----',
    ):
        assert pre_commit_refuses(line), line
    print(f'{LABEL}: credentials are still refused, also next to a test result')

    assert pre_commit_refuses(f'Written with {ASSISTANT}.')
    assert commit_msg_refuses(f'Fix the timer\n\nCo-authored-by: {ASSISTANT}')
    assert not commit_msg_refuses('Fix the timer')
    print(f'{LABEL}: assistant attribution is refused in files and commit messages')


if __name__ == '__main__':
    main()
