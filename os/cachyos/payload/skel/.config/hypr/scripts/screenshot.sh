#!/usr/bin/env bash
#                                 __        __ 
#   ___ ___________ ___ ___  ___ / /  ___  / /_
#  (_-</ __/ __/ -_) -_) _ \(_-</ _ \/ _ \/ __/
# /___/\__/_/  \__/\__/_//_/___/_//_/\___/\__/ 
#                                              
# Improved ML4W Screenshot Script (Fixed to work without grimblast)

# -----------------------------------------------------

SAVE_DIR=$(cat ~/.config/ml4w/settings/screenshot-folder)
SAVE_FILENAME=$(cat ~/.config/ml4w/settings/screenshot-filename)
eval screenshot_folder="$SAVE_DIR"
eval NAME="$SAVE_FILENAME"
mkdir -p "$screenshot_folder"

# Notifications
source "$HOME/.config/ml4w/scripts/ml4w-notification-handler"
APP_NAME="Screen Capture"
NOTIFICATION_ICON="camera-photo-symbolic"

# Quick instant mode: full screen
take_instant_full() {
    grim "$screenshot_folder/$NAME" && notify_user \
        --a "${APP_NAME}" \
        --i "${NOTIFICATION_ICON}" \
        --s "Screenshot saved" \
        --m "$screenshot_folder/$NAME" \
        --t 2000
    wl-copy < "$screenshot_folder/$NAME"
}

# Quick instant mode: area selection
take_instant_area() {
    grim -g "$(slurp -b '#00000080' -c '#888888ff' -w 1)" "$screenshot_folder/$NAME" && notify_user \
        --a "${APP_NAME}" \
        --i "${NOTIFICATION_ICON}" \
        --s "Screenshot saved" \
        --m "$screenshot_folder/$NAME" \
        --t 2000
    wl-copy < "$screenshot_folder/$NAME"
}

# Handle instant flags
if [[ "$1" == "--instant" ]]; then
    take_instant_full
    exit 0
elif [[ "$1" == "--instant-area" ]]; then
    take_instant_area
    exit 0
fi

# Options
option_1="Immediate"
option_2="Delayed"

option_capture_1="Capture Everything"
option_capture_2="Capture Selection"

option_time_1="5s"
option_time_2="10s"
option_time_3="20s"

list_col='1'
list_row='2'

copy='Copy'
save='Save'
copy_save='Copy & Save'
edit='Edit'

# Rofi CMD
rofi_cmd() {
    "$HOME/.config/prime/rofi-hint.sh" -dmenu -replace -config ~/.config/rofi/config-screenshot.rasi -i -no-show-icons -l 2 -width 30 -p "Take screenshot"
}

# Pass variables to rofi dmenu
run_rofi() {
    echo -e "$option_1\n$option_2" | rofi_cmd
}

####
# Choose Timer
timer_cmd() {
    "$HOME/.config/prime/rofi-hint.sh" -dmenu -replace -config ~/.config/rofi/config-screenshot.rasi -i -no-show-icons -l 3 -width 30 -p "Choose timer"
}

timer_exit() {
    echo -e "$option_time_1\n$option_time_2\n$option_time_3" | timer_cmd
}

timer_run() {
    selected_timer="$(timer_exit)"
    if [[ "$selected_timer" == "$option_time_1" ]]; then
        countdown=5
        ${1}
    elif [[ "$selected_timer" == "$option_time_2" ]]; then
        countdown=10
        ${1}
    elif [[ "$selected_timer" == "$option_time_3" ]]; then
        countdown=20
        ${1}
    else
        exit
    fi
}

####
# Choose Screenshot Type
type_screenshot_cmd() {
    "$HOME/.config/prime/rofi-hint.sh" -dmenu -replace -config ~/.config/rofi/config-screenshot.rasi -i -no-show-icons -l 2 -width 30 -p "Type of screenshot"
}

type_screenshot_exit() {
    echo -e "$option_capture_1\n$option_capture_2" | type_screenshot_cmd
}

type_screenshot_run() {
    selected_type_screenshot="$(type_screenshot_exit)"
    if [[ "$selected_type_screenshot" == "$option_capture_1" ]]; then
        option_type_screenshot=screen
        ${1}
    elif [[ "$selected_type_screenshot" == "$option_capture_2" ]]; then
        option_type_screenshot=area
        ${1}
    else
        exit
    fi
}

####
# Choose Action
copy_save_editor_cmd() {
    "$HOME/.config/prime/rofi-hint.sh" -dmenu -replace -config ~/.config/rofi/config-screenshot.rasi -i -no-show-icons -l 4 -width 30 -p "Action"
}

copy_save_editor_exit() {
    echo -e "$copy\n$save\n$copy_save\n$edit" | copy_save_editor_cmd
}

copy_save_editor_run() {
    selected_chosen="$(copy_save_editor_exit)"
    if [[ "$selected_chosen" == "$copy" ]]; then
        option_chosen=copy
        ${1}
    elif [[ "$selected_chosen" == "$save" ]]; then
        option_chosen=save
        ${1}
    elif [[ "$selected_chosen" == "$copy_save" ]]; then
        option_chosen=copysave
        ${1}
    elif [[ "$selected_chosen" == "$edit" ]]; then
        option_chosen=edit
        ${1}
    else
        exit
    fi
}

timer() {
    while [[ $countdown -ne 0 ]]; do
        notify_user \
            --a "${APP_NAME}" \
            --i "${NOTIFICATION_ICON}" \
            --s "Taking screenshot in ${countdown} seconds" \
            --m "" \
            --t 1000
        countdown=$((countdown - 1))
        sleep 1
    done
}

takescreenshot() {
    sleep 0.5
    TEMP_FILE="/tmp/screenshot_tmp.png"
    
    if [[ "$option_type_screenshot" == "area" ]]; then
        grim -g "$(slurp -b '#00000080' -c '#888888ff' -w 1)" "$TEMP_FILE" || exit 1
    else
        grim "$TEMP_FILE" || exit 1
    fi

    case "$option_chosen" in
        copy)
            wl-copy < "$TEMP_FILE"
            notify_user --a "${APP_NAME}" --i "${NOTIFICATION_ICON}" --s "Copied to Clipboard"
            rm "$TEMP_FILE"
            ;;
        save)
            mv "$TEMP_FILE" "$screenshot_folder/$NAME"
            notify_user --a "${APP_NAME}" --i "${NOTIFICATION_ICON}" --s "Saved to Pictures" --m "$screenshot_folder/$NAME"
            ;;
        copysave)
            cp "$TEMP_FILE" "$screenshot_folder/$NAME"
            wl-copy < "$TEMP_FILE"
            notify_user --a "${APP_NAME}" --i "${NOTIFICATION_ICON}" --s "Saved & Copied" --m "$screenshot_folder/$NAME"
            rm "$TEMP_FILE"
            ;;
        edit)
            swappy -f "$TEMP_FILE" -o "$screenshot_folder/$NAME"
            rm "$TEMP_FILE"
            ;;
    esac
}

takescreenshot_timer() {
    timer
    takescreenshot
}

# Execute Command
run_cmd() {
    if [[ "$1" == '--opt1' ]]; then
        type_screenshot_run
        copy_save_editor_run "takescreenshot"
    elif [[ "$1" == '--opt2' ]]; then
        timer_run
        type_screenshot_run
        copy_save_editor_run "takescreenshot_timer"
    fi
}

# Actions
chosen="$(run_rofi)"
case ${chosen} in
    $option_1)
        run_cmd --opt1
        ;;
    $option_2)
        run_cmd --opt2
        ;;
esac
