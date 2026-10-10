"""Tooling contract tests with one shared CI module import path.

Run selected tests with python3 -m unittest tests.tooling.test_NAME.CASE.
Discovery uses -s tests/tooling -t . so this package initializes first.
"""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'ci'))
