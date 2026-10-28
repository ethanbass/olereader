#' Open an OLE compound file
#'
#' Reads the header, the sector allocation tables and the directory of a
#' Microsoft compound file (MS-CFB), also called OLE2 or structured storage.
#' Stream contents are not read until you ask for them with [ole_read()].
#' Only reading is supported.
#'
#' The file is not kept open: each call to [ole_read()] reopens it. There is
#' nothing to close.
#'
#' The other functions also take a path in place of an `ole_file` object and
#' call `ole_open()` on it themselves. A path is simpler for a single read, but
#' the file is parsed again on every call, so open it once to read several
#' streams.
#'
#' Damaged files give an error rather than wrong data: a header or allocation
#' table that does not fit the size of the file, a chain of sectors that loops,
#' a directory entry that points past the end of the directory, or storages
#' nested more than 64 levels deep.
#' @param path Path to the file.
#' @return An `ole_file` object: a list holding
#' * `path`, `version` (3 or 4) and `file_size`, in bytes;
#' * `sector_size` and `mini_sector_size`, in bytes, and `n_sectors`, the
#'   number of sectors after the header;
#' * `fat` and `minifat`, which give for each sector or mini sector the
#'   0-based number of the next sector in its chain, or a negative number
#'   marking the end of a chain or a free or reserved sector;
#' * `mini_chain`, the 0-based sectors holding the mini stream, or the error
#'   met while following them;
#' * `dir`, a data frame with one row per directory entry. Its columns are
#'   `name`; `type` (1 for a storage, 2 for a stream, 5 for the root);
#'   `left`, `right` and `child`, the 0-based IDs of the entry's siblings and
#'   first child, or -1 for none; `start`, its first sector; `size`, in
#'   bytes; `parent`, the row of the storage holding it, or 0 for the root
#'   and for entries not reached from it; and `key`, its name with the letters
#'   A to Z in lower case.
#' @seealso [ole_streams()], [ole_read()], [ole_size()], [ole_extract()]
#' @examples
#' ole <- ole_open(system.file("extdata", "example.cfb", package = "olereader"))
#' ole
#' @export
ole_open <- function(path){
  path <- path.expand(path)
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  header <- readBin(con, "raw", n = 512)
  signature <- as.raw(c(0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1))
  if (length(header) < 512 || !identical(header[1:8], signature)){
    stop(sQuote(path), " is not an OLE compound file.", call. = FALSE)
  }
  u16 <- function(o) readBin(header[o + 1:2], "integer", size = 2,
                             signed = FALSE, endian = "little")
  i32 <- function(o, n = 1) readBin(header[o + seq_len(4 * n)], "integer",
                                    n = n, size = 4, endian = "little")
  corrupt <- function(what){
    stop("The ", what, " of ", sQuote(path), " is corrupt.", call. = FALSE)
  }
  if (!u16(30) %in% c(9, 12) || u16(32) != 6) corrupt("sector size")
  version <- u16(26)
  sector_size <- 2^u16(30)
  per_sector <- sector_size %/% 4
  file_size <- file.size(path)
  n_sectors <- ceiling(file_size / sector_size) - 1
  n_fat <- i32(44)
  if (is.na(n_fat) || n_fat < 1 || n_fat > n_sectors) corrupt("header")

  difat <- i32(76, 109)
  sector <- i32(68)
  seen <- integer(0)
  while (length(difat) < n_fat){
    if (is.na(sector) || sector < 0 || sector >= n_sectors || sector %in% seen){
      corrupt("sector allocation table")
    }
    seen <- c(seen, sector)
    entries <- ole_int32(ole_read_sectors(con, sector, sector_size))
    difat <- c(difat, entries[-per_sector])
    sector <- entries[per_sector]
  }
  difat <- difat[seq_len(n_fat)]
  if (anyNA(difat) || any(difat < 0 | difat >= n_sectors)){
    corrupt("sector allocation table")
  }
  fat <- ole_int32(ole_read_sectors(con, difat, sector_size))
  fat <- fat[seq_len(min(length(fat), n_sectors))]

  ole <- list(path = path, version = version, sector_size = sector_size,
              mini_sector_size = 64, file_size = file_size,
              n_sectors = n_sectors, fat = fat)
  ole$minifat <- if (!is.na(i32(64)) && i32(64) > 0){
    ole_int32(ole_read_sectors(con, ole_chain(fat, i32(60)), sector_size))
  } else integer(0)
  ole$dir <- ole_directory(ole_read_sectors(con, ole_chain(fat, i32(48)),
                                            sector_size), version)
  if (!nrow(ole$dir) || ole$dir$type[1] != 5L) corrupt("directory")
  ole$mini_chain <- tryCatch({
    n <- ceiling(ole$dir$size[1] / sector_size)
    if (n > n_sectors) stop("The mini stream of ", sQuote(path),
                            " is larger than the file.", call. = FALSE)
    ole_chain(fat, ole$dir$start[1], n)
  }, error = function(e) e)
  structure(ole, class = "ole_file")
}

