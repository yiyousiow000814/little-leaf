# Development

## Run

Open `project.godot` in Godot **4.6.3**, use **GL Compatibility**, and press **F5**. From the repository root, `godot --path .` also starts the game.

Normal play reads and writes local saves. Use a separate profile and copied saves for experiments.

## Test

With Python 3 and Godot 4.6.3 on Linux or macOS:

```sh
python3 tests/run_integration_candidate.py --output /tmp/little-leaf-qa
```

Use a new output directory for each run. Set `GODOT_BIN` if the executable is not named `godot`. Add `--only` followed by test names for a focused run; `--help` lists the choices.

The runner uses a disposable project and generated saves. It checks engine behavior, not browser storage or rendered visuals.

## Build

For automated builds and publishing, see [GitHub Web builds and releases](github-release.md).

Use the **Web** export preset with Godot 4.6.3 and its matching non-threaded release template at `export_templates/web_nothreads_release.zip`.

```sh
mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html
cp docs/third-party/GODOT-AA-LICENSE.txt build/web/
```

Serve the exported folder over HTTP to test it. Keep the license notice, custom HTML shell and export include/exclude rules.

## Project files

Keep asset inputs, `.import` settings and script `.uid` files tracked. Some fonts and HUD assets use `importer="keep"`; preserve those settings. Generated `.godot/` files, exports and player saves stay out of Git.

See [assets and licenses](licenses.md) before reusing or distributing content. Older review notes and recovery records are in the [archive](archive/README.md).
