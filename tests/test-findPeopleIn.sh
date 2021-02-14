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

printf "==> Testing ${RED}findCastOf.sh${NO_COLOR}.\n\n"
printf "First, print the help file...\n"
./findCastOf.sh -h
waitUntil -k
clear

while true; do
    if waitUntil "$YN_PREF" -Y 'Run ./findCastOf.sh tt1606375'; then
        ./findCastOf.sh tt1606375
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh -d tt1606375'; then
        ./findCastOf.sh -d tt1606375
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh tt1606375 tt1399664 "Broadchurch"'; then
        ./findCastOf.sh tt1606375 tt1399664 "Broadchurch"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh -d tt1606375 tt1399664 "Broadchurch"'; then
        ./findCastOf.sh -d tt1606375 tt1399664 "Broadchurch"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh "The Crown"'; then
        ./findCastOf.sh "The Crown"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh -d "The Crown"'; then
        ./findCastOf.sh -d "The Crown"
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./findCastOf.sh tt1606375 tt1399664 broadchurch "the crown"'; then
        ./findCastOf.sh tt1606375 tt1399664 broadchurch "the crown"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh "The Crown" River'; then
        ./findCastOf.sh "The Crown" River
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./findCastOf.sh "The Night Manager" "The Crown" "The Durrells in Corfu"'; then
        ./findCastOf.sh "The Night Manager" "The Crown" "The Durrells in Corfu"
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./findCastOf.sh -d "The Night Manager" "The Crown" "The Durrells in Corfu"'; then
        ./findCastOf.sh -d "The Night Manager" "The Crown" "The Durrells in Corfu"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh aaa'; then
        ./findCastOf.sh aaa
    fi

    ! waitUntil "$YN_PREF" -Y '\nTests completed. Run again?' && break
    printf "\n"

done
