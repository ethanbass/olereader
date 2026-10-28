# Writes a compound file holding two streams: `data` (`data_size` bytes of
# rep_len(0:255), in the FAT with a free sector splitting its chain) and
# `notes/readme` (README_TEXT, in the mini stream). A large enough `data_size`
# needs more than the 109 FAT sectors the header can list, so the rest go in
# DIFAT sectors.
#
# Sector layout: FAT, DIFAT, directory, miniFAT, mini stream, first half of
# data, one free sector, second half of data.
#
# With `layout = "right"` the directory is root, data, notes, readme, and
# `notes` is the right sibling of `data`. With `layout = "left"` it is root,
# notes, readme, data, and `data` is the left sibling of `notes`, so entry IDs
# are not in name order.

README_TEXT <- paste("This is the readme stream of the olereader example",
                     "file. It is short enough to be in the mini stream.")

cfb_i32 <- function(x) writeBin(as.integer(x), raw(), size = 4, endian = "little")
cfb_u16 <- function(x) writeBin(as.integer(x), raw(), size = 2, endian = "little")
cfb_pad <- function(x, n) c(x, raw(n - length(x)))

cfb_entry <- function(name, type, left = -1, right = -1, child = -1,
                      start = 0, size = 0, size_high = 0,
                      utf16 = iconv(name, "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]]){
  c(cfb_pad(utf16, 64), cfb_u16(length(utf16) + 2), as.raw(c(type, 1)),
    cfb_i32(c(left, right, child)), raw(16 + 4 + 16), cfb_i32(start),
    cfb_i32(size), cfb_i32(size_high))
}

make_cfb <- function(path, version = 3, data_size = 5000,
                     layout = c("right", "left")){
  layout <- match.arg(layout)
  i32 <- cfb_i32; u16 <- cfb_u16; pad <- cfb_pad; entry <- cfb_entry
  FREE <- -1L; END <- -2L; FATSECT <- -3L; DIFSECT <- -4L

  sector_size <- if (version == 4) 4096 else 512
  per_sector <- sector_size / 4
  readme <- charToRaw(README_TEXT)
  data <- as.raw(rep_len(0:255, data_size))
  n_data <- ceiling(data_size / sector_size)
  n_first <- ceiling(n_data / 2)

  n_fat <- 1
  repeat {
    n_difat <- max(0, ceiling((n_fat - 109) / (per_sector - 1)))
    n_total <- n_fat + n_difat + 3 + n_data + 1
    if (n_fat * per_sector >= n_total) break
    n_fat <- n_fat + 1
  }
  fat_sectors <- seq_len(n_fat) - 1
  difat_sectors <- n_fat + seq_len(n_difat) - 1
  s_dir <- n_fat + n_difat
  s_data <- s_dir + 3 + c(seq_len(n_first) - 1, n_first + seq_len(n_data - n_first))

  fat <- rep(FREE, n_fat * per_sector)
  fat[fat_sectors + 1] <- FATSECT
  fat[difat_sectors + 1] <- DIFSECT
  fat[s_dir + 1:3] <- END
  fat[s_data + 1] <- c(s_data[-1], END)

  difat <- c(fat_sectors, rep(FREE, 109 + n_difat * (per_sector - 1) - n_fat))
  difat_blocks <- lapply(seq_len(n_difat), function(k){
    entries <- difat[109 + (k - 1) * (per_sector - 1) + seq_len(per_sector - 1)]
    i32(c(entries, if (k < n_difat) difat_sectors[k + 1] else END))
  })

  header <- pad(c(
    as.raw(c(0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1)), raw(16),
    u16(0x3E), u16(version), u16(0xFFFE), u16(log2(sector_size)), u16(6),
    raw(6), i32(if (version == 4) 1 else 0), i32(n_fat), i32(s_dir), i32(0),
    i32(4096), i32(s_dir + 1), i32(1),
    i32(if (n_difat) difat_sectors[1] else END), i32(n_difat),
    i32(difat[1:109])), sector_size)

  root <- entry("Root Entry", 5, child = 1, start = s_dir + 2, size = 128)
  directory <- if (layout == "right"){
    c(root,
      entry("data", 2, right = 2, start = s_data[1], size = data_size),
      entry("notes", 1, child = 3),
      entry("readme", 2, start = 0, size = length(readme)))
  } else {
    c(root,
      entry("notes", 1, left = 3, child = 2),
      entry("readme", 2, start = 0, size = length(readme)),
      entry("data", 2, start = s_data[1], size = data_size))
  }

  minifat <- c(1L, END, rep(FREE, per_sector - 2))
  first <- seq_len(min(n_first * sector_size, data_size))
  writeBin(c(header, i32(fat), unlist(difat_blocks),
             pad(directory, sector_size), i32(minifat),
             pad(readme, sector_size),
             pad(data[first], n_first * sector_size), raw(sector_size),
             pad(data[-first], (n_data - n_first) * sector_size)), path)
  invisible(path)
}

# Copies `path` to a temporary file with `bytes` written at the 0-based
# `offset`, or cut to its first `truncate` bytes.
patch_cfb <- function(path, offset = NULL, bytes = NULL, truncate = NULL,
                      env = parent.frame()){
  b <- readBin(path, "raw", file.size(path))
  if (!is.null(offset)) b[offset + seq_along(bytes)] <- bytes
  if (!is.null(truncate)) b <- b[seq_len(truncate)]
  out <- withr::local_tempfile(fileext = ".cfb", .local_envir = env)
  writeBin(b, out)
  out
}
