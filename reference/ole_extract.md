# Extract OLE streams to files

Writes each stream to a file under `dir`, with one folder for each
storage that contains it, so `c("storage", "stream")` becomes
`dir/storage/stream`.

## Usage

``` r
ole_extract(ole, dir, streams = NULL, overwrite = FALSE)
```

## Arguments

- ole:

  An `ole_file` object from
  [`ole_open()`](https://ethanbass.github.io/olereader/reference/ole_open.md),
  or the path to a compound file, which is opened and parsed again on
  every call.

- dir:

  Folder to write to. It is created if it does not exist.

- streams:

  The streams to extract, or `NULL` (the default) for all of them.
  Either a character vector with one `/`-separated path per stream, such
  as `c("data", "notes/readme")`, or a list of paths like the one
  returned by
  [`ole_streams()`](https://ethanbass.github.io/olereader/reference/ole_streams.md).
  In a list, each path is a vector of names, such as
  `list("data", c("notes", "readme"))`, and strings are not split at
  `/`, so `list("notes/readme")` looks for a stream named `notes/readme`
  outside any storage.

- overwrite:

  Whether to replace files that already exist. If `FALSE` (the default),
  extraction stops at the first file that already exists, including one
  written by an earlier stream in the same call.

## Value

The paths of the files written, invisibly, named by stream.

## Details

Names are changed where they would not work as file names on every
platform. Control characters and `<>:"/\|?*` are replaced with `_`,
trailing dots and spaces are removed, names left empty (including `.`
and `..`) become `_`, and 'Windows' device names such as `CON` or
`NUL.txt` get a `_` prefix. The names in a file cannot place a file
outside `dir`.

`ole_extract()` stops before writing anything if a requested stream does
not exist, if two streams would be written to the same file (ignoring
case), or if the streams add up to more bytes than the file holds, which
means it is truncated or has streams sharing sectors. Any other error
stops extraction partway, and the files already written are left in
place.

## Examples

``` r
ole <- ole_open(system.file("extdata", "example.cfb", package = "olereader"))
dir <- file.path(tempdir(), "example")
ole_extract(ole, dir)
list.files(dir, recursive = TRUE)
#> [1] "data"         "notes/readme"

ole_extract(ole, dir, streams = "notes/readme", overwrite = TRUE)
unlink(dir, recursive = TRUE)
```
