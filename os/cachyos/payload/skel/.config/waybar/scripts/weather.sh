#!/usr/bin/env bash
# Weather module for waybar — auto-detects location via wttr.in

CACHE_FILE="/tmp/waybar-weather-cache"
CACHE_AGE=900  # 15 minutes

# Use cache if fresh enough
if [ -f "$CACHE_FILE" ] && [ $(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") )) -lt $CACHE_AGE ]; then
    cat "$CACHE_FILE"
    exit 0
fi

DATA=$(curl -s --max-time 5 "wttr.in/?format=j1" 2>/dev/null)

if [ -z "$DATA" ]; then
    echo '{"text": "? °F", "tooltip": "Weather unavailable", "class": "unavailable"}'
    exit 0
fi

TEMP=$(echo "$DATA" | python3 -c "
import sys, json
d = json.load(sys.stdin)
c = d['current_condition'][0]
print(c['temp_F'])
" 2>/dev/null)

DESC=$(echo "$DATA" | python3 -c "
import sys, json
d = json.load(sys.stdin)
c = d['current_condition'][0]
print(c['weatherDesc'][0]['value'])
" 2>/dev/null)

FEELS=$(echo "$DATA" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d['current_condition'][0]['FeelsLikeF'])
" 2>/dev/null)

HIGH=$(echo "$DATA" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d['weather'][0]['maxtempF'])
" 2>/dev/null)

LOW=$(echo "$DATA" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d['weather'][0]['mintempF'])
" 2>/dev/null)

# Weather icon
ICON="󰖙"
case $(echo "$DESC" | tr '[:upper:]' '[:lower:]') in
    *thunder*|*storm*)    ICON="󰖓" ;;
    *snow*|*sleet*|*blizzard*) ICON="󰖘" ;;
    *rain*|*drizzle*|*shower*) ICON="󰖗" ;;
    *fog*|*mist*|*haze*)  ICON="󰖑" ;;
    *overcast*)           ICON="󰖐" ;;
    *cloud*)              ICON="󰖕" ;;
    *clear*|*sunny*)      ICON="󰖙" ;;
esac

RESULT="{\"text\": \"${ICON} ${TEMP}°F\", \"tooltip\": \"${DESC}\\nFeels like ${FEELS}°F  ·  High ${HIGH}°F  ·  Low ${LOW}°F\", \"class\": \"weather\"}"

echo "$RESULT" | tee "$CACHE_FILE"
