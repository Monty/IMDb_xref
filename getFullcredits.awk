# Get credits data from the "Full Cast & Crew" page
#
# Used to debug possibly missing data from the .tsv.gz files
#
# Grab title, grab people by category, add characters for actors
# Process director, writer, actor, producer
# Exit when composer is encountered to cut reading ~50% of file.
/<meta property="pageId"/ {
    split($0, fld, "\"")
    tconstID = fld[4]
    next
}

/<meta name="title" content=/ {
    split($0, fld, "\"")
    showTitle = fld[4]
    sub(/ \(.*/, "", showTitle)
    next
}

/name="director" id="director"/ {
    category = "director"
    rank = 0
    next
}

/name="writer" id="writer"/ {
    category = "writer"
    rank = 0
    next
}

/name="cast" id="cast"/ {
    category = "actor"
    rank = 0
    next
}

/name="producer" id="producer"/ {
    category = "producer"
    rank = 0
    next
}

/^<a href="\/name\// {
    split($0, fld, "/")
    nconstID = fld[3]
    getline

    if ($0 ~ /><img height/) next

    sub(/> /, "")
    name = $0

    if (category != "actor" && name != previousName) {
        rank += 1
        printf(\
            "%s\t%s\t\t%02d\t%s\t\t%s\t%s\n",
            name,
            showTitle,
            rank,
            category,
            nconstID,
            tconstID\
        )
    }

    previousName = name
    next
}

/<a href="\/title\/tt.*\/characters\/nm/ {
    rank += 1
    #
    split($0, fld, "[<>]")
    character = fld[3]
    printf(\
        "%s\t%s\t\t%02d\t%s\t%s\t%s\t%s\n",
        name,
        showTitle,
        rank,
        category,
        character,
        nconstID,
        tconstID\
    )
    next
}

/name="composer" id="composer"/ { exit }
