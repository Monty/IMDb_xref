#!/usr/bin/env bash

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME"/.. || exit

export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions
ensurePrerequisites

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    exit 130
}

printf "==> Testing ${RED}saveShows.sh${NO_COLOR}.\n\n"
printf "First, print the help file...\n"
./saveShows.sh -h
waitUntil -k
clear

while true; do
    if waitUntil "$YN_PREF" -Y 'Run ./saveShows.sh tt1606375'; then
        ./saveShows.sh tt1606375
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./saveShows.sh tt1606375 tt1399664 "Broadchurch"'; then
        ./saveShows.sh tt1606375 tt1399664 "Broadchurch"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./saveShows.sh "The Crown"'; then
        ./saveShows.sh "The Crown"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./saveShows.sh tt1606375 tt1399664 broadchurch "the crown"'; then
        ./saveShows.sh tt1606375 tt1399664 broadchurch "the crown"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./saveShows.sh "The Crown" River'; then
        ./saveShows.sh "The Crown" River
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./saveShows.sh -f Dramas.tconst tt1606375'; then
        ./saveShows.sh -f Dramas.tconst tt1606375
    fi
    if waitUntil "$YN_PREF" -Y '\nRun ./saveShows.sh'; then
        ./saveShows.sh
    fi
    if waitUntil "$YN_PREF" -Y '\nRun ./saveShows.sh aaa'; then
        ./saveShows.sh aaa
    fi

    ! waitUntil "$YN_PREF" -Y '\nTests completed. Run again?' && break
    printf "\n"

done
