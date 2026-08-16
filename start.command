#!/usr/bin/env bash
#
# Run the available high level scripts

# On macOS, .command files can be executed by double clicking in a Finder window
# or right-clicking and selecting 'Open'. Either will open a Terminal window
# and run them as a shell script.

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

# castLimit caps how many cast & crew members the menu items below list. It is
# deliberately NOT exported. It used to be, as FULLCAST, which meant a variable
# set here for menu labels also flipped xrefCast.sh and iQuery.sh onto the
# cross-reference cache -- so picking item 6 or 7 gave a brand-new user the
# thinnest available view without their ever having heard of FULLCAST. Those two
# scripts now take an explicit -c, and the cap travels as -n to the scripts that
# want it. FULLCAST is still read as the default so existing muscle memory keeps
# working, but it goes no further than this file.
castLimit="${FULLCAST:-20}"
if [[ ! $castLimit =~ ^[0-9]+$ ]]; then
    printf "==> [Warning] Ignoring non-numeric FULLCAST: $castLimit\n\n" >&2
    castLimit=20
fi

# 0 means all. Whole phrases rather than an interpolated number, so the labels
# read as English either way. Note "all" is dropped entirely at 0 rather than
# written out: this branch's cast comes from title.principals.tsv.gz, ~10 names
# per title, so there is no fuller list an "all" could be promising. The
# hundreds-long fullcredits page is a live-fetch capability only.
if [[ $castLimit -eq 0 ]]; then
    castDescription="their principal cast & crew members"
    actorDescription="its principal actors"
    castHeading="Principal cast & crew members"
else
    castDescription="their top $castLimit principal cast & crew members"
    actorDescription="its top $castLimit actors"
    castHeading="Top $castLimit principal cast & crew members"
fi

source functions/define_colors
source functions/define_files
source functions/load_functions

function start_help() {
    cat <<EOF

1) Find shows, then list $castDescription

        Search IMDb titles for show names or tconst IDs such as tt1606375,
        which is the tconst for Downton Abbey -- taken from this URL:
        https://www.imdb.com/title/tt1606375/

        List principal cast & crew members and any characters portrayed. If you
        search for multiple shows, also list principal cast & crew members who
        are found in more than one show.

        An excerpt from searching for The Crown:

==> $castHeading in IMDb billing order (Name|Job|Show|Role):
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

3) Find a show, then list $actorDescription that are in your cached shows

        Search IMDb titles for one show name or tconst ID such as tt4786824,
        which is the tconst for The Crown.

        List any of those actors who also appear in any show you've
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
pickOptions=("Find shows, then list $castDescription")
# 2
pickOptions+=("Find shows, then list only cast & crew members they share")
# 3
pickOptions+=("Find a show, then list $actorDescription that are in your cached shows")
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
    if [[ $REPLY -ge 1 ]] 2>/dev/null &&
        [[ $REPLY -le ${#pickOptions[@]} ]]; then
        case "$REPLY" in
        1)
            exec ./findCastOf.sh -n "$castLimit"
            ;;
        2)
            exec ./findCastOf.sh -dn "$castLimit"
            ;;
        3)
            exec ./findOtherShows.sh -n "$castLimit"
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
            # uniqTitles.txt is generated by generateXrefData.sh, and
            # cleanupEverything.sh can remove it. Unlike the other menu items,
            # nothing here would offer to rebuild it -- a bare cat just printed
            # "No such file or directory" and dropped back to the menu.
            if [[ -e uniqTitles.txt ]]; then
                cat uniqTitles.txt
            else
                printf "==> I didn't find uniqTitles.txt, which lists your saved shows.\n"
                printf "    Run ./generateXrefData.sh to create it.\n"
            fi
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
