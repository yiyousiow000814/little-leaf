"""Launch the opt-in native game using a copied project and disposable profile."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from project_layout import stage_project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="little-leaf-navigation-review-",
                                     ignore_cleanup_errors=True) as directory:
        temp = Path(directory)
        project = temp / "project"
        stage_project(ROOT, project, ignore=shutil.ignore_patterns(
            ".git", ".godot", "qa-project", "__pycache__", "export", "exports"))
        env = os.environ.copy()
        for key in ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME",
                    "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            profile = temp / "profile" / key.lower()
            profile.mkdir(parents=True)
            env[key] = str(profile)
        # Import the copy; the original source and user profile are untouched.
        subprocess.run([args.godot, "--headless", "--audio-driver", "Dummy",
                        "--path", str(project), "--editor", "--import", "--quit"],
                       env=env, check=True)
        print("Native navigation review: temporary profile; saves suppressed.", flush=True)
        subprocess.run([args.godot, "--path", str(project), "--",
                        "--fresh-review", "--navigation-candidate"], env=env, check=True)


if __name__ == "__main__":
    main()
