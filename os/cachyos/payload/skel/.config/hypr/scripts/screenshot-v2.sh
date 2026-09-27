#!/usr/bin/env bash
# Improved Screenshot Script for Hyprland

# Dependencies: grim, slurp, swappy, wl-copy, notify-send
# Sourced Notification Handler
source "$HOME/.config/ml4w/scripts/ml4w-notification-handler"

APP_NAME="Screen Capture"
NOTIFICATION_ICON="camera-photo-symbolic"

# Save Directory
SAVE_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SAVE_DIR"

# Filename with timestamp
NAME="screenshot_$(date +%Y%m%d_%H%M%S).png"
TEMP_FILE="/tmp/$NAME"

# Function to capture
capture() {
    local mode=$1
    if [[ "$mode" == "area" ]]; then
        # Capture selection
        grim -g "$(slurp -b '#00000080' -c '#888888ff' -w 1)" "$TEMP_FILE" || exit 1
    else
        # Capture full screen
        grim "$TEMP_FILE" || exit 1
    fi

    # Check if file was created (user might have cancelled slurp)
    if [[ -f "$TEMP_FILE" ]]; then
        # Copy to clipboard
        wl-copy < "$TEMP_FILE"
        
        # Open with swappy for editing (it will save to SAVE_DIR if configured or user chooses)
        # We tell swappy to save to our desired location by default
        swappy -f "$TEMP_FILE" -o "$SAVE_DIR/$NAME"
        
        # Notify user (if swappy saved it, or if it's just in clipboard)
        if [[ -f "$SAVE_DIR/$NAME" ]]; then
            notify_user \
                --a "${APP_NAME}" \
                --i "${NOTIFICATION_ICON}" \
                --s "Screenshot Saved & Copied" \
                --m "$SAVE_DIR/$NAME" \
                --t 2000
        else
            notify_user \
                --a "${APP_NAME}" \
                --i "${NOTIFICATION_ICON}" \
                --s "Screenshot Copied to Clipboard" \
                --m "Selection copied. Editor closed without saving." \
                --t 2000
        fi
        
        # Clean up temp file
        rm "$TEMP_FILE"
    fi
}

# Run capture
case "$1" in
    --area)
        capture "area"
        ;;
    --full)
        capture "full"
        ;;
    *)
        capture "area"
        ;;
esac
