"""Run Build/Tiles checks; native_ui_runner documents the shared CLI contract."""
if __package__:
    from . import native_ui_runner as runner
else:
    import native_ui_runner as runner


def main():
    runner.main('res://tests/building/test_build_tiles_ui.gd', 'BUILD_TILES_UI_RESULT',
                'res://tests/diagnostics/capture_build_tiles_ui.gd', 'BUILD_TILES_CAPTURE_RESULT')


if __name__ == "__main__":
    main()
