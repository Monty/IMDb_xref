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

clear
cat <<EOF

When watching a TV show or movie, have you ever spotted a familiar face but
can't remember the actor's name or what other shows you've seen them in?

To solve this I used to go to the IMDb website; find the show; click on "See
full cast & crew"; find the character; click on the actor's name; then scroll
through their "Filmography" to see if I recognized any other shows I'd watched.
This was both time-consuming and difficult -- even more so if I wanted to know
if two shows had actors in common.

I wrote IMDb_xref to answer such questions simply and quickly. Now I have
even more fun learning about actors and shows.

The following screens will first pose a question about the PBS show "The Crown"
then pause. Hitting any key will find the answer, then pause again.
EOF
waitUntil -k # Default prompt for -k is: "Hit any key to continue, '^C' to quit."

waitUntil -kc 'What actresses played Princess Diana?'
./xrefCast.sh -pn "Princess Diana"
waitUntil -k

waitUntil -kc 'What about Queen Elizabeth?'
./xrefCast.sh -pn "Queen Elizabeth II" 'Princess Diana'
waitUntil -k

waitUntil -kc 'What other shows was Olivia Colman in?'
./xrefCast.sh -dn "Olivia Colman"
waitUntil -k

waitUntil -kc \
    'Are there actors in common between "The Night Manager" "The Crown" "The Durrells in Corfu"?'
./xrefCast.sh -dn "The Night Manager" 'The Crown' 'The Durrells in Corfu'
waitUntil -k

waitUntil -kc 'Who was in The Crown?'
./xrefCast.sh -pn "The Crown"
waitUntil -k

clear
printf "\nThat's All!\n\n"
