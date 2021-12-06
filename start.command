#!/usr/bin/env bash
#
# Run the available high level scripts

# On macOS, .command files can be executed by double clicking in a Finder window
# or right-clicking and selecting 'Open'. Either will open a Terminal window
# and run them as a shell script.

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

FULLCAST="${FULLCAST:-20}"
export FULLCAST

# Is FULLCAST an integer?
if [ "$FULLCAST" -eq "$FULLCAST" ] 2>/dev/null; then
    maxCast="$FULLCAST "
    [ "$FULLCAST" -eq 0 ] && maxCast=""
fi

source functions/define_colors
source functions/define_files
source functions/load_functions

function start_help() {
    cat <<EOF

1) Find shows, then list their top ${maxCast}cast & crew members

        Search IMDb titles for show names or tconst IDs such as tt1606375,
        which is the tconst for Downton Abbey -- taken from this URL:
        https://www.imdb.com/title/tt1606375/

        List principal cast & crew members and any characters portrayed. If you
        search for multiple shows, also list principal cast & crew members who
        are found in more than one show.

        An excerpt from searching for The Crown:

==> Top ${maxCast}cast & crew members in IMDb billing order (Name|Job|Show|Role):
Claire Foy                  actor     The Crown  Queen Elizabeth II
Olivia Colman               actor     The Crown  Queen Elizabeth II
Imelda Staunton             actor     The Crown  Queen Elizabeth II
Matt Smith                  actor     The Crown  Philip, Duke of Edinburgh
Tobias Menzies              actor     The Crown  Prince Philip, Duke of Edinburgh
Jonathan Pryce              actor     The Crown  Prince Philip, Duke of Edinburgh
Lesley Manville             actor     The Crown  Princess Margaret
Elizabeth Debicki           actor     The Crown  Princess Diana
Dominic West                actor     The Crown  Prince Charles
EOF
    waitUntil -k
    cat <<EOF

2) Find shows, then list only cast & crew members they share

        Search IMDb titles for show names or tconst IDs such as tt4786824,
        which is the tconst for The Crown.

        List principal cast & crew members and any characters portrayed, but
        only if they are found in more than one show.

        The result from searching for The Crown and The Night Manager:

==> Principal cast & crew members listed in more than one show (Name|Job|Show|Role):
Elizabeth Debicki  actor  The Crown          Princess Diana
Elizabeth Debicki  actor  The Night Manager  Jed Marshall
Olivia Colman      actor  The Crown          Queen Elizabeth II
Olivia Colman      actor  The Night Manager  Angela Burr
Tobias Menzies     actor  The Crown          Prince Philip, Duke of Edinburgh
Tobias Menzies     actor  The Night Manager  Geoffrey Dromgoole
EOF
    waitUntil -k
    cat <<EOF

3) Find a show, then list its top ${maxCast}actors that are in your cached shows

        Search IMDb titles for one show name or tconst ID such as tt4786824,
        which is the tconst for The Crown.

        List any of the top ${maxCast}actors who also appear any any show you've
        previously searched for, i.e. not just your saved shows.

==> Principal cast members that appear in other shows (Name|Job|Show|Rank|Role|Link):
Olivia Colman      actor  The Crown          02  Queen Elizabeth II                imdb.com/name/nm1469236
Olivia Colman      actor  Broadchurch        02  Ellie Miller                      imdb.com/title/tt2249364
Olivia Colman      actor  The Night Manager  04  Angela Burr                       imdb.com/title/tt1399664
 ---
Tobias Menzies     actor  The Crown          05  Prince Philip, Duke of Edinburgh  imdb.com/name/nm0580014
Tobias Menzies     actor  The Night Manager  14  Geoffrey Dromgoole                imdb.com/title/tt1399664
 ---
Elizabeth Debicki  actor  The Crown          08  Princess Diana                    imdb.com/name/nm4456120
Elizabeth Debicki  actor  The Night Manager  03  Jed Marshall                      imdb.com/title/tt1399664
 ---
Charles Edwards    actor  The Crown          10  Martin Charteris                  imdb.com/name/nm0249876
Charles Edwards    actor  Downton Abbey      46  Michael Gregson                   imdb.com/title/tt1606375
 ---
Josh O'Connor      actor  The Crown          19  Prince Charles                    imdb.com/name/nm4853066
Josh O'Connor      actor  The Durrells       02  Lawrence Durrell                  imdb.com/title/tt5014882
EOF
    waitUntil -k
    cat <<EOF

4) Find people, then list all shows having them as a principal cast or crew member

        Find all shows listing a person as a principal cast or crew member based
        on their name or nconst ID, such as nm0000233 -- which is the nconst for
        Quentin Tarantino -- taken from this URL: https://www.imdb.com/name/nm0000233/

        An excerpt from searching for Quentin Tarantino:

==> I found 38 titles listing Quentin Tarantino as: actor
==> Shall I list them? [Y/n]
movie      Once Upon a Time... In Hollywood            2019
movie      The Hateful Eight                           2015
movie      She's Funny That Way                        2014
movie      Django Unchained                            2012

==> I found 21 titles listing Quentin Tarantino as: director
==> Shall I list them? [Y/n]
movie     Once Upon a Time... In Hollywood    2019
movie     The Hateful Eight                   2015
movie     Django Unchained                    2012
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

        Run detailed queries of any shows you searched as favorites in 1) or 2).

        Search cached shows for any mix of shows, cast or crew members, and
        characters portrayed, e.g. The Crown, Olivia Colman, or Queen Elizabeth.

        1), 2), and 3) search all records for shows. 4) and 5) search all
        records for cast or crew names. This script only searches cached shows,
        but adds searching for characters and mixing all three types.
EOF
    waitUntil -k
    cat <<EOF

7) Run a guided cross-reference of your cached shows

        Runs the same types of queries as 6), but is menu and prompt driven.

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
pickOptions=("Find shows, then list their top ${maxCast}cast & crew members")
# 2
pickOptions+=("Find shows, then list only cast & crew members they share")
# 3
pickOptions+=("Find a show, then list its top ${maxCast}actors that are in your cached shows")
# 4
pickOptions+=("Find people, then list all shows having them as a principal cast or crew member")
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
            exec ./findOtherShows.sh -n $FULLCAST
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
