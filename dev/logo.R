# "El olé" (Vienna: H. F. Müller's Witwe, 185-), NYPL Jerome Robbins Dance Division, public domain
src <- "https://upload.wikimedia.org/wikipedia/commons/9/98/El_ol%C3%A9_%28NYPL_b12149002-5247020%29.jpg"
src_file <- tempfile(fileext = ".jpg")
download.file(src, src_file, mode = "wb", headers = c("User-Agent" = "olereader-logo-script"))
ink_color <- "#5A1414"

mask <- magick::image_read(src_file) |>
  magick::image_crop("1150x1000+1690+1360") |>
  magick::image_convert(colorspace = "gray") |>
  magick::image_level(black_point = 30, white_point = 74) |>
  magick::image_negate()
vignette <- magick::image_blank(1150, 1000, pseudo_image = "radial-gradient:white-black") |>
  magick::image_level(black_point = 0, white_point = 55)
fade <- magick::image_blank(1150, 1000, pseudo_image = "gradient:white-black") |>
  magick::image_level(black_point = 0, white_point = 30)
mask <- mask |>
  magick::image_composite(vignette, operator = "multiply") |>
  magick::image_composite(fade, operator = "multiply")

ink <- magick::image_blank(1150, 1000, ink_color) |>
  magick::image_composite(mask, operator = "CopyOpacity")
ink_file <- tempfile(fileext = ".png")
magick::image_write(ink, ink_file)

sysfonts::font_add_google("Rye", "rye")
showtext::showtext_auto()

dir.create("man/figures", showWarnings = FALSE, recursive = TRUE)
hexSticker::sticker(
  ink_file,
  s_x = 1, s_y = 0.82, s_width = 0.72,
  package = "olereader", p_family = "rye", p_size = 15, p_y = 1.56,
  p_color = ink_color, h_fill = "#F3E9D2", h_color = "#9E1B1B", h_size = 1.6,
  filename = "man/figures/logo.png", dpi = 300
)
