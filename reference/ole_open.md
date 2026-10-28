# Open an OLE compound file

Reads the header, the sector allocation tables and the directory of a
Microsoft compound file (MS-CFB), also called OLE2 or structured
storage. Stream contents are not read until you ask for them with
[`ole_read()`](https://ethanbass.github.io/olereader/reference/ole_read.md).
Only reading is supported.

## Usage

``` r
ole_open(path)
```

## Arguments

- path:

  Path to the file.

## Value

An `ole_file` object: a list holding

- `path`, `version` (3 or 4) and `file_size`, in bytes;

- `sector_size` and `mini_sector_size`, in bytes, and `n_sectors`, the
  number of sectors after the header;

- `fat` and `minifat`, which give for each sector or mini sector the
  0-based number of the next sector in its chain, or a negative number
  marking the end of a chain or a free or reserved sector;

- `mini_chain`, the 0-based sectors holding the mini stream, or the
  error met while following them;

- `dir`, a data frame with one row per directory entry. Its columns are
  `name`; `type` (1 for a storage, 2 for a stream, 5 for the root);
  `left`, `right` and `child`, the 0-based IDs of the entry's siblings
  and first child, or -1 for none; `start`, its first sector; `size`, in
  bytes; `parent`, the row of the storage holding it, or 0 for the root
  and for entries not reached from it; and `key`, its name with the
  letters A to Z in lower case.

## Details

The file is not kept open: each call to
[`ole_read()`](https://ethanbass.github.io/olereader/reference/ole_read.md)
reopens it. There is nothing to close.

The other functions also take a path in place of an `ole_file` object
and call `ole_open()` on it themselves. A path is simpler for a single
read, but the file is parsed again on every call, so open it once to
read several streams.

Damaged files give an error rather than wrong data: a header or
allocation table that does not fit the size of the file, a chain of
sectors that loops, a directory entry that points past the end of the
directory, or storages nested more than 64 levels deep.

## See also

[`ole_streams()`](https://ethanbass.github.io/olereader/reference/ole_streams.md),
[`ole_read()`](https://ethanbass.github.io/olereader/reference/ole_read.md),
[`ole_size()`](https://ethanbass.github.io/olereader/reference/ole_size.md),
[`ole_extract()`](https://ethanbass.github.io/olereader/reference/ole_extract.md)

## Examples

``` r
ole <- ole_open(system.file("extdata", "example.cfb", package = "olereader"))
ole
#> <ole_file> /home/runner/work/_temp/Library/olereader/extdata/example.cfb
#>   version 3, 512-byte sectors, 2 streams
```
