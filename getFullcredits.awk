# Get credits data from the "Full Cast & Crew" page
#
# Used to debug possibly missing data from the .tsv.gz files
#
# Grab title, grab people by category, add characters for actors
# Process director, writer, actor, producer
# Exit when composer is encountered to cut reading ~50% of file.

/<meta name="title" content=/ {
    split ($0,fld,"\"")
    showTitle = fld[4]
    sub (/ \(.*/,"",showTitle)
    next
}

/name="director" id="director"/ {
    category = "director"
    next
}

/name="writer" id="writer"/ {
    category = "writer"
    next
}

/name="cast" id="cast"/ {
    category = "actor"
    next
}

/name="producer" id="producer"/ {
    category = "producer"
    next
}

/^<a href="\/name\// {
    getline
    if ($0 ~ /><img height/)
        next
    sub (/> /,"")
    name = $0
    if (category != "actor") {
        printf ("%s\t%s\t\t\t%s\t\n",name,showTitle,category)
    }
    next
}

/<a href="\/title\/tt.*\/characters\/nm/ {
    rank += 1
    #
    split ($0,fld,"[<>]")
    character =  fld[3]
    printf ("%s\t%s\t\t%02d\t%s\t%s\n",name,showTitle,rank,category,character)
    next
}

/name="composer" id="composer"/ {
    exit
}