#' @export
print.ole_file <- function(x, ...){
  cat("<ole_file> ", x$path, "\n", sep = "")
  cat("  version ", x$version, ", ", x$sector_size, "-byte sectors, ",
      length(ole_streams(x)), " streams\n", sep = "")
  invisible(x)
}

#' Parse the directory entries of an OLE file
#'
#' Each entry is 128 bytes. Children of a storage form a red-black tree
#' through their left and right sibling IDs; the walk below collects every
#' entry reachable from the root and records its parent.
#' @noRd
ole_directory <- function(bytes, version){
  m <- bytes
  length(m) <- length(m) %/% 128 * 128
  dim(m) <- c(128L, length(m) %/% 128)
  w <- matrix(readBin(m, "integer", n = length(m) %/% 4, size = 4,
                      endian = "little"), nrow = 32)
  u32 <- function(word){
    x <- as.numeric(w[word, ])
    x[is.na(x)] <- -2^31
    x %% 2^32
  }
  id <- function(word){
    x <- u32(word)
    ifelse(x >= 0xFFFFFFFA, -1, x)
  }
  n <- ncol(m)
  name_len <- as.integer(m[65, ]) + 256L * as.integer(m[66, ])
  name_len <- pmax(pmin((name_len + 1L) %/% 2L * 2L, 64L) - 2L, 0L)
  nul <- which(m[seq(1, 63, 2), , drop = FALSE] == as.raw(0) &
                 m[seq(2, 64, 2), , drop = FALSE] == as.raw(0), arr.ind = TRUE)
  first <- !duplicated(nul[, 2])
  name_len[nul[first, 2]] <- pmin(name_len[nul[first, 2]],
                                  2L * (nul[first, 1] - 1L))
  pos <- rep(1:64, n)
  keep <- pos <= rep(name_len, each = 64)
  b <- m[1:64, , drop = FALSE][keep]
  pos <- pos[keep]
  entry <- factor(rep(seq_len(n), each = 64)[keep], levels = seq_len(n))
  utf8 <- function(b){
    x <- iconv(unname(split(b, entry)), from = "UTF-16LE", to = "UTF-8",
               sub = "\ufffd")
    x[is.na(x)] <- "\ufffd"
    x
  }
  names <- utf8(b)
  upper <- which(pos %% 2L == 1L & b >= as.raw(0x41) & b <= as.raw(0x5A))
  upper <- upper[b[upper + 1L] == as.raw(0)]
  b[upper] <- as.raw(as.integer(b[upper]) + 32L)
  keys <- utf8(b)
  size <- u32(31)
  if (version >= 4) size <- size + u32(32) * 2^32
  dir <- data.frame(name = names, type = as.integer(m[67, ]),
                    left = id(18), right = id(19), child = id(20),
                    start = id(30), size = size)

  type <- dir$type
  left <- dir$left
  right <- dir$right
  child <- dir$child
  parent <- integer(n)
  depth <- integer(n)
  visited <- logical(n)
  stack_id <- numeric(3 * n + 1)
  stack_parent <- integer(3 * n + 1)
  top <- 0L
  if (n){
    visited[1] <- TRUE
    top <- 1L
    stack_id[1] <- child[1] + 1
    stack_parent[1] <- 1L
  }
  while (top > 0){
    i <- stack_id[top]
    p <- stack_parent[top]
    top <- top - 1L
    if (i > n){
      stop("An entry in the directory of this OLE file points past the end ",
           "of the directory.", call. = FALSE)
    }
    if (i < 1 || visited[i]) next
    visited[i] <- TRUE
    parent[i] <- p
    depth[i] <- depth[p] + 1L
    stack_id[top + 1:2] <- c(left[i], right[i]) + 1
    stack_parent[top + 1:2] <- p
    top <- top + 2L
    if (type[i] == 1L){
      if (depth[i] > 64){
        stop("The storages of this OLE file are nested more than 64 levels ",
             "deep.", call. = FALSE)
      }
      top <- top + 1L
      stack_id[top] <- child[i] + 1
      stack_parent[top] <- i
    }
  }
  dir$parent <- parent
  dir$key <- keys
  dir
}

