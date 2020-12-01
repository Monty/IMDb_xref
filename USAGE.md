#### Prerequisites

Install **[ripgrep](https://crates.io/crates/xsv)** to get acceptable performance.
Searching 700 MB of compressed data with **zgrep** is 15x slower. See
[https://crates.io/crates/ripgrep](). (*If someone wants to rewrite this to use
zgrep or another search engine, be my guest.*)

While it's not required, **[xsv](https://crates.io/crates/xsv)** greatly improves
table layout, especially for non-English names, by using "elastic tabs". See
[https://crates.io/crates/xsv]()

#### Get started quickly

Run **./makeSpreadsheets.sh** to download the IMDb data files and generate lists
and spreadsheets containing cast members, characters portrayed, alternate titles,
and other details from **[IMDb]([https://www.imdb.com/interfaces/]())**. This
takes 40 seconds on my 2014 iMac (*Note: I have a fast internet connection.*)

Re-running **./makeSpreadsheets.sh** doesn't download the IMDb data files again.
This reduces the run time to 20 seconds. It will overwrite any spreadsheets
produced earlier that day but not those from any previous day.

Run **./demo.sh** to see what types of information can be returned from queries.
Each query should take less than one second.

Since **./makeSpreadsheets.sh** displays statistics as it runs, you probably
noticed that it only produced data on 3 shows with 92 episodes -- crediting 81
people with 684 lines of credits.

If you run **./makeSpreadsheets.sh -t**, you'll get 98 shows with 2179
episodes -- crediting 3607 people with 17275 lines of credits. Running this takes
about 45 seconds. However, queries should still take less than one second.

Data can grow quite large. If you use all the files in /Contrib, you'll generate
7.5 MB of data on 361 shows, including two 46,000 line Credits spreadsheets.

Run **./xrefCast.sh -h** to see some example queries. Experiment making up other
queries. One may lead to another...

***Protip***: typing **alias xr="${PWD}/xrefCast.sh \\"\\$@\\""** 
while in this directory will allow you to type **xr 'Princess Diana'** instead of
**./xrefCast.sh 'Princess Diana'** -- and **xr** can be run from anywhere.

#### Go further

You can select different shows by using one or more of the .tconst files in the
Contrib directory or creating your own .tconst file. You can even translate
non-English titles to their English equivalents by using a .xlate file.

The default for **./makeSpreadsheets.sh** is to use all .tconst and all .xlate
files in the top level directory. So put whatever files you want there.  (*Your
contributions are welcome. Start your own lists: genres such as Comedies, Sci-Fi,
Musicals, Historical Dramas - or more specific lists like "TV shows with Robots")

#### Coming next

Until I get time to produce some documentation, you can learn a lot from the
descriptive comments in the shell scripts and *.example files.
