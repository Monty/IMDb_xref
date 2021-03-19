# Get person data from the filmography page
#
# Used to debug possibly missing data from the .tsv.gz files
#
# Grab tconstID, nconstID, and job
# Exit when NameFilmographyWidget_finished encountered to cut reading some of file.

/<meta property="pageId" content="/ {
    split ($0,fld,"\"")
    nconstID = fld[4]
    next
}

/<a name=".*credit/ {
    split ($0,fld,"\"")
    job = fld[2]
    next
}

/<b><a href="\/title\/tt/ {
    split ($0,fld,"/")
    tconstID = fld[3]
    printf ("%s\t%s\t%s\n",tconstID,nconstID,job)
    next
}

/NameFilmographyWidget_finished/ {
    exit
}
