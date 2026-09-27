#!/usr/bin/env bash
#                                      __   
#   ___ ____ ___ _  ___ __ _  ___  ___/ /__ 
#  / _ `/ _ `/  ' \/ -_)  ' \/ _ \/ _  / -_)
#  \_, /\_,_/_/_/_/\__/_/_/_/\___/\_,_/\__/ 
# /___/                                     
# 

ml4w_cache_folder="$HOME/.cache/ml4w/hyprland-dotfiles"
gamemode_monitor="$HOME/.config/hypr/conf/monitors/gamemode.conf"

# Notifications
source "$HOME/.config/ml4w/scripts/ml4w-notification-handler"
APP_NAME="System"
NOTIFICATION_ICON="joystick"

if [ -f $HOME/.config/ml4w/settings/gamemode-enabled ]; then
  # EXITING GAMEMODE
  if [ -f $ml4w_cache_folder/last_monitor.conf ]; then
    cat $ml4w_cache_folder/last_monitor.conf > $HOME/.config/hypr/conf/monitor.conf
    rm $ml4w_cache_folder/last_monitor.conf
  fi
  if [ -f $ml4w_cache_folder/restart-wpauto ]; then
    rm $ml4w_cache_folder/restart-wpauto
    $HOME/.config/ml4w/scripts/ml4w-wallpaper-automation &
  fi
  
  # RESTORE PERFORMANCE TWEAKS
  pkill scx_lavd
  scxctl start --sched lavd
  powerprofilesctl set balanced
  pkill -CONT ollama
  pkill -CONT ags
  
  hyprctl reload
  rm $HOME/.config/ml4w/settings/gamemode-enabled
  notify_user --a "${APP_NAME}" \
            --i "${NOTIFICATION_ICON}" \
            --s "Gamemode deactivated" \
            --m "UI Restored, Scheduler: LAVD Auto"
else
  # ENTERING GAMEMODE
  if [ -f $gamemode_monitor ]; then
    cat $HOME/.config/hypr/conf/monitor.conf > $ml4w_cache_folder/last_monitor.conf
    echo "source = $gamemode_monitor" > $HOME/.config/hypr/conf/monitor.conf
  fi
  if [ -f $ml4w_cache_folder/wallpaper-automation ]; then
    touch $ml4w_cache_folder/restart-wpauto
    $HOME/.config/ml4w/scripts/ml4w-wallpaper-automation
  fi
  
  # APPLY PERFORMANCE TWEAKS
  powerprofilesctl set performance
  pkill scx_lavd
  scx_lavd --performance &
  pkill -STOP ollama
  pkill -STOP ags
  
  hyprctl --batch "\
    keyword animations:enabled 0;\
    keyword decoration:shadow:enabled 0;\
    keyword decoration:blur:enabled 0;\
    keyword general:gaps_in 0;\
    keyword general:gaps_out 0;\
    keyword general:border_size 1;\
    keyword decoration:active_opacity 1;\
    keyword decoration:inactive_opacity 1;\
    keyword decoration:fullscreen_opacity 1;\
    keyword decoration:rounding 0;\
    keyword render:direct_scanout false"
    
  touch $HOME/.config/ml4w/settings/gamemode-enabled
  notify_user --a "${APP_NAME}" \
          --i "${NOTIFICATION_ICON}" \
          --s "Gamemode activated" \
          --m "Latency Optimized, Scheduler: LAVD Performance"
fi
