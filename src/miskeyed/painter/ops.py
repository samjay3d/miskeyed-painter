from typing import Union
from dataclasses import dataclass


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
    

@dataclass(frozen=True)
class UpdateJob:
    node_name: str
    params: dict[str, sp.source.PropertyValue]

def update_parameters(jobs = list[UpdateJob], stack : sp.textureset.Stack = None):
    if stack is None:
        stack = _textureset._get_active_stack()
    if stack is None:
        return

    for node in _iter.scoped_iter_nodes(stack):
        for i, job in enumerate(jobs[:]):
            if job.node_name == node.get_name():
                job = jobs.pop(i)
                break
        source = node.get_source()

        source.set_parameters(params=job.params)

def add_material(layer_name: str, material_name: str, stack : sp.textureset.Stack = None):
    node = next(filter(lambda x: x.get_name() == layer_name,_iter.scoped_iter_nodes(stack)), None)
    if node is None:
        raise ValueError(f"{layer_name} does not exist in {stack.name()}")
    node.set_material_source(sp.resource.search(material_name))

def apply_preset(layer_name: str, preset: str, stack : sp.textureset.Stack = None):
    node = next(filter(lambda x: x.get_name() == layer_name,_iter.scoped_iter_nodes(stack)), None)
    source = node.get_source()
    if not isinstance(source, sp.source.SourceSubstance):
        raise ValueError("Current source is not a substance material")
    source.apply_preset(preset)