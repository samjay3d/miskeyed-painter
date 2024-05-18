__all__ = ['iter_nodes', 'scoped_iter_nodes']
from typing import Generator
from contextlib import ExitStack

import substance_painter
import logging

from . import _textureset

log = logging.getLogger(__name__)

def iter_nodes(stack: substance_painter.textureset.Stack = None) -> Generator[substance_painter.layerstack.HierarchicalNode, None, None]:
    """
    Parses through an entire stack and yields every node in the layer stack.
    """
    if stack is None:
        stack = _textureset._get_active_stack()
    if stack is None:
        return
        
    for root in substance_painter.layerstack.get_root_layer_nodes(stack):
        root : substance_painter.layerstack.HierarchicalNode
        if isinstance(root, substance_painter.layerstack.GroupLayerNode):
            layers = root.sub_layers()
            while True:
                try:
                    layer = layers.pop()
                except IndexError:
                    break
                if isinstance(layer, substance_painter.layerstack.GroupLayerNode):
                    layers.extend(layer.sub_layers())
                yield layer
        yield root

def scoped_iter_nodes(stack: substance_painter.textureset.Stack = None) -> Generator[substance_painter.layerstack.HierarchicalNode, None, None]:
    """Iterate over nodes with undo scope."""
    if stack is None:
        stack = _textureset._get_active_stack()
    if stack is None:
        return
    with ExitStack() as s:
        s.enter_context(substance_painter.application.disable_engine_computations())
        scope = s.enter_context(substance_painter.layerstack.ScopedModification(f"{stack.name} undo scope"))
        nodes = iter_nodes(stack)
        try:
            while True:
                yield next(nodes)
        except StopIteration:
            ...
