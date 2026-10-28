# List the streams in an OLE file

Streams are listed depth-first, with the entries of each storage sorted
by name, the same order as `listdir()` in the Python package 'olefile'.
Storages themselves are not listed.

## Usage

``` r
ole_streams(ole)
```

## Arguments

- ole:

  An `ole_file` object from
  [`ole_open()`](https://ethanbass.github.io/olereader/reference/ole_open.md),
  or the path to a compound file, which is opened and parsed again on
  every call.

## Value

A named list of character vectors, each the path to a stream: the names
of the storages that contain it, then its own name. The names of the
list are the same paths joined with `/`.

## Examples

``` r
ole <- ole_open(system.file("extdata", "example.cfb", package = "olereader"))
ole_streams(ole)
#> $data
#> [1] "data"
#> 
#> $`notes/readme`
#> [1] "notes"  "readme"
#> 
names(ole_streams(ole))
#> [1] "data"         "notes/readme"
```
