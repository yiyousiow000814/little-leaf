#!/usr/bin/env bash
# Bounded private engine attribution. No executable, cache, raw report or privileged work.
set -euo pipefail
d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
checkout="$(pwd -P)"
base_path="$PATH"
w="$RUNNER_TEMP/ll397-engine-full-v1-private"
out="$RUNNER_TEMP/ll397-engine-full-v1-public/summary.json"
fail() { python3 -B "$d/guard.py" summary "$out" not_qualified "$1"; }
mkdir -m 700 "$w"
fail source_guard
python3 -B "$d/guard.py" event . > "$w/event.log" 2>&1
fail capacity
python3 -B "$d/guard.py" capacity "$w" initial > "$w/capacity-initial.json"
fail host_base_tools
for name in curl git python3 sh bash readelf tar find timeout sha256sum; do command -v "$name" >/dev/null; done
export HOME="$w/home" XDG_CACHE_HOME="$w/cache" TMPDIR="$w/tmp" PYTHONDONTWRITEBYTECODE=1
mkdir "$HOME" "$XDG_CACHE_HOME" "$TMPDIR"
for a in source sdk accesskit scons; do
  fail "${a}_download"
  url="$(python3 -B "$d/guard.py" asset "$a")"
  curl --proto '=https' --proto-redir '=https' --max-time 75 -fSsL -- "$url" > "$w/$a.archive"
  fail "${a}_checksum"
  python3 -B "$d/guard.py" asset_check "$a" "$w/$a.archive" > "$w/checksum-$a.log" 2>&1
  fail "${a}_manifest"
  python3 -B "$d/guard.py" manifest "$a" "$w/$a.archive" "$w/$a" > "$w/manifest-$a.log" 2>&1
  fail "${a}_extract"
  python3 -B "$d/guard.py" extract "$a" "$w/$a.archive" "$w/$a" > "$w/extract-$a.log" 2>&1
