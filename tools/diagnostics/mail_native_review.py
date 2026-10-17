"""PR329-only full-game mail pixels. Mock transport; no player data or service."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASE = "f6ebeccd9fb8d2ded28895dc2f134c2a491f1ced"
OLD_PR_HEAD = "076747fe956f08e34cf18e67bf0b4339d1aac00b"
FIXTURE = "tests/persistence/test_support_mail_ui.gd"
FIXTURE_SHA = 'e707fa8d9d1637eb24e72f0b3a1a93186b9451c7bad7117a7320d5ebf14161a8'
REVIEWED_POSTIMAGES = {
    "game/scripts/main.gd": "a585cfa764e893bb974343fe8dc77d5365ff8b8ac7ae17be5dbf6167bdf47b78",
    "game/scripts/persistence/cafe_web_save.gd": "42eb9aea6a1bbaf79f29dc8c8b4b7a0a16852f9ace5a8e31f405a44492b62f0d",
    "game/scripts/ui/cafe_compact_ui.gd": "52dce3768a941a847d3d93684f6e8dda43c49546f183d06df286f11fac36c881",
    "game/scripts/ui/cafe_inbox.gd": "4e256a5ff15fde90f2b55787221a85100caefd4cc4b4075d38b7fa425c564c50",
    "game/scripts/ui/cafe_mail_frame.gd": "47696e4a6980a78bcf6db42856adcaedf731b80180a8d5f815e8eaeecbd4ab00",
    "game/scripts/ui/cafe_mail_gift_catalog.gd": "bac2c5c930be7ed59782584a6930e3ccbeebe4ee3ace9d39f644a5f2d0689e88",
    "game/scripts/ui/cafe_mail_recipients.gd": "ae3f114c3012a011b481863d531c221bbc167c8afced3b9676eb6db3ebafbef0",
    "game/scripts/ui/cafe_support_mail.gd": "ab9c2645795c58824ce20e60b69aae6b5eff391c21514142b38a75f55d792a2a",
    "platform/firebase/firestore.rules": "350806e48d676a2b09bcd9e938c6faddbccedacaac60125c1091931b136b7601",
    "platform/firebase/index.mjs": "93464f1e4c5d3e8ce8a4fd7ffd033c756e6ac844714915643cb39bdf233b60e1",
    "platform/firebase/package-lock.json": "2e9194dac6f50f02bce3b637763e3ca47b9ddca1371163e78c4a2aef6dbb96d9",
    "platform/firebase/package.json": "289a7bea0d6bffce1c4971af9753d7432a75be4ba468fef8a007a5f6d5dce79e",
    "platform/firebase/support_mail.test.mjs": "05017dc8f87f77e7e31211784d1a04c1b39ee6ad03dd967d6bb53be2142ddd31",
    "platform/firebase/support_mail_adapter.test.mjs": "887b4b971296b441acd750c910cbbb241597004a2366c38e3bb0cec717edf660",
    "platform/firebase/support_mail_audience.emulator.test.mjs": "e5cbd711b153c55bfc622fbfeccf38e09bbddb6ffbe80ff7a21060e7ab189134",
    "platform/firebase/support_mail_audience.test.mjs": "fef9f7eccbc4afb5bd114a74b208b371c8b0ca39a31d8fde3efe6ac597d5585a",
    "platform/firebase/support_mail_client.test.mjs": "a204137810e4fb0237b17470e34cb673308667bb71437bc9f46155fe8d0c0bb1",
    "platform/firebase/support_mail_contract.mjs": "998929ac9e46409270f978ab3176daaf880c429f5ecf0adcfd0ebb1ea4cc43ca",
    "platform/firebase/support_mail_contract.test.mjs": "29dc8e08b42c4fe5588dc7eac9d1dcc30d9724dfe45edc4e3aef06978095f2eb",
    "platform/firebase/support_mail_identity.test.mjs": "5823c8e73a13e3569d848305503939085912ce13f439d72cad3e47777fb075e6",
    "platform/firebase/support_mail_rules.test.mjs": "b6c2d43e393c1ccbe50f0bd28e4585ee6e020629253cce0bc940ac54201bd235",
    "platform/firebase/support_mail_service.mjs": "394e0debf6ffed2305235de2e560625fa273a89270aee08f71a4b86634a2900b",
    "platform/firebase/support_storage.test.mjs": "3f784fb0d8c842e677e6bb4e260de8155a07ecb1e8b8c632d9379142dafd2775",
    "platform/firebase/support_storage_fixture.mjs": "5160069fd12bcf9813cfc376499919d3f216cefe90f6a438ff1b1506da20c80b",
    "platform/firebase/support_storage_routing.rules.test.mjs": "4e6d76f7e0cefdcf3251827ee25ff7078b2390e402e0379f708bda8ac22d9539",
    "platform/web/little_leaf_crazygames_shell.html": "27fab3b123d464fc02bee8bb3a9187d16c2abfbf812eeb814afc91723bc6d21a",
    "platform/web/little_leaf_firebase.js": "d63b7ec0343aebb534e9c0b4f86197519ce7ac2dbf14476d510dcaeba550d027",
    "platform/web/little_leaf_firebase_boot.mjs": "39f7cbefab4a6155e79ff00537dde479b88b0b87b314d38014bcf1764ea32635",
    "platform/web/little_leaf_shell.html": "748042f6d140268a32268f090bee094304509d4a42ec59028694942d7babd273",
    "platform/web/little_leaf_vault.js": "34a9d8ab24e1b8aab5cddd9a7da5d3f596d9b2c0ceaf798fe91d32894a73709c"
}
SIZES = ("1360x880", "390x844", "844x390")
SURFACES = ("selected-review", "selected-attachments", "all-review", "inbox-letter", "inbox-attachments")


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args]).decode().strip()


def verify_postimages(changed, root):
    require(REVIEWED_POSTIMAGES and set(changed) == set(REVIEWED_POSTIMAGES), "Unreviewed mail production paths")
    require(all(sha(root / name) == value for name, value in REVIEWED_POSTIMAGES.items()), "Mail postimage changed")
    require(sha(root / FIXTURE) == FIXTURE_SHA, "Mail capture fixture changed")


def verify_checkout(expected_head):
    require(git("rev-parse", "HEAD") == expected_head, "Checkout does not match PR head")
    for parent in (BASE, OLD_PR_HEAD):
        require(subprocess.run(["git", "-C", str(ROOT), "merge-base", "--is-ancestor", parent, "HEAD"]).returncode == 0,
                "Preserve current main and original PR329 history")
    require(not git("status", "--porcelain", "--untracked-files=no"), "Tracked source must be clean")
    changed = git("diff", "--name-only", BASE, "HEAD", "--", "game", "platform").splitlines()
    verify_postimages(changed, ROOT)


def check_frames(folder, log):
    results = [json.loads(line.split(" ", 1)[1]) for line in log.splitlines()
               if line.startswith("SUPPORT_MAIL_UI_RESULT ")]
    require(len(results) == 1 and results[0].get("failures") == [] and results[0].get("checks", 0) > 100,
            "Missing or failed full-game mail checks")
    require("OpenGL API" in log and "Compatibility" in log, "Actual native GL renderer required")
    receipt = json.loads((folder / "capture-receipt.json").read_text())
    require(receipt.get("synthetic_only") is True and receipt.get("player_save_used") is False
            and receipt.get("rendered_pngs") is True and receipt.get("display") == "X11"
            and receipt.get("renderer") == "gl_compatibility", "Actual isolated capture receipt required")
    expected = {surface + "-" + size + ".png": tuple(map(int, size.split("x")))
                for surface in SURFACES for size in SIZES}
    require({p.name for p in folder.glob("*.png")} == set(expected), "Incomplete or unexpected mail frames")
    rows = {}
    for name, size in expected.items():
        data = (folder / name).read_bytes()
        require(data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) > 1000 and
                (int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")) == size,
                "Invalid or wrongly sized mail PNG: " + name)
        rows[name] = {"sha256": sha(folder / name), "bytes": len(data), "size": size}
    return {"result": results[0], "receipt": receipt, "frames": rows, "pixels_inspected": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    verify_checkout(args.expected_head)
    if args.verify_only:
        print("Exact reviewed PR329 production and UI fixture bindings passed.")
        return
    require(args.godot and args.output, "Native capture requires engine and output paths")
    native = module("retained_native", ROOT / "tools/diagnostics/storage_native_review.py")
    require(sha(args.godot) == native.ENGINE_SHA, "Official engine binary differs")
    atlas = module("mail_atlas", ROOT / "tools/qualification/verify_prebaked_atlases.py")
    manifest = json.loads((ROOT / "game/data/prebaked_atlas_manifest.json").read_text())
    closure = atlas.sources()
    native.check_closure(closure, manifest)
    for name in native.NAMES:
        require(all(manifest["atlases"][name][k] == v for k, v in atlas.asset(name).items()), "Atlas PNG/import bytes changed")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    require(not any(output.iterdir()) and not output.is_relative_to(ROOT), "Use a fresh evidence directory outside checkout")
    report = {"head": args.expected_head, "tree": git("rev-parse", "HEAD^{tree}"), "base": BASE,
              "fixture_sha256": FIXTURE_SHA, "reviewed_postimages": REVIEWED_POSTIMAGES,
              "engine_sha256": sha(args.godot), "producer_count": len(closure), "closure_sha256": native.CLOSURE_SHA,
              "atlas_regenerated": False, "manifest_written": False, "player_save_used": False,
              "mock_transport": True, "status": "running", "steps": [], "pixels_inspected": False}

    def save():
        (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(label, command, env):
        path = output / (label + ".log")
        code, reason = native.execute_native(command, env, path)
        text = path.read_text(errors="replace")
        report["steps"].append({"label": label, "exit_code": code, "stop_reason": reason, "log_sha256": sha(path)})
        save()
        require(code == 0 and not reason and "ERROR:" not in text, "Native mail stage failed: " + label)
        return text

    save()
    try:
        stage = module("mail_project", ROOT / "tools/build/project_layout.py").stage_project
        with tempfile.TemporaryDirectory(prefix="mail-native-saveguard-") as temporary:
            temp = Path(temporary); project = temp / "project"
            stage(ROOT, project, tests=True, ignore=shutil.ignore_patterns(".git", ".godot", "__pycache__"))
            originals = {p.relative_to(project).as_posix(): sha(p) for p in project.rglob("*") if p.is_file()}
            config = project / "project.godot"
            config.write_text(config.read_text().replace("[application]", '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="mail-native-saveguard"', 1))
            controller = project / "scripts/persistence/cafe_web_save.gd"
            old = 'const STAGING_FILE="/tmp/little_leaf_vault_staging.json"'
            require(old in controller.read_text(), "Mail staging contract changed")
            controller.write_text(controller.read_text().replace(old, 'const STAGING_FILE="user://generated_mail_stage.json"'))
            report["disposable_overrides"] = {n: sha(project / n) for n in ("project.godot", "scripts/persistence/cafe_web_save.gd")}
            env = os.environ.copy()
            for key in ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                folder = temp / "profile" / key.lower(); folder.mkdir(parents=True); env[key] = str(folder)
            env["LIBGL_ALWAYS_SOFTWARE"] = "1"
            engine = [str(args.godot.resolve()), "--path", str(project), "--audio-driver", "Dummy"]
            runtime = config.read_text()
            require("[editor]" not in runtime, "Import policy changed")
            config.write_text(runtime + "\n[editor]\nimport/use_multiple_threads=false\n")
            try:
                run("import", engine + ["--headless", "--editor", "--import", "--quit"], env)
            finally:
                config.write_text(runtime)
            frames = output / "mail"; frames.mkdir()
            log = run("mail-native", engine + ["--rendering-method", "gl_compatibility", "--script", "res://" + FIXTURE,
                "--", "--visual-qa", "--fresh-review", "--skip-intro", "--skip-tutorial", "--capture-dir=" + str(frames)], env)
            report["mail"] = check_frames(frames, log)
            require(all(sha(project / n) == value for n, value in originals.items() if n not in report["disposable_overrides"]),
                    "Staged source or assets changed during capture")
            require(not list((temp / "profile").rglob("little_leaf_cafe_layout_motion_v15.json")), "Unexpected normal save")
        require(not git("status", "--porcelain", "--untracked-files=no"), "Tracked source changed")
        report["status"] = "rendered_pending_pixel_review"
    except Exception as error:
        report["status"] = "failed"; report["error"] = str(error)
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
