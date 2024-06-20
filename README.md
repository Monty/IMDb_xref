## IMDb_xref

Quickly search IMDb for principal cast members of TV shows or movies, characters
they portray, other shows they are in, and whether multiple shows have cast
members in common.

Create comprehensive lists and spreadsheets about your favorite shows. They're
useful as an overview or for researching details on shows and cast members. For
example, [shows with episode titles](docs/OutputFiles/Shows-Episodes.tsv),
[credits sorted by show/episode](docs/OutputFiles/Credits-Show.tsv), and
[credits sorted by cast member](docs/OutputFiles/Credits-Person.tsv).

[![MIT License](https://img.shields.io/github/license/Monty/IMDb_xref)](LICENSE)
[![Code](https://tokei.rs/b1/github/Monty/IMDb_xref?category=code)](https://github.com/Monty/IMDb_xref)
[![Lines](https://tokei.rs/b1/github/Monty/IMDb_xref?category=lines)](https://github.com/Monty/IMDb_xref)
[![Files](https://tokei.rs/b1/github/Monty/IMDb_xref?category=files)](https://github.com/Monty/IMDb_xref)
[![Commits](https://badgen.net/github/commits/Monty/IMDb_xref/main/)](https://github.com/Monty/IMDb_xref)
[![Last Commit](https://img.shields.io/github/last-commit/Monty/IMDb_xref)](https://github.com/Monty/         IMDb_xref)

**Table of Contents**

- [Motivation](#motivation)
  - [A simpler solution](#a-simpler-solution)
- [Download IMDb_xref](#download-imdb_xref)
- [Automated quickstart](#automated-quickstart)
  - [Understanding query results](#understanding-query-results)
  - [Cross-reference saved shows](#cross-reference-saved-shows)
  - [Search term hints](#search-term-hints)
- [Manual installation](#manual-installation)
  - [Install prerequisites](#install-prerequisites)
  - [Generate sample data](#generate-sample-data)
  - [Run sample queries](#run-sample-queries)
  - [Generate additional data](#generate-additional-data)
  - [Explore other commands](#explore-other-commands)
- [Limitations](#limitations)
- [Compatibility](#compatibility)
- [Suggestions](#suggestions)
- [Performance](#performance)
- [Contributing](#contributing)
- [License](#license)

## Motivation

When watching a TV show or movie, have you ever spotted a familiar face but
can't remember the actor's name or what other shows you've seen them in?

To solve this I used to go to the IMDb website; find the show; click on "See
full cast & crew"; find the character; click on the actor's name; then scroll
through their "Filmography" to see if I recognized any other shows I'd watched.
This was both time-consuming and difficult -- even more so if I wanted to know
if two shows had actors in common.

I wrote **IMDb_xref** to answer such questions simply and quickly. Now I have
even more fun learning about actors and shows.

### A simpler solution

Suppose you're a fan of the PBS series "The Crown". You start watching "The
Night Manager". You recognize the actress who played Princess Diana in "The
Crown" but aren't sure of her name.

Run `start.command`, select `1) Find shows, then list their top 50 cast & crew members`. Enter **`The Crown`**, enter **`The Night Manager`**, enter a blank
line. *It will find 5 shows titled The Crown - select #5, the tvSeries.* *It will find 2 shows titled The Night Manager - select #3, the one dated 2016.* It will
display the cast of "The Crown", the cast of "The Night Manager", and finally,
the principal cast members who appear in more than one show. You can easily see
that the actress you were looking for is Elizabeth Debicki.

![Finding duplicates](docs/Screenshots/duplicates.png?raw=true)

If you like those shows, save them to your favorites. It will enable some
advanced features we'll cover later.

Then select `4) Find people, then list all shows having them as a principal cast or crew member`. Enter **`Elizabeth Debicki`**. It will find the titles listing Elizabeth Debicki as: self, actress, etc. Enter "n" for any categories you don't want to see.

![Debicki as actress](docs/Screenshots/Debicki.png?raw=true)

Repeat with any cast members you want to know more about, such as Olivia Colman.
You'll discover she is in 130 shows, including "Broadchurch".

Look up the cast of "Broadchurch" to find more actors, then find more shows and
even more actors. Enjoy exploring! Each query result includes handy links to
imdb.com in case you only want to use **IMDb_xref** as a less cumbersome IMDb
search tool.

## Download IMDb_xref

Either **[download an IMDb_xref
release](https://github.com/Monty/IMDb_xref/releases)** or type those commands
into a terminal window:

```sh
git clone https://github.com/Monty/IMDb_xref.git
cd IMDb_xref
```

If you get a pop-up saying: 'The "git" command requires the command line
developer tools. Would you like to install the tools now?', click the
"[Install](docs/Screenshots/Install_Dev-Tools.png?raw=true)" button, not the
"Get Xcode" button.

## Automated quickstart

In a terminal window, type `./start.command`. In macOS, you can simply
double-click the `start.command` icon. (*The first time, control-click or
right-click instead. Then select `Open` from the pop-up menu and click `Open` in
the dialog box.*)

This will set up your preferences, install prerequisites, download the
compressed IMDb data files, and open the top-level menu shown below.

![Top-level menu](docs/Screenshots/startMenu.png?raw=true)

Select #1 `Find shows, then list their top 50 cast & crew members`. Enter
the title of a movie or TV show you like. If you know another show starring some
of the same actors, enter that on the next line. Then enter a blank line.

### Understanding query results

The "Searching for" section lists the search terms used, one per line. If you
get unexpected results in a complex query, check it to see if you mistyped a
search term.

The "Principal cast & crew" section contains all rows with a match for **any**
term. It can be quite long for complex queries.

The "... listed in more than one" section contains only rows with names
found in more than one show. It can be empty.

Selecting #2 `Find shows, then list only cast & crew members they share` will hide the "Principal cast & crew" section. Running identical queries
using #1 and #2 will give you an understanding of when each is useful.

Menu selections #4 and #5 search for principal cast and crew members instead of
show titles. Results should be self-explanatory.

### Cross-reference saved shows

When prompted in #1 or #2, add some shows to your favorites, and update your
data files. That will create lists and spreadsheets that combine data for
cross-referencing. Those files are much smaller, enabling faster queries.

Select #6 `Run a cross-reference of your cached shows` to enter search terms a
line at a time.

You can mix and match shows, cast or crew members, and characters portrayed in a
single search, e.g. The Crown, Olivia Colman, and Queen Elizabeth. Search for
two or more actors to see if they appear in any shows together. Search for two
or more shows to see which actors, if any, appear in more than one.

Select #7 `Run a guided cross-reference of your cached shows` to predict and fill
in search terms with minimal typing. This is particularly useful on a tablet
running a terminal emulator. *I use the free version of Termius on an iPad, but
others should work also.*

You can use #8, `Show me a list of my saved shows` to make sure you have saved
the necessary shows before cross-referencing.

### Search term hints

You don't need to quote a search term or escape spaces and other special
characters. **`The Crown`** or **`Schitt's Creek`** will both be handled
correctly.

Shows with non-English titles such as **`Jo Nesbø's Headhunters`** or cast
member names like **`Rolf Lassgård`** must be entered exactly. You can
copy/paste such search terms, or use a tconst/nconst found in their IMDb URL,
e.g. https://imdb.com/title/tt1614989/ and https://www.imdb.com/name/nm0489858/

Searches use "smart case". If there are no uppercase letters in **any** search
term, searches will match both uppercase and lowercase letters. However, you may
get more results than if your search terms were exact.

## Manual installation

If you are comfortable typing commands into a terminal window, you may prefer
using the following steps to set things up yourself.

### Install prerequisites

Install **ripgrep** to get acceptable performance. Searching 700 MB of
compressed data with zgrep is 15x slower. See
[https://crates.io/crates/ripgrep](https://crates.io/crates/ripgrep). (*If
anyone wants to rewrite this to use zgrep or another search engine, be my
guest.*)

While it's not required, **xsv** improves table layout, especially for
non-English names, by using "elastic tabs". See
[https://crates.io/crates/xsv](https://crates.io/crates/xsv).

### Generate sample data

Run `./generateXrefData.sh` to download the IMDb data files and generate lists
and spreadsheets containing principal cast members, characters portrayed,
alternate titles, and other details from IMDb. This takes 40 seconds on my 2014
iMac. (*Note: Longer if you have a slow internet connection.*)

Re-running `./generateXrefData.sh` doesn't download the IMDb data files again.
This reduces the run time to 20 seconds. It will overwrite any previously
generated files.

### Run sample queries

Run `./xrefCast.sh -h` (help) to see some example queries that can be typed
into a terminal window.

Run `./demo.command` to see the types of information returned from those queries
and more.

### Generate additional data

Since `./generateXrefData.sh` displays statistics as it runs, you probably
noticed that it only produced data on 3 shows with 92 episodes -- crediting 87
people with 758 lines of credits. It did so by selecting three PBS shows from
**`example.tconst`** and creating the example files **`PBS.tconst`** and
**`PBS.xlate`**.

If you run `./generateXrefData.sh -t`, it will load all the shows in
**`tconst.example`**. You'll now have data on 98 shows with 2541 episodes --
crediting 8457 people with 38151 lines of credits. Running this takes about 2
minutes. However, queries should still take less than one second.

You can clean up any data you don't want by running `cleanupEverything.sh`. I
suggest you don't delete anything until you've run through the entire list of
choices it offers.

### Explore other commands

All the commands in the top-level menu invoke shell scripts that can be run in a
terminal window, supplying options and parameters on the command line.

To learn more run `./explain_scripts.sh` or examine the included shell scripts.

If you run commands as shell scripts, you'll need to be careful to quote and
escape spaces and other special characters.

If you run one of the commands in the top-level menu as a shell script, it will
still open the top-level menu when it exits. I find this convenient, but if you
would prefer that it exit, simply set a NO_MENUS environment variable, i.e.
`export NO_MENUS="yes"`.

## Limitations

Data downloaded from IMDb often has errors or omissions. It has less information
on cast and crew than is available on the IMDb website.

Data on shows only includes "**Principal** cast & crew members", which is
limited to 10 persons per show. Queries for movies only return those 10. Queries
for TV shows can return more than 10 because each episode has its own credits --
which is why you can see 56 "Principal cast & crew members" for "The Crown".

IMDb prohibits scraping their website, but you can use the imdb.com links we
provide to access the "Full Cast & Crew" data online.

Downloading IMDb data frequently is not as beneficial as you might think. While
the data is updated daily, those updates are usually minor changes, like
changing the type of a show from tvSeries to tvEpisode, or changing the titles a
person is most known for.

Queries for principal cast & crew members can include results you might not
expect, e.g. cinematographers and editors. However, updating your data files
only saves actors, actresses, writers, directors, and producers. To save all
types run `generateXrefData.sh -a` at any time. You may want to also use the
`-d` or `-f` options to prevent the larger results from being overwritten.

Queries for all shows listing a person as a principal cast or crew member can
include results you might not expect, e.g. videoGame or radioSeries. For each
type, you will be asked if you want to display those results.

## Compatibility

Tested on macOS and Linux. It may work in Windows 10 if [Windows Subsystem for
Linux](https://docs.microsoft.com/en-us/windows/wsl/faq) is installed.

## Suggestions

Start your own lists: broad genres such as Comedies, Sci-Fi, Musicals,
Historical Dramas -- or more specific ones like "All Alfred Hitchcock movies",
"TV shows with Robots", or "shows with Salsa music", "Shows for Trivia
questions".

Until I find time to produce more documentation, you can learn a lot from the
descriptive comments in the shell scripts, .example, and [Contrib](Contrib)
files.

## Performance

Even complex queries on 14MB of saved shows run in less than 100ms on my 2014
iMac, 25ms on my 2019 MacBook Pro with an internal SSD.  There is almost no
difference between using gzipped data and non-gzipped data.

<details><summary><b>Show comparative benchmarks</b></summary>

Timing results for running 5 queries on gzipped and non-gzipped files.  Both
contain 219510 rows. The gzipped file is 3.0MB, the non-gzipped file is 14MB.
The times are nearly identical, with a very slight edge to the gzipped version.

#### On a 2014 iMac with internal hard drive:

```sh
$ hyperfine -w 5 './xrefTest.sh -f ZipTest.csv' './xrefTest.sh -f ZipTest.csv.gz'
Benchmark #1: ./xrefTest.sh -f ZipTest.csv
  Time (mean ± σ):      95.2 ms ±   0.9 ms    [User: 28.3 ms, System: 46.2 ms]
  Range (min … max):    92.9 ms …  97.2 ms    30 runs

Benchmark #2: ./xrefTest.sh -f ZipTest.csv.gz
  Time (mean ± σ):      94.9 ms ±   1.0 ms    [User: 28.4 ms, System: 45.7 ms]
  Range (min … max):    92.9 ms …  97.9 ms    30 runs

Summary
  './xrefTest.sh -f ZipTest.csv.gz' ran
    1.00 ± 0.01 times faster than './xrefTest.sh -f ZipTest.csv'
```

#### On a 2019 MacBook Pro with an internal SSD.

```
$ hyperfine -w 5 './xrefTest.sh -f ZipTest.csv' './xrefTest.sh -f ZipTest.csv.gz'
Benchmark #1: ./xrefTest.sh -f ZipTest.csv
  Time (mean ± σ):      17.0 ms ±   1.0 ms    [User: 6.0 ms, System: 8.8 ms]
  Range (min … max):    16.1 ms …  23.0 ms    155 runs

Benchmark #2: ./xrefTest.sh -f ZipTest.csv.gz
  Time (mean ± σ):      16.8 ms ±   0.7 ms    [User: 5.9 ms, System: 8.7 ms]
  Range (min … max):    16.1 ms …  20.7 ms    155 runs

Summary
  './xrefTest.sh -f ZipTest.csv.gz' ran
    1.01 ± 0.07 times faster than './xrefTest.sh -f ZipTest.csv'
```

</details>

## Contributing

Feel free to dive in! Contribute an interesting tconst list, submit additional
scripts, [Open an issue](https://github.com/Monty/IMDb_xref/issues/new), or
submit PRs.

## License

[MIT](LICENSE) © Monty Williams
