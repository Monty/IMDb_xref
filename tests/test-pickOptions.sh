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

printf "==> Testing ${RED}pickOptions${NO_COLOR}.\n"
cat <<EOF
    Supplying  parameters that should trigger pickOptions in scripts.
    Check that sort order and expected results are correct.
    Select "Skip" or "Quit" if you want to minimize output.

EOF

while true; do
    if waitUntil "$YN_PREF" -Y '\nRun ./findCastOf.sh Fargo Shaft'; then
        ./findCastOf.sh Fargo Shaft
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh "John Wayne" "Robert Downey"'; then
        ./findShowsWith.sh "John Wayne" "Robert Downey"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./saveFilmography.sh "John Wayne" "Robert Downey"'; then
        ./saveFilmography.sh "John Wayne" "Robert Downey"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./iQuery.sh'; then
        ./iQuery.sh
    fi

    ! waitUntil "$YN_PREF" -Y '\nTests completed. Run again?' && break
    printf "\n"

done
