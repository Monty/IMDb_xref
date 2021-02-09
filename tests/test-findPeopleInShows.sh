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

printf "==> Testing ${RED}findPeopleInShows.sh${NO_COLOR}.\n\n"
printf "First, print the help file...\n"
./findPeopleInShows.sh -h
waitUntil -k
clear

while true; do
    if waitUntil "$YN_PREF" -Y 'Run ./findPeopleInShows.sh tt1606375'; then
        ./findPeopleInShows.sh tt1606375
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleInShows.sh -d tt1606375'; then
        ./findPeopleInShows.sh -d tt1606375
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleInShows.sh tt1606375 tt1399664 "Broadchurch"'; then
        ./findPeopleInShows.sh tt1606375 tt1399664 "Broadchurch"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleInShows.sh -d tt1606375 tt1399664 "Broadchurch"'; then
        ./findPeopleInShows.sh -d tt1606375 tt1399664 "Broadchurch"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleInShows.sh "The Crown"'; then
        ./findPeopleInShows.sh "The Crown"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleInShows.sh -d "The Crown"'; then
        ./findPeopleInShows.sh -d "The Crown"
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./findPeopleInShows.sh tt1606375 tt1399664 broadchurch "the crown"'; then
        ./findPeopleInShows.sh tt1606375 tt1399664 broadchurch "the crown"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleInShows.sh "The Crown" River'; then
        ./findPeopleInShows.sh "The Crown" River
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./findPeopleInShows.sh "The Night Manager" "The Crown" "The Durrells in Corfu"'; then
        ./findPeopleInShows.sh "The Night Manager" "The Crown" "The Durrells in Corfu"
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./findPeopleInShows.sh -d "The Night Manager" "The Crown" "The Durrells in Corfu"'; then
        ./findPeopleInShows.sh -d "The Night Manager" "The Crown" "The Durrells in Corfu"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleInShows.sh aaa'; then
        ./findPeopleInShows.sh aaa
    fi

    ! waitUntil "$YN_PREF" -Y '\nTests completed. Run again?' && break
    printf "\n"

done
