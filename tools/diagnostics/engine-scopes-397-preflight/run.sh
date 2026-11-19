#!/usr/bin/env bash
# Bounded build-only diagnostic. No application launch, full link, upload or privileges.
set -euo pipefail
d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
w="$RUNNER_TEMP/ll397-engine-partial-private"
out="$RUNNER_TEMP/ll397-engine-partial-public/summary.json"
fail() { python3 -B "$d/guard.py" summary "$out" not_qualified "$1"; }
mkdir -m 700 "$w"
fail source_guard
python3 -B "$d/guard.py" event . > "$w/event.log" 2>&1
fail capacity
python3 -B "$d/guard.py" capacity "$w" initial > "$w/capacity-initial.json"
fail host_dependencies
for name in curl git python3 sh bash pkg-config readelf wayland-scanner timeout sha256sum; do command -v "$name" >/dev/null; done
export HOME="$w/home" XDG_CACHE_HOME="$w/cache" TMPDIR="$w/tmp" PYTHONDONTWRITEBYTECODE=1
mkdir "$HOME" "$XDG_CACHE_HOME" "$TMPDIR"
for a in source sdk accesskit scons; do
  fail download
  url="$(python3 -B "$d/guard.py" asset "$a")"
  curl --proto '=https' --proto-redir '=https' --max-time 75 -fSsL -- "$url" > "$w/$a.archive"
  fail unpack
  python3 -B "$d/guard.py" unpack "$a" "$w/$a.archive" "$w/$a" > "$w/unpack-$a.log" 2>&1
done
fail capacity
python3 -B "$d/guard.py" capacity "$w" staged > "$w/capacity.json"
src="$w/source/godot-4.6.3-stable"
sdk="$w/sdk/x86_64-godot-linux-gnu_sdk-buildroot"
mapfile -t access_roots < <(find "$w/accesskit" -mindepth 1 -maxdepth 1 -type d -name 'accesskit-c-*')
[[ ${#access_roots[@]} -eq 1 ]]
access="${access_roots[0]}"
fail patch
cd "$src"
sha256sum --status -c "$d/source.sha256"
git apply --check "$d/engine-scopes.review.patch"
git apply "$d/engine-scopes.review.patch"
fail sdk
test -d "$access"; test -f "$sdk/relocate-sdk.sh"
(cd "$sdk"; bash ./relocate-sdk.sh > "$w/sdk-relocate.log" 2>&1)
export PATH="$sdk/bin:$PATH"
cc="$sdk/bin/x86_64-godot-linux-gnu-gcc"
cxx="$sdk/bin/x86_64-godot-linux-gnu-g++"
[[ "$("$cxx" -dumpmachine)" =~ ^x86_64-[[:alnum:]_-]+-linux-gnu$ && "$("$cxx" -dumpfullversion)" == 13.2.0 ]]
export PYTHONPATH="$w/scons"
scons_cmd=(python3 -B -c 'from SCons.Script.Main import main; main()')
"${scons_cmd[@]}" --version > "$w/scons-version.log" 2>&1
grep -Eq '(^|[^0-9])4\.10\.1([^0-9]|$)' "$w/scons-version.log"
flags=(platform=linuxbsd arch=x86_64 target=editor production=yes x11=yes opengl3=yes
       "accesskit_sdk_path=$access" cppdefines=LL397_ENGINE_DIAG
       "CC=$cc" "CXX=$cxx" compiledb=yes verbose=yes progress=no redirect_build_objects=no)
fail db
timeout --kill-after=5s 120s "${scons_cmd[@]}" "${flags[@]}" compiledb > "$w/db.log" 2>&1
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
python3 -B "$d/guard.py" summary "$out" passed object_verify "$w/capacity.json"