#' Path of the entry in row `i` of `ole$dir`
#' @noRd
ole_path <- function(ole, i){
  path <- character(0)
  while (i > 1){
    path <- c(ole$dir$name[i], path)
    i <- ole$dir$parent[i]
  }
  path
}

#' List the streams in an OLE file
#'
#' Streams are listed depth-first, with the entries of each storage sorted by
#' name, the same order as `listdir()` in the Python package 'olefile'.
#' Storages themselves are not listed.
#' @inheritParams ole_read
#' @return A named list of character vectors, each the path to a stream: the
#' names of the storages that contain it, then its own name. The names of the
#' list are the same paths joined with `/`.
#' @examples
#' ole <- ole_open(system.file("extdata", "example.cfb", package = "olereader"))
#' ole_streams(ole)
#' names(ole_streams(ole))
#' @export
ole_streams <- function(ole){
  if (is.character(ole)) ole <- ole_open(ole)
  paths <- lapply(ole_stream_rows(ole), ole_path, ole = ole)
  stats::setNames(paths, vapply(paths, paste, "", collapse = "/"))
}

#' Rows of `ole$dir` holding streams, in the order of [ole_streams()]
#' @noRd
ole_stream_rows <- function(ole){
  rows <- which(ole$dir$type == 2L & ole$dir$parent > 0L)
  key <- vapply(rows, function(i){
    paste(ole_path(ole, i), collapse = "\001")
  }, "")
  rows[order(key, method = "radix")]
}

#' Turn a stream path into the names used to look it up
#'
#' Only the letters A to Z are folded, so matching does not depend on the
#' locale. A single string is split at `/` unless it comes in a list.
#' @noRd
ole_key <- function(stream){
  split <- !is.list(stream)
  if (!split){
    if (length(stream) != 1){
      stop("Give one stream at a time; use `ole_extract()` or `lapply()` ",
           "for several.", call. = FALSE)
    }
    stream <- stream[[1]]
  }
  if (!is.character(stream) || !length(stream) || anyNA(stream)){
    stop("`stream` must be a character vector.", call. = FALSE)
  }
  if (split && length(stream) == 1){
    stream <- strsplit(stream, "/", fixed = TRUE)[[1]]
  }
  ole_fold(stream)
}

#' @noRd
ole_fold <- function(x){
  vapply(enc2utf8(x), function(s){
    b <- charToRaw(s)
    upper <- b >= as.raw(0x41) & b <= as.raw(0x5A)
    b[upper] <- as.raw(as.integer(b[upper]) + 32L)
    s <- rawToChar(b)
    Encoding(s) <- "UTF-8"
    s
  }, "", USE.NAMES = FALSE)
}

#' Find an OLE stream by path
#'
#' Walks down from the root one name at a time.
#' @return The row of the stream in `ole$dir`, or `NA`.
#' @noRd
ole_find <- function(ole, stream){
  names <- ole_key(stream)
  if (!length(names)) return(NA_integer_)
  i <- 1L
  for (k in seq_along(names)){
    type <- if (k < length(names)) 1L else 2L
    i <- match(TRUE, ole$dir$parent == i & ole$dir$type == type &
                 ole$dir$key == names[k])
    if (is.na(i)) break
  }
  i
}

#' Size of an OLE stream
#' @inheritParams ole_read
#' @return The size in bytes, or 0 if the stream does not exist. Storages also
#' have size 0.
#' @examples
#' ole <- ole_open(system.file("extdata", "example.cfb", package = "olereader"))
#' ole_size(ole, "data")
#' @export
ole_size <- function(ole, stream){
  if (is.character(ole)) ole <- ole_open(ole)
  i <- ole_find(ole, stream)
  if (is.na(i)) 0 else ole$dir$size[i]
}

#' Read an OLE stream
#' @param ole An `ole_file` object from [ole_open()], or the path to a compound
#' file, which is opened and parsed again on every call.
#' @param stream Path to the stream: a character vector of names, such as
#' `c("storage", "stream")`, a single string separating them with `/`, or a
#' list holding one such path, such as `ole_streams(ole)[1]`. A string in a
#' list is not split at `/`, so a list also reaches streams whose names
#' contain `/`. Names are matched ignoring the case of the letters A to Z.
#' [ole_extract()] reads a character vector differently: each element is a
#' separate stream.
#' @return A raw vector, or `NULL` if the stream does not exist.
#' @examples
#' ole <- ole_open(system.file("extdata", "example.cfb", package = "olereader"))
#' rawToChar(ole_read(ole, c("notes", "readme")))
#' @export
ole_read <- function(ole, stream){
  if (is.character(ole)) ole <- ole_open(ole)
  i <- ole_find(ole, stream)
  if (is.na(i)) return(NULL)
  con <- file(ole$path, "rb")
  on.exit(close(con), add = TRUE)
  ole_read_entry(ole, i, con)
}

