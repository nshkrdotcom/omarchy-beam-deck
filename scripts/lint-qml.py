#!/usr/bin/env python3
"""Map Quickshell's qs import root for native lint; unresolved imports are errors."""
from __future__ import annotations
import argparse
from pathlib import Path
import subprocess
import tempfile


def run(executable: str, shell: Path, files: list[str]) -> int:
    with tempfile.TemporaryDirectory(prefix='beam-deck-native-imports-') as folder:
        (Path(folder) / 'qs').symlink_to(shell.resolve(), target_is_directory=True)
        result = subprocess.run(
            [executable, '--import', 'error', '-I', folder, *files],
            capture_output=True, text=True, timeout=60,
        )
    if result.stdout:
        print(result.stdout, end='')
    if result.stderr:
        print(result.stderr, end='')
    return result.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lint', required=True)
    parser.add_argument('--shell', required=True, type=Path)
    parser.add_argument('files', nargs='+')
    args = parser.parse_args()
    return run(args.lint, args.shell, args.files)


if __name__ == '__main__':
    raise SystemExit(main())
