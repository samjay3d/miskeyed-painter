from __future__ import annotations

import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch

from miskeyed.rez_bridge import (
    _command,
    _package_source,
    _parse_inspection,
    _write_repository,
    main,
)


class RezBridgeTests(unittest.TestCase):
    def test_parses_only_resolved_child_environment(self) -> None:
        executable, environment = _parse_inspection(
            "application=substancepainter\n"
            "executable=/opt/painter\n"
            "site_packages=/tmp/site\n"
            "environment.PAINTER_PLUGIN_PATH=/tmp/plugin=variant\n"
        )
        self.assertEqual(executable, "/opt/painter")
        self.assertEqual(environment, {"PAINTER_PLUGIN_PATH": "/tmp/plugin=variant"})

    def test_generates_deterministic_rez_commands(self) -> None:
        source = _package_source({"Z_LAST": "last", "A_FIRST": "it's first"})
        self.assertEqual(
            source,
            'name = "misapp_uv_context"\n'
            'version = "0.1.0"\n\n'
            "def commands():\n"
            '    env.A_FIRST = "it\'s first"\n'
            "    env.Z_LAST = 'last'\n",
        )

    def test_writes_repository_layout_and_builds_launch_command(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            package = _write_repository(repository, {"PLUGIN_PATH": "/plugin"})
            self.assertTrue((package / "package.py").is_file())
            self.assertEqual(
                _command("rez-env", repository, "/dcc", ["--flag"]),
                [
                    "rez-env",
                    "--paths",
                    str(repository),
                    "misapp_uv_context",
                    "--",
                    "/dcc",
                    "--flag",
                ],
            )

    def test_dry_run_does_not_require_rez_installation(self) -> None:
        inspection = CompletedProcess(
            args=[],
            returncode=0,
            stdout=(
                "executable=/dcc/painter\n"
                "environment.SUBSTANCE_PAINTER_PLUGINS_PATH=/uv/site/plugins\n"
            ),
            stderr="",
        )
        output = StringIO()
        with (
            patch("miskeyed.rez_bridge.shutil.which", side_effect=["/bin/misapp", None]),
            patch("miskeyed.rez_bridge.subprocess.run", return_value=inspection),
            redirect_stdout(output),
        ):
            status = main(["--dry-run", "substancepainter", "--", "--mesh", "model.fbx"])
        self.assertEqual(status, 0)
        self.assertIn("env.SUBSTANCE_PAINTER_PLUGINS_PATH = '/uv/site/plugins'", output.getvalue())
        self.assertIn("rez-env --paths", output.getvalue())
        self.assertIn("/dcc/painter --mesh model.fbx", output.getvalue())


if __name__ == "__main__":
    unittest.main()