#' Locate the bytes of the stream in row `i` of `ole$dir`
#'
#' Follows the stream's chain and checks it against the size of the file
#' without reading anything.
#' @return A list of file offsets and lengths, one for each sector or mini
#' sector holding the stream.
#' @noRd
ole_plan <- function(ole, i){
  size <- ole$dir$size[i]
  name <- sQuote(paste(ole_path(ole, i), collapse = "/"))
  if (size == 0) return(list(offset = numeric(0), len = numeric(0)))
  if (size < 4096){
    if (inherits(ole$mini_chain, "error")){
      stop(conditionMessage(ole$mini_chain), call. = FALSE)
    }
    unit <- ole$mini_sector_size
    per_sector <- ole$sector_size / unit
    mini <- ole_chain(ole$minifat, ole$dir$start[i], ceiling(size / unit))
    big <- mini %/% per_sector
    if (any(big >= length(ole$mini_chain))){
      stop("The stream ", name, " is truncated.", call. = FALSE)
    }
    offset <- (ole$mini_chain[big + 1] + 1) * ole$sector_size +
      (mini %% per_sector) * unit
  } else {
    unit <- ole$sector_size
    n <- ceiling(size / unit)
    if (n > ole$n_sectors){
      stop("The stream ", name, " is larger than the file.", call. = FALSE)
    }
    offset <- (ole_chain(ole$fat, ole$dir$start[i], n) + 1) * unit
  }
  len <- rep(unit, length(offset))
  len[length(len)] <- size - unit * (length(len) - 1)
  if (any(offset + len > ole$file_size)){
    stop("The stream ", name, " is truncated.", call. = FALSE)
  }
  list(offset = offset, len = len)
}

#' Read the stream in row `i` of `ole$dir` from an open connection
#' @noRd
ole_read_entry <- function(ole, i, con, plan = ole_plan(ole, i)){
  bytes <- ole_read_pieces(con, plan$offset, plan$len)
  if (length(bytes) < ole$dir$size[i]){
    stop("The stream ", sQuote(paste(ole_path(ole, i), collapse = "/")),
         " is truncated.", call. = FALSE)
  }
  bytes
}

#' Extract OLE streams to files
#'
#' Writes each stream to a file under `dir`, with one folder for each storage
#' that contains it, so `c("storage", "stream")` becomes
#' `dir/storage/stream`.
#'
#' Names are changed where they would not work as file names on every
#' platform. Control characters and `<>:"/\|?*` are replaced with `_`,
#' trailing dots and spaces are removed, names left empty (including `.` and
#' `..`) become `_`, and 'Windows' device names such as `CON` or `NUL.txt`
#' get a `_` prefix. The names in a file cannot place a file outside `dir`.
#'
#' `ole_extract()` stops before writing anything if a requested stream does
#' not exist, if two streams would be written to the same file (ignoring
#' case), or if the streams add up to more bytes than the file holds, which
#' means it is truncated or has streams sharing sectors. Any other error stops
#' extraction partway, and the files already written are left in place.
#' @inheritParams ole_read
#' @param dir Folder to write to. It is created if it does not exist.
#' @param streams The streams to extract, or `NULL` (the default) for all of
#' them. Either a character vector with one `/`-separated path per stream,
#' such as `c("data", "notes/readme")`, or a list of paths like the one
#' returned by [ole_streams()]. In a list, each path is a vector of names,
#' such as `list("data", c("notes", "readme"))`, and strings are not split at
#' `/`, so `list("notes/readme")` looks for a stream named `notes/readme`
#' outside any storage.
#' @param overwrite Whether to replace files that already exist. If `FALSE`
#' (the default), extraction stops at the first file that already exists,
#' including one written by an earlier stream in the same call.
#' @return The paths of the files written, invisibly, named by stream.
#' @examples
#' ole <- ole_open(system.file("extdata", "example.cfb", package = "olereader"))
#' dir <- file.path(tempdir(), "example")
#' ole_extract(ole, dir)
#' list.files(dir, recursive = TRUE)
#'
#' ole_extract(ole, dir, streams = "notes/readme", overwrite = TRUE)
#' unlink(dir, recursive = TRUE)
#' @export
ole_extract <- function(ole, dir, streams = NULL, overwrite = FALSE){
  if (is.character(ole)) ole <- ole_open(ole)
  if (is.null(streams)){
    rows <- ole_stream_rows(ole)
  } else {
    rows <- vapply(seq_along(streams), function(k){
      ole_find(ole, streams[k])
    }, 0L)
    missing <- is.na(rows)
    if (any(missing)){
      stop("These streams were not found: ",
           paste(sQuote(vapply(streams[missing], paste, "", collapse = "/")),
                 collapse = ", "), call. = FALSE)
    }
    rows <- unique(rows)
  }
  if (sum(ole$dir$size[rows]) > file.size(ole$path)){
    stop("The streams of ", sQuote(ole$path), " add up to more bytes than ",
         "the file holds, so it is truncated or some streams share sectors.",
         call. = FALSE)
  }
  paths <- lapply(rows, ole_path, ole = ole)
  files <- file.path(dir, vapply(paths, function(p){
    paste(ole_file_name(p), collapse = "/")
  }, ""))
  clash <- files[duplicated(tolower(files))]
  if (length(clash)){
    stop("These streams would be written to the same file as another stream: ",
         paste(sQuote(clash), collapse = ", "), call. = FALSE)
  }
  con <- file(ole$path, "rb")
  on.exit(close(con), add = TRUE)
  withCallingHandlers({
    for (k in seq_along(files)){
      link <- Sys.readlink(files[k])
      if (!overwrite && (file.exists(files[k]) || (!is.na(link) && nzchar(link)))){
        stop(sQuote(files[k]), " already exists; use `overwrite = TRUE` to ",
             "replace it.", call. = FALSE)
      }
      folder <- dirname(files[k])
      if (!dir.exists(folder) && !dir.create(folder, recursive = TRUE,
                                             showWarnings = FALSE)){
        stop("Could not create the folder ", sQuote(folder), ".", call. = FALSE)
      }
      writeBin(ole_read_entry(ole, rows[k], con), files[k])
    }
  }, warning = function(w) stop(conditionMessage(w), call. = FALSE))
  invisible(stats::setNames(files, vapply(paths, paste, "", collapse = "/")))
}

