#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh"   # never the real home or session (tests/sandbox.sh)
# tests/check-gpu-detect.sh — install.sh's hardware.conf picks the GPU that runs the
# desktop (the one that drew the boot screen), and only writes NVIDIA's settings when
# NVIDIA's own driver is installed. Fake sysfs trees; nothing on this machine is read.
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; fail=0
eval "$(sed -n '/^gpu_hw_env() {/,/^}/p' install.sh)"
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
pci() {   # pci <tree> <vendor> <boot_vga> — one fake device
    local d="$T/$1/$RANDOM$RANDOM"; mkdir -p "$d"; echo "0x$2" > "$d/vendor"; echo "$3" > "$d/boot_vga"
}
INTEL='00:02.0 VGA compatible controller [0300]: Intel Corporation Alder Lake-P GT2 [8086:46a6]'
NV='01:00.0 3D controller [0302]: NVIDIA Corporation GA107M [10de:25a2]'
AMD='03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 44 [1002:7590]'
run() { PRIME_PCI_ROOT="$T/$1" PRIME_NVIDIA_DRIVER="$2" gpu_hw_env "$3"; }

pci laptop 8086 1; pci laptop 10de 0
ck "Intel + NVIDIA laptop: Intel's video decode"        "[ \"\$(run laptop 1 \"\$INTEL
\$NV\")\" = 'env = LIBVA_DRIVER_NAME,iHD' ]"
ck "...and no NVIDIA settings"                         "! run laptop 1 \"\$INTEL
\$NV\" | grep -q nvidia"
pci desk 8086 0; pci desk 10de 1
ck "desktop on NVIDIA (CPU graphics on): NVIDIA's set" "run desk 1 \"\$INTEL
\$NV\" | grep -q 'no_hardware_cursors = true'"
ck "NVIDIA on nouveau: nothing NVIDIA-only"           "[ -z \"\$(run desk 0 \"\$NV\")\" ]"
pci amd 1002 1
ck "AMD: radeonsi"                                     "[ \"\$(run amd 0 \"\$AMD\")\" = 'env = LIBVA_DRIVER_NAME,radeonsi' ]"
mkdir -p "$T/none"
ck "no boot_vga (VM): first display line decides"     "[ \"\$(run none 0 \"\$AMD\")\" = 'env = LIBVA_DRIVER_NAME,radeonsi' ]"
ck "Intel isn't read as AMD (\"ati\" in Corporation)" "[ \"\$(run none 0 \"\$INTEL\")\" = 'env = LIBVA_DRIVER_NAME,iHD' ]"
ck "no GPU at all: nothing, and no error"              "[ -z \"\$(run none 0 '')\" ]"
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
