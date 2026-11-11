"""Keep runtime assets, not local configs, source code, tests or player saves."""
from pathlib import Path
import shutil
import sys

source, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
for name in ('_maps', 'strings', 'icons', 'sound', 'html', 'tgui/public',
             'build/behavior_trees', 'code', 'modular_skyrat', 'modular_zubbers',
             'modular_zzplurt', 'services/supervisor', 'container', 'modular_babylon/lobby'):
    shutil.copytree(source / name, output / name, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('*.dm', '*.dme', '*.dmb', '*.rsc', '*.lk',
                                                 '__pycache__', 'test_*.py', 'smoke_*.py',
                                                 'active.dmm', 'node_modules', '.cache'))
for name in ('babylon.dmb', 'babylon.rsc', 'babylon-lobby.dmb', 'babylon-lobby.rsc',
             'LICENSE', 'GPLv3.txt'):
    shutil.copy2(source / name, output / name)
for name in ('librust_g.so', 'libdreamluau.so'):
    shutil.copy2(Path('/opt/native') / name, output / name)
