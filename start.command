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

export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

function start_help() {
    cat <<EOF

1) Find the principal cast and crew members of one or more shows

        Search IMDb titles for show names or tconst IDs such as tt1606375 --
        which is the tconst for Downton Abbey.

        List principal cast & crew members and any characters portrayed. If you
        search for multiple shows, also list cast & crew members who are listed
        in more than one.

        An excerpt from searching for The Crown:

        ==> Principal cast & crew members (Name|Job|Show|Role):
        Ben Daniels        actor     The Crown  Lord Snowdon
        Josh O'Connor      actor     The Crown  Prince Charles
        Elizabeth Debicki  actress   The Crown  Princess Diana
        Gillian Anderson   actress   The Crown  Margaret Thatcher
        Olivia Colman      actress   The Crown  Queen Elizabeth II
        Jessica Hobbs      director  The Crown
        Jonathan Wilson    writer    The Crown
EOF
    waitUntil -k
    cat <<EOF

2) Find any principal cast & crew members listed in more than one show

        Search IMDb titles for show names or tconst IDs such as tt4786824 --
        which is the tconst for The Crown.

        List principal cast & crew members and any characters portrayed, but
        only if they are listed in more than one show.

        The result from searching for The Crown and The Night Manager:

        ==> Principal cast & crew members listed in more than one show (Name|Job|Show|Role):
        Tobias Menzies     actor    The Crown          Prince Philip, Duke of Edinburgh
        Tobias Menzies     actor    The Night Manager  Geoffrey Dromgoole
        Elizabeth Debicki  actress  The Crown          Princess Diana
        Elizabeth Debicki  actress  The Night Manager  Jed Marshall
        Olivia Colman      actress  The Crown          Queen Elizabeth II
        Olivia Colman      actress  The Night Manager  Angela Burr
EOF
    waitUntil -k
    cat <<EOF

3) Find all shows listing a person as a cast or crew member

        Find all shows listing a person as a cast or crew member based on their
        name or nconst ID, such as nm0000233 -- which is the nconst for Quentin
        Tarantino

        An excerpt from searching for Quentin Tarantino:

        ==> I found 9 titles listing Quentin Tarantino as: writer
        movie  Natural Born Killers  1994

        ==> I found 15 titles listing Quentin Tarantino as: director
        movie  The Hateful Eight     2015
        movie  Django Unchained      2012
EOF
    waitUntil -k
    cat <<EOF

4) Save a filmography for a cast or crew member

        Generate a filmography based on a person's name or nconst ID.  such as
        nm0000123 -- which is the nconst for George Clooney.

        Basically the same as 3), but more useful for detailed research as it
        will offer to save any sections and create related lists and
        spreadsheets.
EOF
    waitUntil -k
    cat <<EOF

5) Run a cross reference of your saved shows

        Run detailed queries of any shows you saved as favorites in 1) or 2).

        Search saved shows for any mix of shows, cast or crew members, and
        characters portrayed, e.g. The Crown, Olivia Colman, or Queen Elizabeth.

        1) and 2) search all records for shows. 3) searches all records for cast
        or crew names. This script only searches saved shows, but adds searching
        for characters, and mixing all three types.
EOF
    waitUntil -k
    cat <<EOF

6) Run a guided cross reference of your saved shows

        Runs the same types of queries as 5), but is menu and prompt driven.

        Instead of entering a full show name like The Night Manager, you only
        need to enter enough characters to ensure a unique match.

        For example, 'Hi' returns 'Tom Hiddleston' in the example data set.

EOF
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

# Make sure prerequisites are satisfied
ensurePrerequisites

printf "==> What would you like to do next?\n"

# 1
pickOptions=("Find the principal cast & crew members of one or more shows")
# 2
pickOptions+=("Find any principal cast & crew members listed in more than one show")
# 3
pickOptions+=("Find all shows listing a person as a cast or crew member")
# 4
pickOptions+=("Save a filmography for a cast or crew member")
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
            exec ./start.command
            ;;
        8)
            start_help
            exec ./start.command
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
