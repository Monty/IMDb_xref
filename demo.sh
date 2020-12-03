#!/usr/bin/env bash
# Run a short demo

function query() {
    clear
    read -p "$1"
    shift
    printf "\n"
    ./xrefCast.sh "$@"
    printf '\nHit "Enter" to continue, "^C" to quit. '
    read
}

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
then pause. Hitting "Enter" will find the answer, then pause again.
EOF

printf '\nHit "Enter" to continue, "^C" to quit. '
read

query 'What actresses played Princess Diana? ' '-a' 'Princess Diana'
query 'What about Queen Elizabeth? ' '-a' 'Queen Elizabeth II' 'Princess Diana'
query 'What other shows was Olivia Colman in? ' '-s' 'Olivia Colman'
query 'Are there actors in common between "The Night Manager" "The Crown" "The Durrells in Corfu"?' \
    '-s' 'The Night Manager' 'The Crown' 'The Durrells in Corfu'
query 'Who was in The Crown? ' '-a' 'The Crown'

clear
printf "That's All!\n\n"
