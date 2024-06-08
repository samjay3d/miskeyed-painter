import miskeyed.painter.startup

def start_plugin():
    """Plugin interface: called to start the plugin."""
    miskeyed.painter.startup.setup()




def close_plugin():
    """Plugin interface: called to stop the plugin."""
    miskeyed.painter.startup.teardown()