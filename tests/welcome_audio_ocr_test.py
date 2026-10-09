"""Verify OCR crops retain original pixels and reject another viewport."""
import tempfile
import unittest
from pathlib import Path
from PIL import Image
from welcome_audio_ocr import crop_hint


class HintCropTests(unittest.TestCase):
    def test_crop_is_bound_to_original_pixels(self):
        with tempfile.TemporaryDirectory() as folder:
            source, output = Path(folder) / 'source.png', Path(folder) / 'hint.png'
            image = Image.new('RGB', (1360, 880), (200, 220, 230))
            image.putpixel((30, 830), (88, 60, 30))
            image.save(source)
            receipt = crop_hint(source, output)
            with Image.open(output) as crop:
                self.assertEqual(crop.size, (1328, 60))
                self.assertEqual(crop.tobytes(), image.crop(tuple(receipt['box'])).tobytes())
            self.assertEqual(receipt['source'], source.name)
            self.assertEqual(len(receipt['source_sha256']), 64)

    def test_unexpected_viewport_is_not_silently_cropped(self):
        with tempfile.TemporaryDirectory() as folder:
            source, output = Path(folder) / 'source.png', Path(folder) / 'hint.png'
            Image.new('RGB', (390, 844)).save(source)
            with self.assertRaisesRegex(ValueError, '1360x880'):
                crop_hint(source, output)
            self.assertFalse(output.exists())

    def test_title_crop_and_unknown_region(self):
        with tempfile.TemporaryDirectory() as folder:
            source, output = Path(folder) / 'source.png', Path(folder) / 'title.png'
            Image.new('RGB', (1360, 880)).save(source)
            receipt = crop_hint(source, output, 'title')
            self.assertEqual(receipt['box'], [540, 140, 820, 185])
            with Image.open(output) as crop:
                self.assertEqual(crop.size, (280, 45))
            with self.assertRaisesRegex(ValueError, 'Unknown'):
                crop_hint(source, output, 'unknown')


if __name__ == '__main__':
    unittest.main()
