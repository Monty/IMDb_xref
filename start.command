#!/usr/bin/env bash
#
# Run the available high level scripts
# Uses Playwright-based scraper for IMDb data.

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function start_help() {
    cat <<EOF

1) Find shows, then list their cast & crew members

        Search IMDb for show names or tconst IDs such as tt1606375,
        which is the tconst for Downton Abbey:
        https://www.imdb.com/title/tt1606375/

        List cast & crew members, characters portrayed, and episode counts.
        If you search for multiple shows, also list cast members who
        are found in more than one show.

        Use -e NNN to filter by minimum episodes (e.g., -e 10 for series regulars).

        An excerpt from searching for Money Heist:

==> Cast & crew for "Money Heist" (Name|Job|Role|Episodes):
Úrsula Corberó             actor  Tokio                          41 episodes
Álvaro Morte               actor  El Profesor                    41 episodes
Itziar Ituño               actor  Raquel Murillo                 41 episodes
Pedro Alonso               actor  Berlín                         41 episodes
Miguel Herrán              actor  Río                            41 episodes
EOF
    waitUntil -k
    cat <<EOF

2) Find shows, then list only cast & crew members they share

        Search IMDb for show names or tconst IDs.

        List cast & crew members but only if found in more than one show.

==> Cast & crew listed in more than one show (Name|Job|Show|Role):
Pedro Alonso       actor  Berlin and the Lady with an Ermine   Berlín
Pedro Alonso       actor  Money Heist                          Berlín
Álvaro Morte       actor  Berlin and the Lady with an Ermine   El Profesor
Álvaro Morte       actor  Money Heist                          El Profesor
EOF
    waitUntil -k
    cat <<EOF

3) Find a show, then list actors that are in your cached shows

        Search IMDb for one show name or tconst ID.

        List actors who also appear in any show you've previously
        searched for, ranked by episode count.

==> Cast members that appear in other cached shows (Name|Job|Show|Episodes|Role|Link):
Pedro Alonso       actor  Berlin and the Lady with an Ermine   8       Berlín         imdb.com/title/tt42178219
Pedro Alonso       actor  Money Heist                          41      Berlín         imdb.com/title/tt6468322
 ---
Álvaro Morte       actor  Berlin and the Lady with an Ermine   1       El Profesor    imdb.com/title/tt42178219
Álvaro Morte       actor  Money Heist                          41      El Profesor    imdb.com/title/tt6468322
 ---
EOF
    waitUntil -k
    cat <<EOF

4) Find people, then list which of your cached shows they appear in

        Search by a person's name or nconst ID, such as nm0022261 for
        Pedro Alonso: https://www.imdb.com/name/nm0022261/

        Lists only shows already in your index, grouped by job. To add a
        show first, use option 1. For a person's full IMDb filmography,
        use option 5.

==> I found 3 titles listing Pedro Alonso as: actor
==> Shall I list them? [Y/n]
Money Heist                         41 episodes  Berlín  tt6468322
Berlin and the Jewels of Paris      8 episodes   Berlín  tt16288804
Berlin and the Lady with an Ermine  8 episodes   Berlín  tt42178219
EOF
    waitUntil -k
    cat <<EOF

5) Find people, then save a filmography for them

        Generate a filmography based on a person's name or nconst ID, such as
        nm0000123 -- which is the nconst for George Clooney.

        Basically the same as 4), but more useful for detailed research as it
        will offer to save any sections and create related lists and
        spreadsheets.
EOF
    waitUntil -k
    cat <<EOF

6) Run a cross-reference of your cached shows

        Search cached shows for any mix of shows, cast or crew members, and
        characters portrayed, e.g. The Crown, Olivia Colman, or Queen Elizabeth.

        Use -e NNN to filter by minimum episodes.
EOF
    waitUntil -k
    cat <<EOF

7) Run a guided cross-reference of your cached shows

        Runs the same types of queries as 6), but is menu and prompt driven.

        Instead of entering a full show name like The Night Manager, you only
        need to enter enough characters to ensure a unique match.
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
pickOptions=("Find shows, then list their cast & crew members")
# 2
pickOptions+=("Find shows, then list only cast & crew members they share")
# 3
pickOptions+=("Find a show, then list its actors that are in your cached shows")
# 4
pickOptions+=("Find people, then list which of your cached shows they appear in")
# 5
pickOptions+=("Find people, then save a filmography for them")
# 6
pickOptions+=("Run a cross-reference of your cached shows")
# 7
pickOptions+=("Run a guided cross-reference of your cached shows")
# 8
pickOptions+=("Show me a list of my saved shows")
# 9
pickOptions+=("Help")
# 10
pickOptions+=("Quit")

PS3="Select a number from 1-${#pickOptions[@]}, or type 'q(uit)': "
COLUMNS=40
select pickMenu in "${pickOptions[@]}"; do
    if [[ $REPLY -ge 1 ]] 2>/dev/null &&
        [[ $REPLY -le ${#pickOptions[@]} ]]; then
        case "$REPLY" in
        1)
            exec ./findCastOf.sh
            ;;
        2)
            exec ./findCastOf.sh -d
            ;;
        3)
            exec ./findOtherShows.sh
            ;;
        4)
            exec ./findShowsWith.sh
            ;;
        5)
            exec ./saveFilmography.sh
            ;;
        6)
            exec ./xrefCast.sh
            ;;
        7)
            exec ./iQuery.sh
            ;;
        8)
            printf "\n"
            cat uniqTitles.txt
            printf "\n"
            exec ./start.command
            ;;
        9)
            start_help
            exec ./start.command
            ;;
        10)
            printf "Quitting...\n"
            exit
            ;;
        *)
            printf "You picked $pickMenu ($REPLY)\n"
            break
            ;;
        esac
    else
        case "$REPLY" in
        [Qq]*)
            printf "Quitting...\n"
            exit
            ;;
        esac
    fi
done </dev/tty