#' Make OLE entry names safe as file names
#' @noRd
ole_file_name <- function(names){
  names <- gsub('[\\x00-\\x1f<>:"/\\\\|?*]', "_", names, perl = TRUE)
  names <- sub("[. ]+$", "", names)
  names[names == ""] <- "_"
  reserved <- grepl("^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\\.|$)", names,
                    ignore.case = TRUE)
  names[reserved] <- paste0("_", names[reserved])
  names
}

#' Follow a sector chain through an allocation table
#' @param table The FAT or miniFAT.
#' @param start First sector (0-based).
#' @param n Number of sectors to follow, or `NULL` to stop at the end of chain.
#' @return The 0-based sector numbers.
#' @noRd
ole_chain <- function(table, start, n = NULL){
  limit <- if (is.null(n)) length(table) else n
  if (limit > length(table)){
    stop("An OLE stream is larger than the file.", call. = FALSE)
  }
  chain <- integer(limit)
  sector <- start
  k <- 0L
  while (k < limit && !is.na(sector) && sector >= 0){
    if (sector >= length(table)){
      stop("An OLE sector chain points outside the file.", call. = FALSE)
    }
    k <- k + 1L
    chain[k] <- sector
    sector <- table[sector + 1L]
  }
  chain <- chain[seq_len(k)]
  if (anyDuplicated(chain)){
    stop("An OLE sector chain loops back on itself.", call. = FALSE)
  }
  if (!is.null(n) && k < n){
    stop("An OLE sector chain ends before the stream does.", call. = FALSE)
  }
  chain
}

#' Read sectors from an OLE file
#' @noRd
ole_read_sectors <- function(con, sectors, sector_size){
  ole_read_pieces(con, (sectors + 1) * sector_size,
                  rep(sector_size, length(sectors)))
}

#' Read pieces of a file, given their offsets and lengths
#'
#' Pieces that follow on from each other are read with a single call.
#' @noRd
ole_read_pieces <- function(con, offset, len){
  if (!length(offset)) return(raw(0))
  n <- length(offset)
  breaks <- c(1L, which(offset[-1] != offset[-n] + len[-n]) + 1L)
  ends <- c(breaks[-1] - 1L, n)
  total <- cumsum(len)
  bytes <- total[ends] - c(0, total[ends[-length(ends)]])
  runs <- lapply(seq_along(breaks), function(k){
    seek(con, offset[breaks[k]])
    readBin(con, "raw", n = bytes[k])
  })
  if (length(runs) == 1) runs[[1]] else unlist(runs, use.names = FALSE)
}

#' @noRd
ole_int32 <- function(bytes){
  readBin(bytes, "integer", n = length(bytes) %/% 4, size = 4,
          endian = "little")
}
