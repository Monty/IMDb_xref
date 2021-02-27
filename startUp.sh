#!/usr/bin/env bash
#
# Run the available high level scripts

# On macOS, .command files can be executed by double clicking in a Finder window
# or right-clicking and selecting 'Open'. Either will open a Terminal window
# and run them as a shell script.

# Make sure window size is useful
printf '\e[9;2t'
[ "$(tput cols)" -lt 100 ] && printf '\e[8;;100t'

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

printf "==> What would you like to do next?\n"

# 1
pickOptions=("Find the principal cast & crew members of one or more shows")
# 2
pickOptions+=("Find any principal cast & crew members listed in more than one show")
# 3
pickOptions+=("Find all shows listing a person as a cast or crew member")
# 4
pickOptions+=("Save a filmography for a person")
# 5
pickOptions+=("Run a cross reference of your saved shows")
# 6
pickOptions+=("Run a guided cross reference of your saved shows")
# 7
pickOptions+=("Show me a list of my saved shows")
# 8
pickOptions+=("Help")
# 9
pickOptions+=("Quit")

PS3="Select a number from 1-${#pickOptions[@]}: "
COLUMNS=40
select pickMenu in "${pickOptions[@]}"; do
    if [ "$REPLY" -ge 1 ] 2>/dev/null &&
        [ "$REPLY" -le "${#pickOptions[@]}" ]; then
        case "$REPLY" in
        1)
            exec ./findCastOf.sh
            ;;
        2)
            exec ./findCastOf.sh -d
            ;;
        3)
            exec ./findShowsWith.sh
            ;;
        4)
            exec ./saveFilmography.sh
            ;;
        5)
            exec ./xrefCast.sh
            ;;
        6)
            exec ./iQuery.sh
            ;;
        7)
            printf "\n"
            cat uniqTitles.txt
            printf "\n"
            exec ./startUp.sh
            ;;
        8)
            exec ./explain_scripts.sh
            ;;
        9)
            printf "Quitting...\n"
            exit
            ;;
        *)
            printf "You picked $pickMenu ($REPLY)\n"
            break
            ;;
        esac
        break
    else
        printf "Your selection must be a number from 1-${#pickOptions[@]}\n"
    fi
done </dev/tty
