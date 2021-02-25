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
    printf "==> Verify script lists details, asks about adding 1 show to favorites\n\n"

    printf "==> Removing $favoritesFile\n\n"
    rm -f $favoritesFile
    if waitUntil "$YN_PREF" -Y 'Run ./findCastOf.sh tt1606375?'; then
        ./findCastOf.sh tt1606375
    fi
    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh tt1606375 again'; then
        ./findCastOf.sh tt1606375
    fi

    printf "\n==> Verify -s doesn't list details, asks about adding to favorites\n\n"

    printf "\n==> Removing $favoritesFile\n\n"
    rm -f $favoritesFile
    if waitUntil "$YN_PREF" -Y 'Run ./findCastOf.sh -s tt1606375?'; then
        ./findCastOf.sh -s tt1606375
    fi
    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh -s tt1606375 again'; then
        ./findCastOf.sh -s tt1606375
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh tt1606375 tt1399664 "Broadchurch"'; then
        ./findCastOf.sh tt1606375 tt1399664 "Broadchurch"
    fi
    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh -s tt1606375 tt1399664 "Broadchurch"'; then
        ./findCastOf.sh -s tt1606375 tt1399664 "Broadchurch"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh "The Crown"'; then
        ./findCastOf.sh "The Crown"
    fi
    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh -s "The Crown"'; then
        ./findCastOf.sh -s "The Crown"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh tt1606375 tt1399664 broadchurch "the crown"'; then
        ./findCastOf.sh tt1606375 tt1399664 broadchurch "the crown"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh "The Crown" River'; then
        ./findCastOf.sh "The Crown" River
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./findCastOf.sh "The Night Manager" "The Crown" "The Durrells in Corfu"'; then
        ./findCastOf.sh "The Night Manager" "The Crown" "The Durrells in Corfu"
    fi

    printf "==> Verify -d only lists cast members that are in more than one show.\n\n"

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./findCastOf.sh -d "The Night Manager" "The Crown" "The Durrells in Corfu"'; then
        ./findCastOf.sh -d "The Night Manager" "The Crown" "The Durrells in Corfu"
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./findCastOf.sh -ds "The Night Manager" "The Crown" "The Durrells in Corfu"'; then
        ./findCastOf.sh -ds "The Night Manager" "The Crown" "The Durrells in Corfu"
    fi

    printf "==> Verify extra shows processing.\n\n"

    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh Kasablanka'; then
        ./findCastOf.sh Kasablanka
    fi
    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh Casablanca'; then
        ./findCastOf.sh Casablanca
    fi
    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh Casablanca Broadchurch'; then
        ./findCastOf.sh Casablanca Broadchurch
    fi
    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh "The Bletchley Circle" "Ocean''s Eleven"'; then
        ./findCastOf.sh "The Bletchley Circle" "Ocean's Eleven"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh -f Dramas.tconst tt1606375'; then
        ./findCastOf.sh -f Dramas.tconst tt1606375
    fi
    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh'; then
        ./findCastOf.sh
    fi
    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh aaa'; then
        ./findCastOf.sh aaa
    fi

    ! waitUntil "$YN_PREF" -Y '\nTests completed. Run again?' && break
    printf "\n"

done
