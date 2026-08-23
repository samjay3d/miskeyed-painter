"""Experimental bridge that launches a resolved misapp context through ``rez-env``.

This module deliberately remains separate from the native launcher.  It is a comparison harness:
misapp discovers the application and resolves its child environment, then a temporary Rez package
applies that environment and Rez owns the actual process context and launch.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Iterable, Mapping, Sequence


def _parse_inspection(output: str) -> tuple[str, dict[str, str]]:
    """Return the executable and recipe-owned environment from ``misapp inspect`` output."""
    values: dict[str, str] = {}
    environment: dict[str, str] = {}
    for line in output.splitlines():
        key, separator, value = line.partition("=")
        if not separator:
            continue
        if key.startswith("environment."):
            environment[key.removeprefix("environment.")] = value
        else:
            values[key] = value
    executable = values.get("executable")
    if not executable:
        raise ValueError("misapp inspection did not contain an executable")
    return executable, environment


def _package_source(environment: Mapping[str, str]) -> str:
    """Generate a data-only Rez package that applies the already-resolved uv environment."""
    lines = [
        'name = "misapp_uv_context"',
        'version = "0.1.0"',
        "",
        "def commands():",
    ]
    if not environment:
        lines.append("    pass")
    else:
        for name, value in sorted(environment.items()):
            if not name.replace("_", "").isalnum() or name[0].isdigit():
                raise ValueError(f"invalid environment variable from misapp: {name!r}")
            lines.append(f"    env.{name} = {value!r}")
    return "\n".join(lines) + "\n"


def _write_repository(root: Path, environment: Mapping[str, str]) -> Path:
    package_root = root / "misapp_uv_context" / "0.1.0"
    package_root.mkdir(parents=True)
    (package_root / "package.py").write_text(_package_source(environment), encoding="utf-8")
    return package_root


def _command(
    rez_env: str,
    repository: Path,
    executable: str,
    arguments: Iterable[str],
) -> list[str]:
    return [rez_env, "--paths", str(repository), "misapp_uv_context", "--", executable, *arguments]


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="misapp-rez",
        description="Compare a misapp launch with a temporary rez-env context.",
    )
    parser.add_argument("application", help="misapp application recipe to inspect")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print the generated package.py and rez-env command without launching",
    )
    parser.add_argument(
        "arguments",
        nargs=argparse.REMAINDER,
        help="application arguments after --",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    forwarded = args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
    misapp = shutil.which("misapp")
    if not misapp:
        print("misapp-rez: the native misapp command is not installed", file=sys.stderr)
        return 2
    rez_env = shutil.which("rez-env")
    if not rez_env and not args.dry_run:
        print(
            "misapp-rez: rez-env was not found; use `uvx --from 'misapp[rez]' "
            "misapp-rez ...` or install Rez separately",
            file=sys.stderr,
        )
        return 2

    inspection = subprocess.run(
        [misapp, "inspect", args.application],
        check=False,
        capture_output=True,
        text=True,
    )
    if inspection.returncode:
        sys.stderr.write(inspection.stderr)
        return inspection.returncode
    try:
        executable, environment = _parse_inspection(inspection.stdout)
    except ValueError as error:
        print(f"misapp-rez: {error}", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory(prefix="misapp-rez-") as temporary:
        repository = Path(temporary)
        package_root = _write_repository(repository, environment)
        command = _command(rez_env or "rez-env", repository, executable, forwarded)
        if args.dry_run:
            print((package_root / "package.py").read_text(encoding="utf-8"), end="")
            print("command:", subprocess.list2cmdline(command))
            return 0
        child_environment = os.environ.copy()
        return subprocess.run(command, env=child_environment, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
