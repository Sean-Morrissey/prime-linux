#!/usr/bin/env bash

# Prime PC Health Check Tool (Apple Style)
# Provides real-time stats for CPU, GPU, RAM, Disk and Net

# Configuration
GPU_SMI="/opt/rocm/bin/rocm-smi"

get_cpu_temp() {
    # Check thermal_zone0
    if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
        temp=$(cat "/sys/class/thermal/thermal_zone0/temp")
        echo "$((temp / 1000))°C"
        return
    fi
    # Check hwmon fallback (e.g., k10temp for AMD or coretemp for Intel)
    for hw in /sys/class/hwmon/hwmon*/temp1_input; do
        if [ -f "$hw" ]; then
            temp=$(cat "$hw")
            echo "$((temp / 1000))°C"
            return
        fi
    done
    echo "N/A"
}

get_gpu_stats() {
    if [ -x "$GPU_SMI" ]; then
        gpu_info=$($GPU_SMI --showuse --showtemp --json 2>/dev/null)
        usage=$(echo "$gpu_info" | jq -r '.card0["GPU use (%)"] // "0"' 2>/dev/null)
        temp=$(echo "$gpu_info" | jq -r '.card0["Temperature (Sensor edge) (C)"] // "0"' 2>/dev/null)
        echo "GPU: ${usage}% @ ${temp}°C"
    else
        echo "GPU: N/A"
    fi
}

get_ram_usage() {
    free -h | awk '/^Mem:/ {print $3 "/" $2}'
}

get_disk_usage() {
    df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}'
}

# Main Loop (for CLI usage) or Single Output (for Waybar)
if [ "$1" == "--waybar" ]; then
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
    cpu_temp=$(get_cpu_temp)
    ram_usage=$(free | awk '/^Mem:/ {printf("%.1fGB", $3/1024/1024)}')
    echo "{\"text\": \"󰻠 $cpu_usage | 󰍛 $ram_usage\", \"tooltip\": \"System Health:\nCPU: $cpu_usage @ $cpu_temp\nRAM: $(get_ram_usage)\nDisk: $(get_disk_usage)\n$(get_gpu_stats)\", \"class\": \"health\"}"
else
    clear
    echo "-----------------------------------"
    echo "  PRIME PC HEALTH CHECK - 2026"
    echo "-----------------------------------"
    echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4"%"}')"
    echo "CPU Temp:  $(get_cpu_temp)"
    echo "RAM Usage: $(get_ram_usage)"
    echo "Disk (/):  $(get_disk_usage)"
    echo "$(get_gpu_stats)"
    echo "Uptime:    $(uptime -p)"
    echo "-----------------------------------"
    read -p "Press enter to exit..."
fi
