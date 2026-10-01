# Where add-ons live (sourced, not run). Two places, same format:
#
#   $LAYER/addons/<name>/            shipped with Prime; prime-update replaces them
#   ~/.config/prime/addons.d/<name>/ personal: yours (or made by prime-import);
#                                    never shipped, never touched by prime-update
#
# A shipped add-on wins over a personal one with the same name (prime-addon list
# says so), so an update can always repair Prime's own. Names are lower-case
# letters, digits, "-" and "_" — nothing that could climb out of the folder.
#
# Needs LAYER set. Gives: PERSONAL_ADDONS, addon_name_ok, addon_dir,
# addon_is_personal, enabled_addons, enabled_addon_dirs.

PERSONAL_ADDONS="${PRIME_PERSONAL_ADDONS:-$HOME/.config/prime/addons.d}"

addon_name_ok() { [[ "${1:-}" =~ ^[a-z0-9][a-z0-9_-]{0,40}$ ]]; }

# addon_dir <name> — prints the add-on's folder, or fails
addon_dir() {
    addon_name_ok "${1:-}" || return 1
    if [ -f "$LAYER/addons/$1/addon.conf" ]; then echo "$LAYER/addons/$1"
    elif [ -f "$PERSONAL_ADDONS/$1/addon.conf" ]; then echo "$PERSONAL_ADDONS/$1"
    else return 1; fi
}

addon_is_personal() { [ "$(addon_dir "$1" 2>/dev/null)" = "$PERSONAL_ADDONS/$1" ]; }

# the names in ~/.config/prime/addons, in order
enabled_addons() { grep -v '^#' "$HOME/.config/prime/addons" 2>/dev/null | grep -E '^[a-z0-9][a-z0-9_-]*$'; return 0; }

# the folders of the enabled add-ons that exist, in order
enabled_addon_dirs() {
    local n
    while read -r n; do addon_dir "$n" || true; done < <(enabled_addons)
}
