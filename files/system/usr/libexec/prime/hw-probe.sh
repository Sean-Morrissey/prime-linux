#!/usr/bin/env bash
# Prime Linux — hardware probe.
#
# Deterministic. No model call, no network required, no writes outside the output
# file. This is what powers the sixty-second open: Prime reports what it found
# about the machine before it asks the user a single question.
#
# Usage:
#   hw-probe.sh                 # JSON to stdout
#   hw-probe.sh -o FILE         # JSON to FILE (interview target:
#                               #   ~/.config/prime/hardware.json)
#   hw-probe.sh --human         # the check-mark lines the interview UI prints
#
# Privacy: this reports capability, never identity. No MAC addresses, no serial
# numbers, no machine UUIDs, no Wi-Fi passwords. Everything it reports is
# something the user is about to see on their own screen anyway.
#
# Design rules:
#   * every external call is wrapped in `timeout` — a probe must never hang the
#     first-boot experience, even on a dead network or a stopped printer daemon
#   * a missing tool is not an error, it is an absent check
#   * values reach Python through the environment, never through string
#     interpolation, so quotes and unicode in a device or SSID name cannot
#     corrupt the JSON

set -uo pipefail

OUT=""
HUMAN=0
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output) OUT="${2:-}"; shift 2 ;;
    --human) HUMAN=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) shift ;;
  esac
done

TMO=3  # seconds per external probe

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- CPU / memory
CPU_MODEL="$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null)"
[ -n "$CPU_MODEL" ] || CPU_MODEL="$(awk -F': ' '/^Hardware|^cpu model/{print $2; exit}' /proc/cpuinfo 2>/dev/null)"
CPU_THREADS="$(nproc 2>/dev/null || echo 0)"
CPU_CORES="$(awk -F'[-:]' '/^cpu cores/{print $2; exit}' /proc/cpuinfo 2>/dev/null | tr -d ' ')"
[ -n "$CPU_CORES" ] || CPU_CORES="$CPU_THREADS"

MEM_TOTAL_KB="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)"
MEM_AVAIL_KB="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)"
MEM_TOTAL_GB="$(awk -v k="${MEM_TOTAL_KB:-0}" 'BEGIN{printf "%.1f", k/1048576}')"
MEM_AVAIL_GB="$(awk -v k="${MEM_AVAIL_KB:-0}" 'BEGIN{printf "%.1f", k/1048576}')"

# ---------------------------------------------------------------------- disk
DISK_JSON="$(df -B1 --output=source,target,fstype,size,avail 2>/dev/null | awk '
  NR > 1 && $3 ~ /^(ext4|btrfs|xfs|f2fs|vfat|overlay)$/ {
    src = $1
    if (src in seen) {
      # btrfs subvolumes and bind mounts share a source: keep the shortest path
      if (length($2) < length(path[src])) path[src] = $2
      next
    }
    seen[src] = 1
    order[++n] = src
    path[src] = $2; fstype[src] = $3; size[src] = $4; avail[src] = $5
  }
  END {
    printf "["
    for (i = 1; i <= n; i++) {
      s = order[i]
      printf "%s{\"mount\":\"%s\",\"fstype\":\"%s\",\"size_gb\":%.1f,\"free_gb\":%.1f}",
        (i > 1 ? "," : ""), path[s], fstype[s], size[s]/1073741824, avail[s]/1073741824
    }
    printf "]"
  }')"
[ -n "$DISK_JSON" ] || DISK_JSON="[]"
ROOT_FREE_GB="$(df -B1 --output=avail / 2>/dev/null | tail -1 | awk '{printf "%.0f", $1/1073741824}')"
ROOT_TOTAL_GB="$(df -B1 --output=size / 2>/dev/null | tail -1 | awk '{printf "%.0f", $1/1073741824}')"

# ------------------------------------------------------------------- display
DISPLAY_JSON="[]"
if have hyprctl && timeout "$TMO" hyprctl monitors -j >/dev/null 2>&1; then
  DISPLAY_JSON="$(PRIME_HYPR="$(timeout "$TMO" hyprctl monitors -j 2>/dev/null)" python3 - <<'PY'
import json, os
try:
    ms = json.loads(os.environ.get('PRIME_HYPR') or '[]')
