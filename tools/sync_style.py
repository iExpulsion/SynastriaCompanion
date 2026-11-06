"""Copies the MaterialCraftUI style kit into SynastriaCompanion/UI/Style.lua, and the Cognac skin into
SynastriaCompanion/UI/Skins/Cognac.

    py -I -X utf8 tools/sync_style.py

MATERIALCRAFTUI overrides where the MaterialCraftUI repo is (default: next to this repo).
"""
import os, runpy, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.environ.get('MATERIALCRAFTUI', os.path.join(ROOT, '..', 'MaterialCraftUI'))
sys.argv = [sys.argv[0], ROOT, 'SynastriaCompanion', 'Cognac']
runpy.run_path(os.path.join(LIB, 'tools', 'sync_style.py'), run_name='__main__')
