import substance_painter as sp

from . import _iter
from . import _textureset

def parent_nodes_under_new_group(name: str, stack : sp.textureset.Stack = None) -> None:
    raise NotImplementedError("Substance Painter Currently does not support moving nodes")

    if stack is None:
        stack = _textureset._get_active_stack()
    if stack is None:
        return
    nodes =  _iter.scoped_iter_nodes(stack)
    insert_position = sp.layerstack.InsertPosition.from_textureset_stack(stack)
    group = sp.layerstack.insert_group(insert_position)
    group.set_name(name)

    insert_position = sp.layerstack.InsertPosition.inside_node(group, sp.layerstack.NodeStack.Substack)
    
        