except Exception:
    ms = []
print(json.dumps([{"name": m.get("name"), "width": m.get("width"),
                   "height": m.get("height"), "refresh": m.get("refreshRate"),
                   "primary": bool(m.get("focused")), "scale": m.get("scale")} for m in ms]))
PY
)"
elif have xrandr; then
  DISPLAY_JSON="$(timeout "$TMO" xrandr --query 2>/dev/null | awk '
    / connected/ {
      name=$1; primary=($2=="primary" ? "true" : "false"); res=""
      for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+x[0-9]+\+/) { split($i,a,"+"); res=a[1] }
      if (res != "") printf "%s{\"name\":\"%s\",\"resolution\":\"%s\",\"primary\":%s}",
        (n++ ? "," : ""), name, res, primary
    }
    BEGIN { printf "[" } END { printf "]" }')"
fi
if [ "$DISPLAY_JSON" = "[]" ]; then
  DISPLAY_JSON="$(python3 - <<'PY'
import glob, json, os
out = []
for modes_path in sorted(glob.glob('/sys/class/drm/card*-*/modes')):
    conn_dir = os.path.dirname(modes_path)
    conn = os.path.basename(conn_dir)
    if '-' not in conn or not conn.startswith('card'):
        continue
    try:
        modes = open(modes_path).read().split()
        state = open(os.path.join(conn_dir, 'status')).read().strip()
    except OSError:
        continue
    if state != 'connected' or not modes:
        continue
    out.append({'name': conn.split('-', 1)[1], 'resolution': modes[0],
                'primary': len(out) == 0})
print(json.dumps(out))
PY
)"
  [ -n "$DISPLAY_JSON" ] || DISPLAY_JSON="[]"
fi
DISPLAY_SUMMARY="$(PRIME_DISP="$DISPLAY_JSON" python3 - <<'PY'
import json, os
try:
    d = json.loads(os.environ.get('PRIME_DISP') or '[]')
except Exception:
    d = []
parts = []
for m in d:
    if m.get('resolution'):
        parts.append(str(m['resolution']))
    elif m.get('width'):
        parts.append(f"{m['width']}x{m['height']}")
if parts and len(set(parts)) == 1 and len(parts) > 1:
    print(f"{parts[0]} \u00d7{len(parts)}")
else:
    print(", ".join(parts[:3]))
PY
)"

# ----------------------------------------------------------------------- GPU
GPU_JSON="$(python3 - <<'PY'
import glob, json, os, re, subprocess

def clean(name):
    s = re.sub(r'^(Advanced Micro Devices, Inc\.?|NVIDIA Corporation|Intel Corporation|AMD/ATI)\s*', '', name)
    s = re.sub(r'\s*\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]', '', s)
    s = re.sub(r'\s*\(rev [0-9a-fA-F]+\)', '', s)
    s = s.replace('[AMD/ATI] ', '').strip(' -')
    return s

cards = []
try:
    out = subprocess.run(['lspci', '-nn'], capture_output=True, text=True, timeout=3).stdout
    for line in out.splitlines():
        if re.search(r'(VGA compatible controller|3D controller|Display controller)', line):
            raw = line.split(':', 2)[-1].strip()
            cards.append({'name': clean(raw)})
except Exception:
    pass
if not cards:
    for dev in sorted(glob.glob('/sys/class/drm/card*/device')):
        link = os.path.join(dev, 'driver')
        if not os.path.islink(link):
            continue
        driver = os.path.basename(os.path.realpath(link))
        if driver:
            cards.append({'driver': driver})
print(json.dumps(cards[:4]))
PY
)"
[ -n "$GPU_JSON" ] || GPU_JSON="[]"