done
fail capacity
python3 -B "$d/guard.py" capacity "$w" staged > "$w/capacity.json"
src="$w/source/godot-4.6.3-stable"
sdk="$w/sdk/x86_64-godot-linux-gnu_sdk-buildroot"
fail accesskit_root
mapfile -t access_roots < <(find "$w/accesskit" -mindepth 1 -maxdepth 1 -type d -name 'accesskit-c-*')
[[ ${#access_roots[@]} -eq 1 ]]
access="${access_roots[0]}"
fail patch
cd "$src"
sha256sum --status -c "$d/source.sha256"
git apply --check "$d/engine-scopes.review.patch"
git apply "$d/engine-scopes.review.patch"
fail sdk_relocate
test -d "$access"; test -f "$sdk/relocate-sdk.sh"
(cd "$sdk"; bash ./relocate-sdk.sh > "$w/sdk-relocate.log" 2>&1)
export PATH="$sdk/bin:$PATH"
fail sdk_pkg_config
[[ "$(command -v pkg-config)" == "$sdk/bin/pkg-config" ]]
timeout 5s pkg-config --version > "$w/sdk-pkgconfig.log" 2>&1
fail sdk_compiler
cc="$sdk/bin/x86_64-godot-linux-gnu-gcc"
cxx="$sdk/bin/x86_64-godot-linux-gnu-g++"
[[ "$("$cxx" -dumpmachine)" =~ ^x86_64-[[:alnum:]_-]+-linux-gnu$ && "$("$cxx" -dumpfullversion)" == 13.2.0 ]]
fail scanner_checksum
mkdir "$w/private-bin"
scanner_sha=e955c99dd2badc09297e580cce9132c58a2bdd04e9ecd5b2df4696ae87ac87d2
scanner="$w/private-bin/wayland-scanner"
candidate=/usr/bin/wayland-scanner
if [[ -x $candidate ]] && printf '%s  %s\n' "$scanner_sha" "$candidate" | sha256sum --status -c -; then
   cat "$candidate" > "$scanner"
else
   fail host_deb_tool
   command -v dpkg-deb >/dev/null
   fail scanner_download
   url="$(python3 -B "$d/guard.py" asset scanner)"
   curl --proto '=https' --proto-redir '=https' --max-time 20 -fSsL -- "$url" > "$w/wayland.deb"
   fail scanner_checksum
   python3 -B "$d/guard.py" asset_check scanner "$w/wayland.deb"
   dpkg-deb --fsys-tarfile "$w/wayland.deb" | tar -xOf - ./usr/bin/wayland-scanner > "$scanner"
fi
printf '%s  %s\n' "$scanner_sha" "$scanner" | sha256sum --status -c -
chmod 700 "$scanner"
fail scanner_dependency
env -u LD_LIBRARY_PATH -u LD_PRELOAD LC_ALL=C timeout 5s /lib64/ld-linux-x86-64.so.2 --list "$scanner" > "$w/scanner-loader.log" 2>&1
python3 -B "$d/guard.py" loader "$w/scanner-loader.log"
fail scanner_smoke
unset LD_LIBRARY_PATH LD_PRELOAD
export PATH="$w/private-bin:$PATH"
[[ "$(command -v wayland-scanner)" == "$scanner" ]]
timeout 5s wayland-scanner -v > "$w/scanner-version.log" 2>&1
grep -Fxq 'wayland-scanner 1.22.0' "$w/scanner-version.log"
xml=thirdparty/wayland-protocols/stable/xdg-shell/xdg-shell.xml
timeout 10s wayland-scanner -c client-header < "$xml" > "$w/xdg-check.h"
timeout 10s wayland-scanner -c private-code < "$xml" > "$w/xdg-check.c"
grep -q 'xdg_wm_base_interface' "$w/xdg-check.h"
grep -q 'xdg_wm_base_interface' "$w/xdg-check.c"
printf '%s  %s\n' 5084e76386f6c3959bee957a784c57de204be0de3f57533ce07b4be0617b171a "$xml" | sha256sum --status -c -
printf '%s  %s\n' 3dbb4e124d5eff8925c0d04de0d5c0b6c44a9cedd44b19cd5b6ef31fa027ab1e "$w/xdg-check.h" | sha256sum --status -c -
printf '%s  %s\n' ca9058caf606fcf97a04a8fcf9255cb7fd3146b6d3dbbff2b5ad36c4a7a2f7aa "$w/xdg-check.c" | sha256sum --status -c -
export PYTHONPATH="$w/scons"
scons_cmd=(python3 -B -c 'from SCons.Script.Main import main; main()')
"${scons_cmd[@]}" --version > "$w/scons-version.log" 2>&1
grep -Eq '(^|[^0-9])4\.10\.1([^0-9]|$)' "$w/scons-version.log"
flags=(platform=linuxbsd arch=x86_64 target=editor production=yes x11=yes wayland=yes opengl3=yes
       "accesskit_sdk_path=$access" cppdefines=LL397_ENGINE_DIAG
       "CC=$cc" "CXX=$cxx" compiledb=yes verbose=yes progress=no redirect_build_objects=no)
fail db
timeout --kill-after=5s 120s "${scons_cmd[@]}" "${flags[@]}" compiledb > "$w/db.log" 2>&1
fail feature_mode
python3 -B "$d/partial_targets.py" "$src" "$cxx" "$src/compile_commands.json" > "$w/targets"
mapfile -t targets < "$w/targets"
[[ ${#targets[@]} -eq 5 ]]
fail dry_run
timeout --kill-after=5s 90s "${scons_cmd[@]}" "${flags[@]}" -n -Q "${targets[@]}" > "$w/dry.log" 2>&1
python3 -B "$d/guard.py" dry "$w/dry.log" "$w/targets" "${cxx##*/}"
fail partial_compile
timeout --kill-after=5s 720s "${scons_cmd[@]}" "${flags[@]}" -j2 "${targets[@]}" > "$w/compile.log" 2>&1
fail object_verify
for obj in "${targets[@]}"; do
  test -s "$obj"
  LC_ALL=C readelf -h "$obj" | grep -E 'Type:.*REL'
  LC_ALL=C readelf -h "$obj" | grep -E 'Machine:.*X86-64'
done > "$w/object-check.log"
test ! -d bin || ! find bin -name 'godot*' -type f -print -quit | grep -q .
fail full_capacity
python3 -B "$d/guard.py" capacity "$w" full > "$w/full-capacity.json"
fail full_compile
timeout --kill-after=15s 4200s "${scons_cmd[@]}" "${flags[@]}" -j4 > "$w/full-build.log" 2>&1
fail binary_abi
candidate="$src/bin/godot.linuxbsd.editor.x86_64"
test -f "$candidate" && test ! -L "$candidate" && test -x "$candidate"
LC_ALL=C readelf -h "$candidate" > "$w/binary-elf.log"
grep -E 'Class:.*ELF64' "$w/binary-elf.log" >/dev/null
grep -E 'Machine:.*X86-64' "$w/binary-elf.log" >/dev/null
LC_ALL=C readelf -l "$candidate" | grep -F '/lib64/ld-linux-x86-64.so.2' >/dev/null
fail stage_binding
export PATH="$base_path"
unset PYTHONPATH
cd "$checkout"
python3 -B "$d/prepare.py" "$checkout/product" "$w/stage" > "$w/stage.json" 2> "$w/stage.log"
fail official_binary
python3 -B "$checkout/product/tools/ci/install_tools.py" godot --native-only --output "$w/tools" > "$w/install.log" 2>&1
stock="$w/tools/godot"
printf 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3  %s\n' "$stock" | sha256sum --status -c -
stock_version="$(timeout 5s "$stock" --version)"
candidate_version="$(timeout 5s "$candidate" --version)"
[[ "$stock_version" =~ ^4\.6\.3\.stable\.[^.]+\.7d41c59c[0-9a-f]*$ && "$candidate_version" =~ ^4\.6\.3\.stable\.[^.]+\.7d41c59c[0-9a-f]*$ ]]
fail import
export HOME="$w/stage/private/home" XDG_DATA_HOME="$w/stage/private/data" XDG_CONFIG_HOME="$w/stage/private/config" XDG_CACHE_HOME="$w/stage/private/cache"
timeout --kill-after=5s 180s "$stock" --headless --editor --import --path "$w/stage/game" > "$w/import.log" 2>&1
! grep -Eq 'SCRIPT ERROR:|Parse Error' "$w/import.log"
# Keep fixture state/import equivalent in all runs. Any app-emitted raw output is private.
fail display
command -v xvfb-run >/dev/null && command -v Xvfb >/dev/null && command -v xauth >/dev/null
fail session
timeout --kill-after=5s 360s xvfb-run -a -s '-screen 0 1600x1000x24' bash "$d/measure.sh" "$w" "$stock" "$candidate" > "$w/sessions.log" 2>&1
fail qualification
python3 -B "$d/qualify.py" "$w" "$candidate" "$out" > "$w/qualification.log" 2>&1
