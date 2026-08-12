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

# Short helper: run the scraper CLI from the scraper directory
_scraper() {
    uv run --directory scraper python cli.py "$@"
}

# Seed the demo's data. Every question below queries the local index, which is
# built from .xref_live_cache -- empty in a fresh clone, so an unseeded demo answers
# "I didn't find any matching records" five times over. Scraping these shows
# live at demo time isn't a fix: it's slow, and a new user has no cookies in
# ~/.config/IMDb_xref/browser_state.json, which is exactly when IMDb's WAF is
# most likely to serve a CAPTCHA. So the four shows ship with the repo instead,
# making the demo offline, instant, and identical for everyone.
#
# Contrib/ is used because cleanupEverything.sh deletes .xref_live_* but leaves
# Contrib/ alone -- so the demo still works after a full cleanup.
# Existing cache entries are never overwritten: a user who has already scraped
# these shows keeps their fresher copy.
demoCacheDir="Contrib/demo_cache"
if [[ -d $demoCacheDir ]]; then
    seeded=""
    for demoFile in "$demoCacheDir"/tt*.json; do
        [[ -e $demoFile ]] || break
        if [[ ! -e "$cacheDirectory/$(basename "$demoFile")" ]]; then
            cp "$demoFile" "$cacheDirectory/"
            seeded="yes"
        fi
    done
    if [[ -n $seeded ]]; then
        printf "==> Adding the demo's example shows to %s...\n" "$cacheDirectory"
        _scraper rebuild-index >/dev/null 2>&1
    fi
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
./xrefCast.sh -pn "Princess Diana"

waitUntil -k 'What about Queen Elizabeth?'
./xrefCast.sh -pn "Queen Elizabeth II" 'Princess Diana'

waitUntil -k 'What other shows was Olivia Colman in?'
./xrefCast.sh -dn "Olivia Colman"

waitUntil -k \
    'Are there actors in common between "The Night Manager" "The Crown" "The Durrells"?'
./xrefCast.sh -dn "The Night Manager" 'The Crown' 'The Durrells'

waitUntil -k 'Who was in The Crown?'
./xrefCast.sh -pn "The Crown"

printf "\nThat's All!\n\n"
