import sys
"""Run Build/Tiles regressions and optional native GL screenshots in disposable profiles.

Example: python3 tests/run_build_tiles_ui.py --output /tmp/build-tiles-qa --native
GODOT_BIN selects Godot 4.6.3. Native mode uses DISPLAY or an isolated Xvfb.
--import-cache SOURCE_PROJECT reuses only imported assets after exact SHA256
validation of all asset inputs and import metadata; it is not a clean import.
Never reads player profiles or the real Web staging file. Source is not modified.
"""
if __package__:
    from . import native_ui_runner as runner
else:
    import native_ui_runner as runner


def main():
    runner.main('res://tests/test_build_tiles_ui.gd', 'BUILD_TILES_UI_RESULT',
                'res://tests/diagnostics/capture_build_tiles_ui.gd', 'BUILD_TILES_CAPTURE_RESULT')


if __name__ == "__main__":
    main()
