#!/usr/bin/env bash

# Colors (Prime Palette)
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
GREEN='\033[0;32m'
NC='\033[0m'

clear
echo -e "${BLUE}-----------------------------------${NC}"
echo -e "  ${CYAN}PRIME OS${NC} - ${BLUE}HYPRLAND COMMANDS${NC}"
echo -e "${BLUE}-----------------------------------${NC}"
echo ""

printf "  %-20s %s\n" "${GREEN}SUPER + Space${NC}" "App Launcher (Spotlight)"
printf "  %-20s %s\n" "${GREEN}SUPER + T${NC}" "Terminal (Konsole)"
printf "  %-20s %s\n" "${GREEN}SUPER + B${NC}" "Browser (Chrome)"
printf "  %-20s %s\n" "${GREEN}SUPER + E${NC}" "File Manager (Dolphin)"
printf "  %-20s %s\n" "${GREEN}SUPER + V${NC}" "Clipboard History"
printf "  %-20s %s\n" "${GREEN}SUPER + H${NC}" "System Health Check"
printf "  %-20s %s\n" "${GREEN}SUPER + S${NC}" "Gaming (Steam)"
printf "  %-20s %s\n" "${GREEN}SUPER + M${NC}" "Music (Spotify)"
printf "  %-20s %s\n" "${GREEN}SUPER + Q${NC}" "Close Active Window"
printf "  %-20s %s\n" "${GREEN}SUPER + L${NC}" "Lock Screen"
printf "  %-20s %s\n" "${GREEN}SUPER + W${NC}" "Restart UI (Waybar)"
echo ""

echo -e "${BLUE}-----------------------------------${NC}"
echo -e "${PURPLE}Press any key to return...${NC}"
read -n 1 -s