# ------------------------------------------------------------------- network
NET_CONNECTED=false
NET_IFACE=""
NET_SUMMARY="not connected"
NET_TYPE=""
if have ip; then
  NET_IFACE="$(timeout "$TMO" ip -o -4 route show default 2>/dev/null | awk '{print $5; exit}')"
  if [ -n "$NET_IFACE" ]; then
    NET_CONNECTED=true
    NET_TYPE="ethernet"
    case "$NET_IFACE" in wl*) NET_TYPE="wifi" ;; esac
    if [ "$NET_TYPE" = "wifi" ]; then
      NET_SUMMARY="Wi-Fi connected"
      if have nmcli; then
        SSID="$(timeout "$TMO" nmcli -t -f GENERAL.CONNECTION device show "$NET_IFACE" 2>/dev/null | sed 's/^GENERAL.CONNECTION://')"
        if [ -n "$SSID" ] && [ "$SSID" != "--" ]; then NET_SUMMARY="Wi-Fi: $SSID"; fi
      fi
    else
      NET_SUMMARY="wired connection active"
    fi
  fi
fi

# ------------------------------------------------------ bluetooth and audio
BT_PRESENT=false
if [ -d /sys/class/bluetooth ] && [ -n "$(ls -A /sys/class/bluetooth 2>/dev/null)" ]; then
  BT_PRESENT=true
fi

AUDIO_OUT=false
AUDIO_IN=false
AUDIO_SUMMARY="no audio device found"
if have pactl; then
  [ -n "$(timeout "$TMO" pactl list short sinks 2>/dev/null)" ] && AUDIO_OUT=true
  [ -n "$(timeout "$TMO" pactl list short sources 2>/dev/null | grep -v monitor)" ] && AUDIO_IN=true
elif have wpctl; then
  if timeout "$TMO" wpctl status >/dev/null 2>&1; then AUDIO_OUT=true; AUDIO_IN=true; fi
elif [ -d /proc/asound ]; then
  if [ -n "$(ls -A /proc/asound/card* 2>/dev/null)" ]; then AUDIO_OUT=true; AUDIO_IN=true; fi
fi
if [ "$AUDIO_OUT" = true ]; then
  AUDIO_SUMMARY="output working"
  [ "$AUDIO_IN" = true ] && AUDIO_SUMMARY="output and microphone working"
fi

# ------------------------------------------------------------------ printing
PRINTERS=""
if have lpstat; then
  PRINTERS="$(timeout "$TMO" lpstat -p 2>/dev/null | awk '/^printer/{print $2}' | tr '\n' ' ')"
  PRINTERS="${PRINTERS% }"
fi

# ------------------------------------------------------------------- battery
BAT_PRESENT=false
BAT_PCT=""
BAT_STATE=""
for b in /sys/class/power_supply/BAT*; do
  [ -r "$b/capacity" ] || continue
  BAT_PRESENT=true
  BAT_PCT="$(cat "$b/capacity" 2>/dev/null)"
  BAT_STATE="$(cat "$b/status" 2>/dev/null)"
  break
done

# --------------------------------------------------------- OS / update state
KERNEL="$(uname -r)"
OS_NAME="$(awk -F= '/^PRETTY_NAME/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release 2>/dev/null)"
HOSTNAME_S="$(cat /etc/hostname 2>/dev/null || uname -n)"
IMAGE_VERSION=""
if have bootc; then
  IMAGE_VERSION="$(PRIME_BOOTC="$(timeout "$TMO" bootc status --json 2>/dev/null)" python3 - <<'PY'
import json, os
try:
    d = json.loads(os.environ.get('PRIME_BOOTC') or '{}')
except Exception:
    raise SystemExit
s = (d.get('status') or {}).get('booted') or d.get('booted') or {}
img = s.get('image') or {}
print(img.get('version') or img.get('digest') or '')
PY
)"
elif have rpm-ostree; then
  IMAGE_VERSION="$(PRIME_OSTREE="$(timeout "$TMO" rpm-ostree status --json 2>/dev/null)" python3 - <<'PY'
import json, os
try:
    d = json.loads(os.environ.get('PRIME_OSTREE') or '{}')
except Exception:
    raise SystemExit
deps = d.get('deployments') or []
print(deps[0].get('version', '') if deps else '')
PY
)"
fi

