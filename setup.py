import setuptools
import pathlib
import shutil
import os

setuptools.setup()

# installs any plugin info.
user_profile = pathlib.Path(os.environ['USERPROFILE'])
documents_path = user_profile / 'Documents'
onedrive_path = user_profile / 'OneDrive' / 'Documents'
if onedrive_path.exists():
    documents_path = onedrive_path

startup_path = documents_path / 'Adobe' / 'Adobe Substance 3D Painter' / 'python'
startup_plugin = pathlib.Path(__file__).parent / 'src' / 'miskeyed' / 'plugins'
nodes = list(startup_plugin.iterdir())
while nodes:
    node = nodes.pop()
    if node.is_dir():
        nodes.extend(node.iterdir())
    else:
        dest = startup_path / node.relative_to(startup_plugin)
        if dest.exists():
            os.remove(str(dest))
        shutil.copy2(str(node), str(dest))