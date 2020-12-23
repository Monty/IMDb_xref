#!/usr/bin/env bash
# Run a short demo

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd $DIRNAME
export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

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
ask_YN -w # Default prompt for -w is: "Hit any key to continue, '^C' to quit."

ask_YN -wc 'What actresses played Princess Diana?'
./xrefCast.sh -a "Princess Diana"
ask_YN -w

ask_YN -wc 'What about Queen Elizabeth?'
./xrefCast.sh -a "Queen Elizabeth II" 'Princess Diana'
ask_YN -w

ask_YN -wc 'What other shows was Olivia Colman in?'
./xrefCast.sh -s "Olivia Colman"
ask_YN -w

ask_YN -wc 'Are there actors in common between "The Night Manager" "The Crown" "The Durrells in Corfu"?'
./xrefCast.sh -s "The Night Manager" 'The Crown' 'The Durrells in Corfu'
ask_YN -w

ask_YN -wc 'Who was in The Crown?'
./xrefCast.sh -a "The Crown"
ask_YN -w

clear
printf "\nThat's All!\n\n"
