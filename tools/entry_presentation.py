"""Shared, licensed entry styling; no external font requests."""
import base64
from pathlib import Path
from project_layout import source_path

ROOT = Path(__file__).resolve().parents[1]


def entry_styles():
    css = source_path(ROOT, 'web/little_leaf_entry.css').read_text(encoding='utf-8')
    notice = source_path(ROOT, 'assets/fonts/Nunito-OFL.txt').read_text(encoding='utf-8')
    font = source_path(ROOT, 'assets/fonts/Nunito-Variable.ttf').read_bytes()
    return '/* ' + notice + ' */\n' + css.replace('$NUNITO_FONT', base64.b64encode(font).decode('ascii'))
