"""Add the permanent itch chooser to the ordinary export before inventory hashing."""
from pathlib import Path
from entry_presentation import entry_styles
from project_layout import source_path

ROOT = Path(__file__).resolve().parents[1]
BOOT = 'window.__littleLeafVault.boot()'
GATED_BOOT = 'window.LittleLeafItchReleaseEntryReady.then(() => ' + BOOT + ')'
PAGE_BEGIN = '<!-- little-leaf-release-entry:begin -->'
PAGE_END = '<!-- little-leaf-release-entry:end -->'
SCRIPT_BEGIN = '<!-- little-leaf-release-controller:begin -->'
SCRIPT_END = '<!-- little-leaf-release-controller:end -->'
ENTRY = '''<section id="itch-release-entry" class="leaf-entry-page" hidden aria-labelledby="itch-release-heading"><div class="leaf-entry-card"><p class="leaf-entry-brand">Little Leaf</p><p class="leaf-entry-eyebrow">A little café of your own</p><h1 id="itch-release-heading" class="leaf-entry-title">Welcome to your café</h1><p class="leaf-entry-intro">Choose how you'd like to begin.</p><div class="leaf-entry-actions"><div class="leaf-entry-option"><a id="itch-release-account" aria-describedby="itch-account-detail itch-progress-separation" class="leaf-entry-link" href="https://little-leaf-41e5d.firebaseapp.com/" target="_blank" rel="noopener noreferrer">Play with Google · opens a new tab</a><p id="itch-account-detail">Open the official account game, then sign in with Google.</p></div><div class="leaf-entry-option local"><button id="itch-release-local" aria-describedby="itch-local-detail itch-progress-separation" type="button">Continue local play on itch</button><p id="itch-local-detail">Return to your café saved in this browser.</p></div></div><p id="itch-progress-separation" class="leaf-entry-note">Local and Google-account progress are separate. Local progress does not transfer automatically.</p></div></section>'''


def ordinary_entry_html(html):
    engine = '<script src="index.js"></script>'
    if html.count(BOOT) != 1 or html.count(engine) != 1 or html.count('<body>') != 1:
        raise ValueError('Original local shell boot contract changed')
    if PAGE_BEGIN in html or SCRIPT_BEGIN in html:
        raise ValueError('Release chooser was already packaged')
    controller = source_path(ROOT, 'web/little_leaf_itch_entry.js').read_text(encoding='utf-8')
    page = PAGE_BEGIN + '<style>' + entry_styles() + '</style>' + ENTRY + PAGE_END
    script = SCRIPT_BEGIN + '<script>' + controller + '</script>' + SCRIPT_END
    return html.replace(BOOT, GATED_BOOT).replace('<body>', '<body>' + page, 1).replace(engine, script + engine, 1)


def remove_ordinary_entry(html):
    """An explicitly requested historical preview uses its own single chooser."""
    if PAGE_BEGIN not in html and SCRIPT_BEGIN not in html:
        return html
    for begin, end in [(PAGE_BEGIN, PAGE_END), (SCRIPT_BEGIN, SCRIPT_END)]:
        if html.count(begin) != 1 or html.count(end) != 1:
            raise ValueError('Release chooser packaging markers changed')
        start, finish = html.index(begin), html.index(end)
        if finish < start:
            raise ValueError('Release chooser packaging order changed')
        html = html[:start] + html[finish + len(end):]
    if html.count(GATED_BOOT) != 1:
        raise ValueError('Release chooser boot contract changed')
    return html.replace(GATED_BOOT, BOOT)
