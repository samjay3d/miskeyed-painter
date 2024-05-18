import substance_painter
import logging

log = logging.getLogger(__name__)

def _get_active_stack() -> None:
    """Safely log raised exceptions in getting active stack"""
    try:
        stack = substance_painter.textureset.get_active_stack()
    except substance_painter.exception.ProjectError:
        log.warning("No project is opened!")
        return None
    except RuntimeError:
        log.error("No active stack!")
        return None 
    return stack