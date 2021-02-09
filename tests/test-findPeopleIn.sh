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

printf "==> Testing ${RED}findPeopleIn.sh${NO_COLOR}.\n\n"
printf "First, print the help file...\n"
./findPeopleIn.sh -h
waitUntil -k
clear

while true; do
    if waitUntil "$YN_PREF" -Y 'Run ./findPeopleIn.sh tt1606375'; then
        ./findPeopleIn.sh tt1606375
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleIn.sh -d tt1606375'; then
        ./findPeopleIn.sh -d tt1606375
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleIn.sh tt1606375 tt1399664 "Broadchurch"'; then
        ./findPeopleIn.sh tt1606375 tt1399664 "Broadchurch"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleIn.sh -d tt1606375 tt1399664 "Broadchurch"'; then
        ./findPeopleIn.sh -d tt1606375 tt1399664 "Broadchurch"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleIn.sh "The Crown"'; then
        ./findPeopleIn.sh "The Crown"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleIn.sh -d "The Crown"'; then
        ./findPeopleIn.sh -d "The Crown"
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./findPeopleIn.sh tt1606375 tt1399664 broadchurch "the crown"'; then
        ./findPeopleIn.sh tt1606375 tt1399664 broadchurch "the crown"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleIn.sh "The Crown" River'; then
        ./findPeopleIn.sh "The Crown" River
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./findPeopleIn.sh "The Night Manager" "The Crown" "The Durrells in Corfu"'; then
        ./findPeopleIn.sh "The Night Manager" "The Crown" "The Durrells in Corfu"
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./findPeopleIn.sh -d "The Night Manager" "The Crown" "The Durrells in Corfu"'; then
        ./findPeopleIn.sh -d "The Night Manager" "The Crown" "The Durrells in Corfu"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findPeopleIn.sh aaa'; then
        ./findPeopleIn.sh aaa
    fi

    ! waitUntil "$YN_PREF" -Y '\nTests completed. Run again?' && break
    printf "\n"

done
