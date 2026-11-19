#!/usr/bin/env bash
set -euo pipefail
{ uname -srm; lscpu | grep -E '^(Architecture|CPU\(s\)|Model name|Thread\(s\) per core):'; grep -E 'Cpus_allowed_list|Mems_allowed_list' /proc/self/status; cat /sys/fs/cgroup/cpu.max 2>/dev/null || true; printf 'image_os=%s\nimage_version=%s\n' "${ImageOS:-local}" "${ImageVersion:-unknown}"; } > "${1:?new host fingerprint output}"
