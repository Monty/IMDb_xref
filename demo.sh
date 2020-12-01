#!/usr/bin/env bash
# Run a short demo

query() {
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

When watching a TV show or movie, I often spot a familiar face but can't
remember the actor's name or what other shows I've seen them in.

So I go to the IMDb website; find the show; click on "See full cast & crew";
find the character; click on the actor's name; then scroll through their
"Filmography" to see if I recognize any other shows I've watched. It is both
time-consuming and difficult. Even more so if I want to know if two shows
have actors in common.

So I wrote a program to answer such questions simply and quickly. Now I have
even more fun learning about actors and shows. You might enjoy that as well.

The following screens run example queries about the PBS show "The Crown" so
you can see what it's like to use.

It will display a question, then pause. Hitting "Enter" will find the answer
then pause again.
EOF

printf '\nHit "Enter" to continue, "^C" to quit. '
read

query 'What actresses played Princess Diana? ' '-a' 'Princess Diana'
query 'What about Queen Elizabeth? ' '-a' 'Queen Elizabeth II' 'Princess Diana'
query 'What other shows was Olivia Colman in? ' '-s' 'Olivia Colman'
query 'Are there actors in common between "The Night Manager" "The Crown" "The Durrells in Corfu"?' \
    '-s' 'The Night Manager' 'The Crown' 'The Durrells in Corfu'
query 'Who was in The Crown? ' '-a' 'The Crown'
