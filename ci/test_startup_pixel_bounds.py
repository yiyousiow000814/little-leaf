import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location('pixel_bounds', Path(__file__).resolve().parents[1] / 'qa/compare_startup_positions.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class PixelBoundsTests(unittest.TestCase):
    def test_exact(self):
        a = bytes([100, 100, 100, 255]) * 10000
        self.assertTrue(module.compare_pixels(100, 100, a, a, 6.5)['accepted'])
    def test_default_remains_strict(self):
        a = bytes([100, 100, 100, 255]) * 10000; b = bytearray(a); b[5] += 1
        self.assertFalse(module.compare_pixels(100, 100, a, b, 3.5)['accepted'])
        self.assertTrue(module.compare_pixels(100, 100, a, b, 3.5, True)['accepted'])
        self.assertFalse(module.compare_pixels(100, 100, a, b, 6.5, True)['accepted'])
    def test_geometry_sized_or_color_changes_rejected(self):
        a = bytes([100, 100, 100, 255]) * 10000; b = bytearray(a); b[5] += 2
        self.assertFalse(module.compare_pixels(100, 100, a, b, 3.5, True)['accepted'])
        b = bytearray(a)
        for x in range(3): b[x * 4] += 1
        self.assertFalse(module.compare_pixels(100, 100, a, b, 3.5, True)['accepted'])
