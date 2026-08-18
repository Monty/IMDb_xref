#!/usr/bin/env bash
#
# Run a short demo

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

# Make sure prerequisites are satisfied
ensurePrerequisites

# The demo asks five fixed questions about The Crown, The Durrells, and The
# Night Manager, so it needs those shows -- and only those shows -- to answer.
# Checking for Credits-Person.csv is not enough: an established user has that
# file built from their own .tconst lists, which very likely don't include the
# demo's shows, and the demo then asks five questions about a show it cannot
# see. (Found exactly that way: a clone holding every show Monty has watched,
# which doesn't include The Crown.)
#
# So the demo builds and queries its own corpus in a subdirectory instead of
# depending on whatever is in the working directory. generateXrefData.sh -d
# writes every output under ./Demo/ and, because OUTPUT_DIR is set, skips
# populating the cross-reference cache, recording durations, and saving run
# history -- so running the demo leaves an existing installation untouched.
demoDir="Demo"
demoCredits="$(ls -1t "$demoDir"/Credits-Person*.csv 2>/dev/null | head -1)"

if [[ -z $demoCredits ]]; then
    printf "==> Setting up the demo data files. This takes a few seconds.\n"
    ./generateXrefData.sh -q -d "$demoDir" Contrib/demo.tconst
    demoCredits="$(ls -1t "$demoDir"/Credits-Person*.csv 2>/dev/null | head -1)"
fi

if [[ -z $demoCredits ]]; then
    printf "\n==> [${RED}Error${NO_COLOR}] I couldn't build the demo data files " >&2
    printf "in $demoDir.\n" >&2
    exit 1
fi

clear
cat <<EOF

When watching a TV show or movie, have you ever spotted a familiar
face but can't remember the actor's name or what other shows you've
seen them in?

To solve this I used to go to the IMDb website; find the show; click
on "See full cast & crew"; find the character; click on the actor's
name; then scroll through their "Filmography" to see if I recognized
any other shows I'd watched.  This was both time-consuming and
difficult -- even more so if I wanted to know if two shows had
actors in common.

I wrote IMDb_xref to answer such questions simply and quickly. Now
I have even more fun learning about actors and shows.

The following screens will first pose a question about the PBS show
"The Crown" then pause. Hitting any key will find the answer, then
pause again.
EOF
waitUntil -k # Default prompt for -k is: "Hit any key to continue, '^C' to quit."

waitUntil -k 'What actresses played Princess Diana?'
NO_MENUS="yes" ./xrefCast.sh -p -f "$demoCredits" "Princess Diana"

waitUntil -k 'What about Queen Elizabeth?'
NO_MENUS="yes" ./xrefCast.sh -p -f "$demoCredits" "Queen Elizabeth II" 'Princess Diana'

waitUntil -k 'What other shows was Olivia Colman in?'
NO_MENUS="yes" ./xrefCast.sh -d -f "$demoCredits" "Olivia Colman"

waitUntil -k \
    'Are there actors in common between "The Night Manager" "The Crown" "The Durrells"?'
NO_MENUS="yes" ./xrefCast.sh -d -f "$demoCredits" "The Night Manager" 'The Crown' 'The Durrells'

# Every question queries the demo corpus explicitly with -f, so the answers are
# the same for a first-time user and for someone with hundreds of shows already
# cross-referenced.
#
# No FULLCAST save/restore around this last question any more. It existed
# because FULLCAST switched xrefCast.sh onto the cross-reference cache, so the
# demo had to unset it to keep the character searches above working, then put it
# back so the last answer matched what the owner's environment would give. The
# cache is now reached only with an explicit -c, and -f wins over -c anyway.
waitUntil -k 'Who was in The Crown?'
NO_MENUS="yes" ./xrefCast.sh -p -f "$demoCredits" "The Crown"

printf "\nThat's All!\n\n"
