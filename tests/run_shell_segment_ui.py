"""Run shell-segment checks; native_ui_runner documents the shared CLI contract."""
if __package__:
    from .tooling import native_ui_runner as runner
else:
    from tooling import native_ui_runner as runner


def main():
    runner.main('res://tests/building/test_shell_segment_ui.gd', 'SHELL_SEGMENT_UI_RESULT',
                'res://tests/building/test_shell_segment_ui.gd', 'SHELL_SEGMENT_UI_RESULT')


if __name__ == "__main__":
    main()
