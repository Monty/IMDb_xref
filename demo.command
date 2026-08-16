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

# A first-time user has no data files. Build them from the committed demo
# corpus rather than from whatever .tconst files happen to be present, so the
# questions below always have answers -- and don't ask, since someone who has
# just launched the demo has no basis on which to decide. Only fires when
# Credits-Person.csv is genuinely absent, so a populated corpus is left alone.
[[ ! -e "Credits-Person.csv" ]] && ensureDataFiles -y Contrib/demo.tconst

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
./xrefCast.sh -pn "Princess Diana"

waitUntil -k 'What about Queen Elizabeth?'
./xrefCast.sh -pn "Queen Elizabeth II" 'Princess Diana'

waitUntil -k 'What other shows was Olivia Colman in?'
./xrefCast.sh -dn "Olivia Colman"

waitUntil -k \
    'Are there actors in common between "The Night Manager" "The Crown" "The Durrells"?'
./xrefCast.sh -dn "The Night Manager" 'The Crown' 'The Durrells'

# No FULLCAST save/restore around this last question any more. It existed
# because FULLCAST switched xrefCast.sh onto the cross-reference cache, so the
# demo had to unset it to keep the character searches above working, then put it
# back so the last answer matched what the owner's environment would give. The
# cache is now reached only with an explicit -c, so every question here reads
# Credits-Person.csv and the demo gives the same answers to everyone.
waitUntil -k 'Who was in The Crown?'
./xrefCast.sh -pn "The Crown"

printf "\nThat's All!\n\n"