# -------------------------------------------------------------------- checks
# This list is exactly what the interview UI prints, in order.
CHECKS_JSON="$(PRIME_CPU="$CPU_MODEL" PRIME_MEM_TOTAL="$MEM_TOTAL_GB" \
  PRIME_MEM_AVAIL="$MEM_AVAIL_GB" PRIME_ROOT_TOTAL="$ROOT_TOTAL_GB" \
  PRIME_ROOT_FREE="$ROOT_FREE_GB" PRIME_DISPLAY="$DISPLAY_SUMMARY" \
  PRIME_NET="$NET_CONNECTED" PRIME_NET_SUMMARY="$NET_SUMMARY" \
  PRIME_BT="$BT_PRESENT" PRIME_AUDIO_OUT="$AUDIO_OUT" PRIME_AUDIO_IN="$AUDIO_IN" \
  PRIME_AUDIO_SUMMARY="$AUDIO_SUMMARY" PRIME_PRINTERS="$PRINTERS" \
  PRIME_BAT="$BAT_PRESENT" PRIME_BAT_PCT="$BAT_PCT" PRIME_BAT_STATE="$BAT_STATE" \
  PRIME_GPU="$GPU_JSON" python3 - <<'PY'
import json, os

e = os.environ.get

def num(x):
    try:
        return float(x)
    except Exception:
        return 0.0

cpu = e('PRIME_CPU', '')
mem_total, mem_avail = num(e('PRIME_MEM_TOTAL')), num(e('PRIME_MEM_AVAIL'))
root_total, root_free = num(e('PRIME_ROOT_TOTAL')), num(e('PRIME_ROOT_FREE'))
disp = e('PRIME_DISPLAY', '')
net = e('PRIME_NET') == 'true'
net_summary = e('PRIME_NET_SUMMARY', '')
audio_out = e('PRIME_AUDIO_OUT') == 'true'
audio_in = e('PRIME_AUDIO_IN') == 'true'
audio_summary = e('PRIME_AUDIO_SUMMARY', '')
printers = [p for p in e('PRIME_PRINTERS', '').split() if p]
try:
    gpus = json.loads(e('PRIME_GPU') or '[]')
except Exception:
    gpus = []

gpu_names = [g.get('driver') or g.get('name') or g.get('pci', '') for g in gpus]
free_pct = (root_free / root_total * 100) if root_total else 0

checks = [
    {"id": "cpu", "label": f"Processor: {cpu or 'unknown'}", "ok": bool(cpu),
     "detail": f"{mem_total:.0f} GB RAM" if mem_total else None},
    {"id": "memory", "label": f"Memory: {mem_total:.1f} GB total, {mem_avail:.1f} GB available",
     "ok": mem_avail > 0.5, "detail": None},
    {"id": "gpu", "label": "Graphics: " + (", ".join(gpu_names) if gpu_names else "unknown"),
     "ok": bool(gpu_names), "detail": None},
    {"id": "disk",
     "label": (f"Storage: {root_free:.0f} GB free of {root_total:.0f} GB" if root_total
               else "Storage: could not be read"),
     "ok": free_pct >= 10,
     "detail": f"{free_pct:.0f}% free" if root_total else None},
    {"id": "display", "label": "Display: " + (disp or "unknown"), "ok": bool(disp), "detail": None},
    {"id": "network", "label": "Network: " + (net_summary if net else "not connected"),
     "ok": net, "detail": None},
    {"id": "audio", "label": "Audio: " + (audio_summary if audio_out else "no output device found"),
     "ok": audio_out, "detail": None},
]
if e('PRIME_BT') == 'true':
    checks.append({"id": "bluetooth", "label": "Bluetooth: adapter present", "ok": True, "detail": None})
if printers:
    checks.append({"id": "printer", "label": "Printer: " + ", ".join(printers), "ok": True, "detail": None})
if e('PRIME_BAT') == 'true':
    pct, state = e('PRIME_BAT_PCT', ''), e('PRIME_BAT_STATE', '')
    checks.append({"id": "battery",
                   "label": f"Battery: {pct}% ({state.lower()})" if pct else "Battery: present",
                   "ok": True, "detail": None})
print(json.dumps(checks))
PY
)"
[ -n "$CHECKS_JSON" ] || CHECKS_JSON="[]"

