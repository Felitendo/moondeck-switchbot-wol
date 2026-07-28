#!/usr/bin/env bash
#
# Dialog helpers. Prefers kdialog (SteamOS desktop mode is KDE), falls back to
# zenity and finally to plain terminal prompts. Set MSB_FORCE_CLI=1 to always
# use the terminal.
#
# Every ui_* function writes its result to stdout and returns non-zero when the
# user cancels, so callers can chain with ||.

msb_ui_backend() {
    if [[ -n ${MSB_FORCE_CLI:-} ]]; then
        printf 'cli'
    elif [[ -z ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
        printf 'cli'
    elif command -v kdialog >/dev/null 2>&1; then
        printf 'kdialog'
    elif command -v zenity >/dev/null 2>&1; then
        printf 'zenity'
    else
        printf 'cli'
    fi
}

MSB_UI=$(msb_ui_backend)

ui_info() {
    local title=$1 text=$2
    case $MSB_UI in
        kdialog) kdialog --title "$title" --msgbox "$text" ;;
        zenity) zenity --info --title="$title" --text="$text" --width=520 ;;
        *) printf '\n%s\n%s\n\n' "$title" "$text" ;;
    esac
}

ui_error() {
    local title=$1 text=$2
    case $MSB_UI in
        kdialog) kdialog --title "$title" --error "$text" ;;
        zenity) zenity --error --title="$title" --text="$text" --width=520 ;;
        *) printf '\n%s\n%s\n\n' "$title" "$text" >&2 ;;
    esac
}

ui_yesno() {
    local title=$1 text=$2 answer
    case $MSB_UI in
        kdialog) kdialog --title "$title" --yesno "$text" ;;
        zenity) zenity --question --title="$title" --text="$text" --width=520 ;;
        *)
            local hint='[y/N]'
            [[ $MSB_LANG == de ]] && hint='[j/N]'
            printf '\n%s\n%s %s ' "$title" "$text" "$hint" >&2
            read -r answer || return 1
            [[ $answer =~ ^[yYjJ] ]]
            ;;
    esac
}

ui_input() {
    local title=$1 label=$2 default=${3:-} value
    case $MSB_UI in
        kdialog) kdialog --title "$title" --inputbox "$label" "$default" ;;
        zenity) zenity --entry --title="$title" --text="$label" --entry-text="$default" --width=520 ;;
        *)
            printf '\n%s\n' "$label" >&2
            [[ -n $default ]] && printf '[%s] ' "$default" >&2
            read -r value || return 1
            printf '%s' "${value:-$default}"
            ;;
    esac
}

ui_password() {
    local title=$1 label=$2 value
    case $MSB_UI in
        kdialog) kdialog --title "$title" --password "$label" ;;
        zenity) zenity --entry --title="$title" --text="$label" --hide-text --width=520 ;;
        *)
            printf '\n%s\n' "$label" >&2
            read -rs value || return 1
            printf '\n' >&2
            printf '%s' "$value"
            ;;
    esac
}

msb_qdbus() {
    local candidate
    for candidate in qdbus qdbus6 qdbus-qt6 qdbus-qt5; do
        if command -v "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

# ui_progress_run <text> <output file> <command> [arguments...]
#
# Runs the command behind a busy indicator, writes its stdout to the given file
# and returns its exit code. Without this the window is simply gone for a few
# seconds while the API is queried, which looks like a crash.
ui_progress_run() {
    local text=$1 output=$2
    shift 2
    local status_file worker qdbus_binary reference exit_code
    status_file=$(mktemp)

    case $MSB_UI in
        zenity)
            {
                "$@" >"$output"
                printf '%s' "$?" >"$status_file"
            } &
            worker=$!
            # zenity closes as soon as its stdin reaches end of file, which
            # happens when the process substitution notices the worker is gone.
            zenity --progress --pulsate --auto-close --no-cancel \
                --title="$(t app_title)" --text="$text" --width=420 \
                < <(while kill -0 "$worker" 2>/dev/null; do sleep 0.2; done) \
                >/dev/null 2>&1
            wait "$worker" || true
            ;;
        kdialog)
            reference=""
            if qdbus_binary=$(msb_qdbus); then
                reference=$(kdialog --title "$(t app_title)" --progressbar "$text" 0 2>/dev/null) || reference=""
            fi
            "$@" >"$output"
            printf '%s' "$?" >"$status_file"
            if [[ -n $reference ]]; then
                # shellcheck disable=SC2086
                $qdbus_binary $reference close >/dev/null 2>&1 || true
            fi
            ;;
        *)
            printf '%s\n' "$text"
            "$@" >"$output"
            printf '%s' "$?" >"$status_file"
            ;;
    esac

    exit_code=$(cat "$status_file" 2>/dev/null)
    rm -f "$status_file"
    return "${exit_code:-1}"
}

# ui_choose <title> <label> <tag> <text> [<tag> <text> ...]
ui_choose() {
    local title=$1 label=$2
    shift 2
    local args=() index=1 choice
    case $MSB_UI in
        kdialog)
            local state=on
            while (($#)); do
                args+=("$1" "$2" "$state")
                state=off
                shift 2
            done
            kdialog --title "$title" --radiolist "$label" "${args[@]}"
            ;;
        zenity)
            local state=TRUE
            while (($#)); do
                args+=("$state" "$1" "$2")
                state=FALSE
                shift 2
            done
            zenity --list --radiolist --title="$title" --text="$label" \
                --column="" --column="ID" --column="Name" --print-column=2 \
                --width=620 --height=420 "${args[@]}"
            ;;
        *)
            local tags=()
            printf '\n%s\n%s\n\n' "$title" "$label" >&2
            while (($#)); do
                tags+=("$1")
                printf '  %2d) %s\n' "$index" "$2" >&2
                index=$((index + 1))
                shift 2
            done
            printf '\n[1] ' >&2
            read -r choice || return 1
            choice=${choice:-1}
            [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#tags[@]})) || return 1
            printf '%s' "${tags[choice - 1]}"
            ;;
    esac
}
