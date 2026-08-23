"""Painter bootstrap kept dependency-free for the embedded interpreter."""

import site
from pathlib import Path

# Painter loads this file directly from its plugin path. Add the wheel root only
# after Painter has built its own sys.path; unlike PYTHONPATH this cannot shadow
# the DCC's standard library during interpreter initialization.
site.addsitedir(str(Path(__file__).resolve().parents[3]))

import miskeyed.painter.startup  # noqa: E402

def start_plugin():
    """Plugin interface: called to start the plugin."""
    miskeyed.painter.startup.setup()




def close_plugin():
    """Plugin interface: called to stop the plugin."""
    miskeyed.painter.startup.teardown()