# -------------------------------------------------------------------- payload
PAYLOAD="$(PRIME_HOST="$HOSTNAME_S" PRIME_OS="$OS_NAME" PRIME_KERNEL="$KERNEL" \
  PRIME_IMAGE="$IMAGE_VERSION" PRIME_CPU="$CPU_MODEL" PRIME_CORES="$CPU_CORES" \
  PRIME_THREADS="$CPU_THREADS" PRIME_MEM_TOTAL="$MEM_TOTAL_GB" \
  PRIME_MEM_AVAIL="$MEM_AVAIL_GB" PRIME_ROOT_TOTAL="$ROOT_TOTAL_GB" \
  PRIME_ROOT_FREE="$ROOT_FREE_GB" PRIME_DISKS="$DISK_JSON" PRIME_GPU="$GPU_JSON" \
  PRIME_DISP="$DISPLAY_JSON" PRIME_NET="$NET_CONNECTED" PRIME_IFACE="$NET_IFACE" \
  PRIME_NET_SUMMARY="$NET_SUMMARY" PRIME_NET_TYPE="$NET_TYPE" PRIME_BT="$BT_PRESENT" \
  PRIME_AUDIO_OUT="$AUDIO_OUT" PRIME_AUDIO_IN="$AUDIO_IN" \
  PRIME_AUDIO_SUMMARY="$AUDIO_SUMMARY" PRIME_PRINTERS="$PRINTERS" \
  PRIME_BAT="$BAT_PRESENT" PRIME_BAT_PCT="$BAT_PCT" PRIME_BAT_STATE="$BAT_STATE" \
  PRIME_CHECKS="$CHECKS_JSON" python3 - <<'PY'
import datetime, json, os

e = os.environ.get

def jloads(key, fallback):
    try:
        return json.loads(e(key) or '')
    except Exception:
        return fallback

def fnum(key):
    try:
        return float(e(key) or 0)
    except Exception:
        return 0.0

def inum(key):
    try:
        return int(float(e(key) or 0))
    except Exception:
        return 0

pct = e('PRIME_BAT_PCT', '')
payload = {
    "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "hostname": e('PRIME_HOST', ''),
    "os": {"name": e('PRIME_OS', ''), "kernel": e('PRIME_KERNEL', ''),
           "image": e('PRIME_IMAGE', '')},
    "cpu": {"model": e('PRIME_CPU', ''), "cores": inum('PRIME_CORES'),
            "threads": inum('PRIME_THREADS')},
    "memory": {"total_gb": fnum('PRIME_MEM_TOTAL'), "available_gb": fnum('PRIME_MEM_AVAIL')},
    "disk": {"root_total_gb": fnum('PRIME_ROOT_TOTAL'), "root_free_gb": fnum('PRIME_ROOT_FREE'),
             "filesystems": jloads('PRIME_DISKS', [])},
    "gpu": jloads('PRIME_GPU', []),
    "display": jloads('PRIME_DISP', []),
    "network": {"connected": e('PRIME_NET') == 'true', "interface": e('PRIME_IFACE', ''),
                "type": e('PRIME_NET_TYPE', ''), "summary": e('PRIME_NET_SUMMARY', '')},
    "bluetooth": {"adapter_present": e('PRIME_BT') == 'true'},
    "audio": {"output": e('PRIME_AUDIO_OUT') == 'true', "input": e('PRIME_AUDIO_IN') == 'true',
              "summary": e('PRIME_AUDIO_SUMMARY', '')},
    "printers": [p for p in e('PRIME_PRINTERS', '').split() if p],
    "battery": {"present": e('PRIME_BAT') == 'true',
                "percent": int(float(pct)) if pct else None,
                "state": (e('PRIME_BAT_STATE', '') or None)},
    "checks": jloads('PRIME_CHECKS', []),
}
print(json.dumps(payload, indent=2, ensure_ascii=False))
PY
)"

[ -n "$PAYLOAD" ] || { echo "prime: hw-probe failed to build output" >&2; exit 1; }

if [ "$HUMAN" = 1 ]; then
  printf '%s' "$PAYLOAD" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for c in d.get("checks", []):
    print(("  [ok] " if c.get("ok") else "  [!!] ") + c.get("label", ""))'
fi

if [ -n "$OUT" ]; then
  mkdir -p "$(dirname "$OUT")"
  if ! printf '%s\n' "$PAYLOAD" > "$OUT"; then
    echo "prime: could not write $OUT" >&2
    exit 1
  fi
  chmod 0644 "$OUT"
else
  printf '%s\n' "$PAYLOAD"
fi
exit 0
