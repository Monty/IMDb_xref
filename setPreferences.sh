#!/usr/bin/env bash
#
# Set user preferences

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
setPreferences.sh -- Set user preferences.

Invoked automatically if preferences have never been set.

USAGE:
    ./setPreferences.sh [OPTIONS...]

OPTIONS:
    -h      Print this message.
EOF
}

# Handle EXIT
trap terminate EXIT
#
function terminate() {
    if [ -n "$DEBUG" ]; then
        printf "Terminating...\n" >&2
    fi
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

while getopts ":h" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    \?)
        printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2
        ;;
    :)
        printf "==> Option -$OPTARG requires an argument'.\n\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

cat <<EOF
Sometimes I will ask you Yes/No questions like:
==> Would you like to create a filmography? [y/n]
==> Would you like to add a show? [Y/n]     -- <cr> defaults to Yes
==> Would you like to start over? [y/N]     -- <cr> defaults to No

Try these two styles of answering such questions and then pick the one you prefer:

EOF

while true; do
    printf "1) Don't require a <cr>. Return as soon as you type a 'y' or 'n'.\n"
    if waitUntil "==> Do you go to movies?"; then
        printf "You answered: Yes\n"
    else
        printf "You answered: No\n"
    fi
    printf "\n"

    printf "2) Require a <cr> after you type a 'y' or 'n'.\n"
    if waitUntil -l "==> Do you watch TV?"; then
        printf "You answered: Yes\n"
    else
        printf "You answered: No\n"
    fi
    printf "\n"

    ynOptions=("Don't require a <cr>" "Require a <cr>" "Let me try those again" "Decide later")
    PS3="Select a number from 1-${#ynOptions[@]}: "
    # shellcheck disable=SC2034      # ynMenu is intentionally not used
    select ynMenu in "${ynOptions[@]}"; do
        if [ "$REPLY" -ge 1 ] 2>/dev/null && [ "$REPLY" -le "${#ynOptions[@]}" ]; then
            case "$REPLY" in
            1)
                YN_PREF=
                perl -pi -e 's+^YN_PREF=.*+YN_PREF="-s"+;' "$configFile"
                break
                ;;
            2)
                YN_PREF="-l "
                perl -pi -e 's+^YN_PREF=.*+YN_PREF="-l"+;' "$configFile"
                break
                ;;
            3)
                printf "\n"
                continue 2
                ;;
            4)
                printf "\n"
                break
                ;;
            esac
        else
            printf "Your selection must be a number from 1-${#ynOptions[@]}\n"
        fi
    done </dev/tty
    perl -pi -e 's+^NEED_PREFS=.*+NEED_PREFS=+;' "$configFile"
    break
done
