## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(echo = TRUE, message = FALSE, warning = FALSE,
                      fig.width = 10, fig.height = 6, dpi = 150, fig.align = "center")
# Run every chunk from the project folder (one level up from /analysis).
# If you run the plain script analysis/shade_analysis.R instead, open the .Rproj first so the
# working directory is the project folder.
knitr::opts_knit$set(root.dir = normalizePath(".."))


## ----packages-----------------------------------------------------------------
# Packages used (all free on CRAN):
#   install.packages(c("dplyr", "tidyr", "readr", "stringr", "forcats",
#                      "ggplot2", "farver", "scales", "knitr", "rmarkdown"))
library(dplyr)    # data cleaning
library(tidyr)    # reshaping tables
library(readr)    # reading and writing CSV files
library(stringr)  # text cleaning
library(forcats)  # ordering categories in charts
library(ggplot2)  # charts
library(farver)   # color conversion (used to double-check my own formula)
library(scales)   # percent labels

dir.create("data/clean", showWarnings = FALSE, recursive = TRUE)
dir.create("output/charts", showWarnings = FALSE, recursive = TRUE)
dir.create("output/tables", showWarnings = FALSE, recursive = TRUE)


## ----load---------------------------------------------------------------------
shades_raw <- read_csv("data/raw/shades_raw.csv", col_types = cols(.default = col_character()))
products   <- read_csv("data/raw/products.csv",   col_types = cols(.default = col_character()))

products %>%
  count(brand, included, name = "products") %>%
  pivot_wider(names_from = included, values_from = products, values_fill = 0,
              names_prefix = "included_") %>%
  knitr::kable(caption = "Products collected per brand")


## ----excluded-----------------------------------------------------------------
products %>%
  filter(included == "no") %>%
  select(brand, product, shades_collected, exclusion_reason) %>%
  knitr::kable()


## ----dictionary, echo = FALSE-------------------------------------------------
tibble::tribble(
  ~column,          ~meaning,
  "brand",          "Brand name",
  "product",        "Product name as shown on the brand's site",
  "product_type",   "Foundation, Skin tint, CC cream or Glow filter (from the product name)",
  "shade",          "Shade name exactly as the site shows it",
  "hex",            "Swatch color as a HEX code, for example #BA8656",
  "R, G, B",        "Red, green and blue parts of the color (0 to 255)",
  "L_star",         "Lightness from 0 (black) to 100 (white): the main measure",
  "a_star, b_star", "The other two CIELAB color numbers (redness and yellowness), kept for future undertone work",
  "depth_band",     "Light, Medium, Tan or Deep, from L* (see Section 7)",
  "rank_in_product","1 = the product's lightest shade",
  "gap_to_next",    "Lightness difference to the next deeper shade in the same product",
  "product_half",   "Whether the shade is in the lighter or deeper half of its own product's range",
  "swatch_type",    "Color code or image",
  "in_stock",       "TRUE/FALSE where the site showed stock; blank where it did not",
  "source_url",     "Product page the swatch came from",
  "date_collected", "2026-09-28"
) %>% knitr::kable()


## ----clean--------------------------------------------------------------------
cleaning_log <- tibble(step = "All swatches collected", rows = nrow(shades_raw))

# 1. Keep only the products that are part of the study
shades <- shades_raw %>%
  semi_join(filter(products, included == "yes"), by = c("brand", "product"))
cleaning_log <- add_row(cleaning_log, step = "Dropped 3 clearance products", rows = nrow(shades))

# 2. Tidy the text: trim spaces and use one kind of dash
shades <- shades %>%
  mutate(across(c(brand, product, shade), ~ str_squish(str_replace_all(.x, "[\\u2013\\u2014]", "-"))),
         hex      = str_to_upper(str_trim(hex)),
         in_stock = as.logical(in_stock))

# 3. Checks (each should be zero)
checks <- tibble(
  check = c("Missing brand, product, shade or HEX",
            "HEX codes that are not a valid #RRGGBB code",
            "Duplicate rows (same brand + product + shade)"),
  count = c(sum(is.na(shades$brand) | is.na(shades$product) | is.na(shades$shade) | is.na(shades$hex)),
            sum(!str_detect(shades$hex, "^#[0-9A-F]{6}$")),
            sum(duplicated(select(shades, brand, product, shade))))
)
knitr::kable(checks, caption = "Data checks")
stopifnot(all(checks$count == 0))

# 4. Label each product's type from its name (my rule, applied the same way to every brand)
shades <- shades %>%
  mutate(product_type = case_when(
    str_detect(product, "CC Cream")              ~ "CC cream",
    str_detect(product, "Filter")                ~ "Glow filter",
    str_detect(product, "Foundation|Makeup")     ~ "Foundation",
    str_detect(product, "Tint|Tinted|Balm")      ~ "Skin tint",
    TRUE                                         ~ "Foundation"))

cleaning_log <- add_row(cleaning_log, step = "Final clean dataset", rows = nrow(shades))
knitr::kable(cleaning_log, caption = "Rows at each cleaning step")


## ----repeated-colors----------------------------------------------------------
repeated_colors <- shades %>%
  group_by(brand, product, hex) %>%
  filter(n() > 1) %>%
  summarise(shades = paste(shade, collapse = " / "), .groups = "drop")
knitr::kable(repeated_colors, caption = "Shades that share one swatch color within a product")


## ----lightness----------------------------------------------------------------
# Step 1: the sRGB curve, for a 0-255 value
srgb_to_linear <- function(v) {
  v <- v / 255
  ifelse(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055)^2.4)
}

# Steps 2 and 3: brightness (Y), then lightness (L*)
lightness_Lstar <- function(R, G, B) {
  Y <- 0.2126 * srgb_to_linear(R) + 0.7152 * srgb_to_linear(G) + 0.0722 * srgb_to_linear(B)
  f <- ifelse(Y > (6/29)^3, Y^(1/3), Y / (3 * (6/29)^2) + 4/29)
  116 * f - 16
}

rgb <- decode_colour(shades$hex)   # HEX -> a table of R, G, B
shades <- shades %>%
  mutate(R = rgb[, "r"], G = rgb[, "g"], B = rgb[, "b"],
         L_star = round(lightness_Lstar(R, G, B), 2))

# The other two CIELAB numbers (a* = red vs green, b* = yellow vs blue), from farver
lab <- convert_colour(rgb, from = "rgb", to = "lab")
shades <- shades %>% mutate(a_star = round(lab[, "a"], 2), b_star = round(lab[, "b"], 2))

# Checks: white should be 100, black 0, and my formula should match farver's full conversion
tibble(color = c("#FFFFFF (white)", "#000000 (black)", "#777777 (mid gray)"),
       L_star = round(lightness_Lstar(c(255, 0, 119), c(255, 0, 119), c(255, 0, 119)), 2)) %>%
  knitr::kable(caption = "Sanity check")
cat("Largest difference between my L* and farver's L*:",
    signif(max(abs(shades$L_star - lab[, "l"])), 2), "\n")


## ----example-shade------------------------------------------------------------
shades %>%
  filter(product == "Soft Glam Satin Foundation", shade == "40 Tan Warm") %>%
  select(shade, hex, R, G, B, L_star) %>%
  knitr::kable()


## ----order-check--------------------------------------------------------------
order_flags <- shades %>%
  mutate(shade_number = suppressWarnings(as.numeric(str_extract(shade, "^\\.?\\d+(\\.\\d+)?")))) %>%
  group_by(brand, product) %>%
  # only products where every shade name starts with its own number (no two shades share a number)
  filter(all(!is.na(shade_number)), n_distinct(shade_number) == n()) %>%
  arrange(shade_number, .by_group = TRUE) %>%
  mutate(next_number = lead(shade_number), next_shade = lead(shade),
         lighter_by  = lead(L_star) - L_star) %>%
  ungroup() %>%
  filter(!is.na(next_number), next_number > shade_number, lighter_by > 5)

n_numbered_products <- shades %>%
  mutate(shade_number = suppressWarnings(as.numeric(str_extract(shade, "^\\.?\\d+(\\.\\d+)?")))) %>%
  group_by(brand, product) %>% filter(all(!is.na(shade_number)), n_distinct(shade_number) == n()) %>% n_groups()

order_flags %>%
  count(brand, swatch_type, name = "flags") %>%
  knitr::kable(caption = paste0("Out-of-order swatches (", nrow(order_flags), " flags across ",
                                n_numbered_products, " numbered product lines)"))


## ----bands--------------------------------------------------------------------
band_levels <- c("Light", "Medium", "Tan", "Deep")
shades <- shades %>%
  mutate(depth_band = cut(L_star, breaks = c(-Inf, 35, 55, 75, Inf),
                          labels = rev(band_levels), right = FALSE),
         depth_band = factor(depth_band, levels = band_levels))

# The 10 Monk Skin Tone Scale colors (Google, CC BY 4.0), for reference
monk <- tibble(tone = 1:10,
               hex  = c("#F6EDE4", "#F3E7DB", "#F7EAD0", "#EADABA", "#D7BD96",
                        "#A07E56", "#825C43", "#604134", "#3A312A", "#292420"))
monk_rgb <- decode_colour(monk$hex)
monk <- monk %>% mutate(L_star = round(lightness_Lstar(monk_rgb[, "r"], monk_rgb[, "g"], monk_rgb[, "b"]), 1),
                        band = cut(L_star, c(-Inf, 35, 55, 75, Inf), labels = rev(band_levels), right = FALSE))
tibble(band = band_levels,
       `L* range` = c("75 and up", "55 to 75", "35 to 55", "below 35"),
       `Monk tones in this band` = sapply(band_levels, function(b) paste(monk$tone[monk$band == b], collapse = ", "))) %>%
  knitr::kable(caption = "The four depth bands")


## ----within-product-----------------------------------------------------------
shades <- shades %>%
  group_by(brand, product) %>%
  arrange(desc(L_star), .by_group = TRUE) %>%
  mutate(rank_in_product = row_number(),
         product_mid     = (max(L_star) + min(L_star)) / 2,
         product_half    = if_else(L_star >= product_mid, "lighter half", "deeper half"),
         gap_to_next     = round(L_star - lead(L_star), 2),               # to the next deeper shade
         gap_half        = if_else((L_star + lead(L_star)) / 2 >= product_mid,
                                   "lighter half", "deeper half")) %>%
  ungroup()

brand_order_default <- c("e.l.f.", "Maybelline", "Huda Beauty", "Charlotte Tilbury", "Hourglass",
                         "L'Oreal Paris", "Laura Mercier", "NYX Professional Makeup",
                         "Rare Beauty", "Makeup by Mario")

shades_clean <- shades %>%
  mutate(brand = factor(brand, levels = brand_order_default)) %>%
  arrange(brand, product, rank_in_product) %>%
  select(brand, product, product_type, shade, hex, R, G, B, L_star, a_star, b_star,
         depth_band, rank_in_product, gap_to_next, product_half, swatch_type, in_stock,
         source_url, date_collected)
write_csv(shades_clean, "data/clean/shades_clean.csv", na = "")
cat("Saved", nrow(shades_clean), "shades to data/clean/shades_clean.csv\n")


## ----theme, include = FALSE---------------------------------------------------
# Chart style: quiet background and grid, so the shade colors are the loudest thing
chart_font <- "sans"  # the computer's default sans-serif font
ink <- "#0b0b0b"; ink2 <- "#52514e"; muted <- "#898781"; grid <- "#e1e0d9"; surface <- "#fcfcfb"
band_colors <- c(Light = "#d4a77f", Medium = "#ae7648", Tan = "#80502c", Deep = "#4f2f19")

theme_shade <- function(base_size = 12) {
  theme_minimal(base_size = base_size, base_family = chart_font) +
    theme(plot.background  = element_rect(fill = surface, colour = NA),
          panel.background = element_rect(fill = surface, colour = NA),
          panel.grid.major = element_line(colour = grid, linewidth = 0.3),
          panel.grid.minor = element_blank(),
          axis.text   = element_text(colour = ink2),
          axis.title  = element_text(colour = ink2, size = rel(0.85)),
          plot.title  = element_text(colour = ink, face = "bold", size = rel(1.25)),
          plot.subtitle = element_text(colour = ink2, size = rel(0.95), margin = margin(b = 10)),
          plot.caption  = element_text(colour = muted, size = rel(0.7), hjust = 0),
          plot.title.position = "plot", plot.caption.position = "plot",
          legend.position = "top", legend.justification = "left",
          legend.title = element_blank(), legend.text = element_text(colour = ink2),
          strip.text = element_text(colour = ink, face = "bold", hjust = 0),
          plot.margin = margin(14, 18, 10, 14))
}
x_lab <- "Lightness (L*): lighter on the left, deeper on the right"
source_note <- "Source: official US brand websites, collected Sept 28, 2026. Lightness = CIELAB L*."
save_chart <- function(plot, file, width = 10, height = 6) {
  ggsave(file.path("output/charts", file), plot, width = width, height = height, dpi = 200, bg = surface)
}


## ----hist, fig.height = 5-----------------------------------------------------
p_hist <- ggplot(shades, aes(x = L_star, fill = depth_band)) +
  geom_histogram(breaks = seq(5, 100, by = 2.5), colour = surface, linewidth = 0.4) +
  geom_vline(xintercept = c(35, 55, 75), colour = muted, linewidth = 0.4) +
  scale_x_reverse(breaks = seq(10, 100, 10), expand = expansion(mult = 0.01)) +
  scale_fill_manual(values = band_colors, drop = FALSE) +
  labs(title = "Most shades are bunched in the light-to-medium range",
       subtitle = "Number of foundation shades at each lightness level, all 10 brands together",
       x = x_lab, y = "Number of shades", caption = source_note) +
  theme_shade()
p_hist
save_chart(p_hist, "01_lightness_histogram.png", height = 5)


## ----boxplot, fig.height = 6.5------------------------------------------------
brand_by_median <- shades %>% group_by(brand) %>% summarise(med = median(L_star)) %>% arrange(med)

set.seed(2026)  # makes the random jitter the same every time
p_box <- ggplot(shades, aes(x = L_star, y = factor(brand, levels = rev(brand_by_median$brand)))) +
  geom_jitter(aes(colour = hex), height = 0.22, width = 0, size = 1.6, alpha = 0.9) +
  geom_boxplot(fill = NA, colour = ink2, outlier.shape = NA, width = 0.55, linewidth = 0.35) +
  scale_colour_identity() +
  scale_x_reverse(breaks = seq(10, 100, 10)) +
  labs(title = "Every shade, drawn in its own color",
       subtitle = "Dots are single shades. Boxes show the middle 50% of each brand's shades; the line is the median.",
       x = x_lab, y = NULL, caption = source_note) +
  theme_shade()
p_box
save_chart(p_box, "02_brand_boxplots.png", height = 6.5)


## ----stats-brand--------------------------------------------------------------
brand_stats <- shades %>%
  group_by(brand) %>%
  summarise(products = n_distinct(product),
            shades   = n(),
            lightest = max(L_star), deepest = min(L_star),
            range    = lightest - deepest,
            mean     = mean(L_star), median = median(L_star), sd = sd(L_star),
            q1 = quantile(L_star, 0.25), q3 = quantile(L_star, 0.75),
            pct_deep       = mean(depth_band == "Deep"),
            pct_deeper_half = mean(depth_band %in% c("Tan", "Deep")),
            .groups = "drop") %>%
  arrange(desc(pct_deeper_half))

brand_stats %>%
  mutate(across(lightest:q3, ~ round(.x, 1)),
         across(starts_with("pct"), ~ percent(.x, accuracy = 0.1))) %>%
  knitr::kable(caption = "Lightness (L*) by brand. pct_deeper_half = Tan + Deep bands (L* below 55).")
write_csv(brand_stats, "output/tables/brand_summary.csv")


## ----stats-overall------------------------------------------------------------
overall <- shades %>% summarise(shades = n(), products = n_distinct(paste(brand, product)),
                                min = min(L_star), q1 = quantile(L_star, .25), median = median(L_star),
                                mean = mean(L_star), q3 = quantile(L_star, .75), max = max(L_star), sd = sd(L_star))
knitr::kable(mutate(overall, across(min:sd, ~ round(.x, 1))), caption = "All shades together")

band_share <- shades %>% count(depth_band) %>% mutate(share = n / sum(n))
knitr::kable(mutate(band_share, share = percent(share, accuracy = 0.1)), caption = "Shades in each depth band")


## ----stats-product------------------------------------------------------------
gaps <- shades %>% filter(!is.na(gap_to_next))

product_stats <- shades %>%
  group_by(brand, product, product_type) %>%
  summarise(shades = n(), lightest = max(L_star), deepest = min(L_star),
            pct_in_deeper_half_of_own_range = mean(product_half == "deeper half"),
            .groups = "drop") %>%
  left_join(gaps %>%
              group_by(brand, product) %>%
              summarise(median_gap_lighter_half = median(gap_to_next[gap_half == "lighter half"]),
                        median_gap_deeper_half  = median(gap_to_next[gap_half == "deeper half"]),
                        gaps_lighter = sum(gap_half == "lighter half"),
                        gaps_deeper  = sum(gap_half == "deeper half"),
                        .groups = "drop"),
            by = c("brand", "product"))

product_stats %>%
  arrange(pct_in_deeper_half_of_own_range) %>%
  mutate(across(c(lightest, deepest, starts_with("median")), ~ round(.x, 1)),
         pct_in_deeper_half_of_own_range = percent(pct_in_deeper_half_of_own_range, accuracy = 1)) %>%
  select(-gaps_lighter, -gaps_deeper) %>%
  knitr::kable(caption = "Every product. If shades were spread evenly, 50% would sit in the deeper half of the product's own range.")
write_csv(product_stats, "output/tables/product_summary.csv")


## ----test---------------------------------------------------------------------
paired <- product_stats %>% filter(gaps_lighter >= 2, gaps_deeper >= 2)

wtest <- wilcox.test(paired$median_gap_deeper_half, paired$median_gap_lighter_half,
                     paired = TRUE, exact = FALSE)
n_products_tested <- nrow(paired)
n_deeper_wider    <- sum(paired$median_gap_deeper_half > paired$median_gap_lighter_half)
typical_light_gap <- median(paired$median_gap_lighter_half)
typical_deep_gap  <- median(paired$median_gap_deeper_half)
gap_ratio         <- typical_deep_gap / typical_light_gap

tibble(`Products tested` = n_products_tested,
       `Deeper shades spaced wider` = n_deeper_wider,
       `Typical gap, lighter half (L*)` = round(typical_light_gap, 2),
       `Typical gap, deeper half (L*)`  = round(typical_deep_gap, 2),
       `p-value` = signif(wtest$p.value, 2)) %>%
  knitr::kable()


## ----chart-strip, fig.height = 7----------------------------------------------
brand_rank <- brand_stats %>% arrange(pct_deeper_half) %>% pull(brand)
strip_data <- shades %>% mutate(brand = factor(brand, levels = brand_rank))
label_data <- brand_stats %>%
  mutate(brand = factor(brand, levels = brand_rank),
         label = paste0(percent(pct_deeper_half, accuracy = 1), " in the deeper half"))

p_strip <- ggplot(strip_data) +
  annotate("rect", xmin = 55, xmax = 5, ymin = -Inf, ymax = Inf, fill = "#f1efe9") +
  geom_vline(xintercept = c(35, 55, 75), colour = grid, linewidth = 0.4) +
  geom_segment(aes(x = L_star, xend = L_star,
                   y = as.numeric(brand) - 0.36, yend = as.numeric(brand) + 0.36, colour = hex),
               linewidth = 0.9) +
  geom_text(data = label_data, aes(x = 3, y = as.numeric(brand), label = label),
            hjust = 0, size = 3.3, colour = ink2, family = chart_font) +
  annotate("text", x = c(85, 65, 45, 25), y = length(brand_rank) + 0.75,
           label = band_levels, colour = muted, size = 3.3, family = chart_font) +
  annotate("text", x = 30, y = 0.2, label = "deeper half of the scale (L* below 55)",
           colour = muted, size = 3, family = chart_font) +
  scale_colour_identity() +
  scale_x_reverse(limits = c(100, -38), breaks = seq(10, 100, 10)) +
  scale_y_continuous(breaks = seq_along(brand_rank), labels = brand_rank,
                     limits = c(0, length(brand_rank) + 1), expand = c(0, 0)) +
  labs(title = "The deep end of the shade range is sparse for every brand",
       subtitle = "Each line is one foundation shade, drawn in its swatch color. Solid blocks mean shades are packed close together.",
       x = x_lab, y = NULL, caption = source_note) +
  theme_shade() +
  theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_blank())
p_strip
save_chart(p_strip, "03_shade_strip_by_brand.png", width = 12, height = 7)


## ----chart-bands, fig.height = 6----------------------------------------------
band_by_brand <- shades %>%
  count(brand, depth_band) %>%
  group_by(brand) %>% mutate(share = n / sum(n)) %>% ungroup() %>%
  mutate(brand = factor(brand, levels = brand_rank))
number_cols <- brand_stats %>%
  mutate(brand = factor(brand, levels = brand_rank),
         deep = percent(pct_deep, accuracy = 1), deeper = percent(pct_deeper_half, accuracy = 1))
top_y <- length(brand_rank) + 0.85

p_bands <- ggplot(band_by_brand, aes(x = share, y = brand, fill = depth_band)) +
  geom_col(width = 0.62, colour = surface, linewidth = 0.8, position = position_stack(reverse = TRUE)) +
  geom_vline(xintercept = 0.5, colour = ink2, linewidth = 0.4) +
  annotate("text", x = 0.508, y = top_y, label = "even split", hjust = 0,
           colour = ink2, size = 3.2, family = chart_font) +
  geom_text(data = number_cols, aes(x = 1.04, y = brand, label = deep), inherit.aes = FALSE,
            hjust = 0, size = 3.4, colour = ink, family = chart_font) +
  geom_text(data = number_cols, aes(x = 1.13, y = brand, label = deeper), inherit.aes = FALSE,
            hjust = 0, size = 3.4, colour = ink, family = chart_font) +
  annotate("text", x = c(1.04, 1.13), y = top_y, label = c("Deep", "Tan + Deep"), hjust = 0,
           colour = muted, size = 3, family = chart_font) +
  scale_fill_manual(values = band_colors) +
  scale_x_continuous(labels = percent, breaks = seq(0, 1, 0.25), expand = c(0, 0)) +
  scale_y_discrete(expand = expansion(add = c(0.6, 1.2))) +
  coord_cartesian(xlim = c(0, 1.25), clip = "off") +
  labs(title = "No brand puts half of its shades in the deeper half of the scale",
       subtitle = "Share of each brand's shades in each lightness band. If shades were spread evenly, Tan + Deep would start at the line.",
       x = "Share of the brand's shades", y = NULL, caption = source_note) +
  theme_shade() +
  theme(panel.grid.major.y = element_blank())
p_bands
save_chart(p_bands, "04_depth_bands_by_brand.png", height = 6)


## ----chart-spacing, fig.height = 6--------------------------------------------
spacing_by_brand <- gaps %>%
  group_by(brand, gap_half) %>%
  summarise(median_gap = median(gap_to_next), .groups = "drop") %>%
  pivot_wider(names_from = gap_half, values_from = median_gap) %>%
  arrange(`deeper half`) %>%
  mutate(brand = factor(brand, levels = brand))
write_csv(spacing_by_brand, "output/tables/spacing_by_brand.csv")

spacing_long <- spacing_by_brand %>%
  pivot_longer(-brand, names_to = "half", values_to = "gap") %>%
  mutate(half = factor(half, levels = c("lighter half", "deeper half"),
                       labels = c("Lighter half of each product's range", "Deeper half")))

p_spacing <- ggplot(spacing_by_brand, aes(y = brand)) +
  geom_segment(aes(x = `lighter half`, xend = `deeper half`, yend = brand),
               colour = grid, linewidth = 2) +
  geom_point(data = spacing_long, aes(x = gap, fill = half), shape = 21, size = 4,
             colour = surface, stroke = 1.2) +
  scale_fill_manual(values = c(band_colors[["Light"]], band_colors[["Deep"]])) +
  scale_x_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.08))) +
  labs(title = "Deep shades are spaced further apart",
       subtitle = paste0("Typical lightness gap between neighboring shades. Across products, deeper shades were further apart in ",
                         n_deeper_wider, " of ", n_products_tested, " (Wilcoxon signed-rank test, p < 0.001)."),
       x = "Median gap between neighboring shades (L* points)", y = NULL, caption = source_note) +
  theme_shade() +
  theme(panel.grid.major.y = element_blank())
p_spacing
save_chart(p_spacing, "05_spacing_light_vs_deep.png", height = 6)


## ----chart-size, fig.height = 6-----------------------------------------------
size_vs_balance <- shades %>%
  group_by(brand, product) %>%
  summarise(shades = n(), pct_deeper = mean(depth_band %in% c("Tan", "Deep")), .groups = "drop") %>%
  mutate(big_range = shades >= 40)
spearman <- cor.test(size_vs_balance$shades, size_vs_balance$pct_deeper, method = "spearman", exact = FALSE)
big <- size_vs_balance %>% filter(big_range)

p_size <- ggplot(size_vs_balance, aes(x = shades, y = pct_deeper)) +
  geom_hline(yintercept = 0.5, colour = ink2, linewidth = 0.4) +
  annotate("text", x = 5, y = 0.515, label = "even split", hjust = 0, vjust = 0,
           colour = ink2, size = 3.2, family = chart_font) +
  geom_point(aes(fill = big_range), size = 3.4, shape = 21, colour = surface, stroke = 0.8) +
  annotate("text", x = 43.5, y = min(big$pct_deeper) - 0.045, hjust = 0.5, size = 3.1, colour = ink2,
           family = chart_font, label = paste0("The ", nrow(big), " biggest ranges (40+ shades)")) +
  scale_fill_manual(values = c(`TRUE` = band_colors[["Tan"]], `FALSE` = "#c3c2b7"), guide = "none") +
  scale_y_continuous(labels = percent, limits = c(0, 0.62)) +
  scale_x_continuous(limits = c(4, 52), breaks = seq(10, 50, 10)) +
  labs(title = "Bigger shade ranges are not more balanced",
       subtitle = paste0("Each dot is one product. The ", nrow(big), " biggest ranges put only ",
                         percent(min(big$pct_deeper), accuracy = 1), " to ", percent(max(big$pct_deeper), accuracy = 1),
                         " of their shades in the deeper half.\nSpearman correlation between shade count and deeper-half share: ",
                         round(spearman$estimate, 2), " (p = ", round(spearman$p.value, 2), ", not significant)."),
       x = "Number of shades in the product", y = "Share of shades in the deeper half (L* below 55)",
       caption = source_note) +
  theme_shade()
p_size
save_chart(p_size, "06_shade_count_vs_balance.png", height = 6)


## ----chart-wall, fig.height = 16----------------------------------------------
wall <- shades %>%
  mutate(product_label = paste0(product, "  (", brand, ")"),
         brand = factor(brand, levels = brand_rank))
wall_order <- wall %>% group_by(brand, product_label) %>% summarise(deep = min(L_star), .groups = "drop") %>%
  arrange(brand, desc(deep)) %>% pull(product_label)

p_wall <- ggplot(wall, aes(y = factor(product_label, levels = rev(wall_order)))) +
  geom_vline(xintercept = c(35, 55, 75), colour = "#c3c2b7", linewidth = 0.4) +
  annotate("text", x = c(85, 65, 45, 25), y = length(wall_order) + 1, label = band_levels,
           colour = muted, size = 3.2, family = chart_font) +
  geom_point(aes(x = L_star, fill = hex), shape = 21, size = 2.6, colour = surface, stroke = 0.35) +
  scale_fill_identity() +
  scale_x_reverse(breaks = seq(10, 100, 10)) +
  scale_y_discrete(expand = expansion(add = c(0.8, 1.6))) +
  labs(title = "All 46 products, every shade",
       subtitle = "Each dot is one shade in its swatch color. Vertical lines mark the Light / Medium / Tan / Deep bands.",
       x = x_lab, y = NULL, caption = source_note) +
  theme_shade(base_size = 10.5) +
  theme(panel.grid.major.y = element_line(colour = "#f1efe9", linewidth = 0.3),
        panel.grid.major.x = element_blank())
p_wall
save_chart(p_wall, "07_shade_wall_all_products.png", width = 11, height = 16)


## ----headline-numbers, include = FALSE----------------------------------------
pct <- function(x) percent(x, accuracy = 1)
share_deep        <- band_share$share[band_share$depth_band == "Deep"]
share_tan         <- band_share$share[band_share$depth_band == "Tan"]
share_deeper_half <- share_deep + share_tan
top_brand   <- brand_stats %>% slice_max(pct_deeper_half, n = 1)
low_brand   <- brand_stats %>% slice_min(pct_deeper_half, n = 1)
n_products  <- nrow(product_stats)
n_unbalanced <- sum(product_stats$pct_in_deeper_half_of_own_range < 0.5)
median_own_half <- median(product_stats$pct_in_deeper_half_of_own_range)


## ----save-headline-numbers, include = FALSE-----------------------------------
# Save the key numbers so the web page and resume use exactly the same values as this report
headline <- tibble::tribble(
  ~key, ~value,
  "n_shades", nrow(shades),
  "n_products", n_products,
  "n_brands", n_distinct(shades$brand),
  "share_deep", round(share_deep, 4),
  "share_tan", round(share_tan, 4),
  "share_deeper_half", round(share_deeper_half, 4),
  "n_unbalanced_products", n_unbalanced,
  "median_share_in_deeper_half_of_own_range", round(median_own_half, 4),
  "typical_gap_lighter_half", round(typical_light_gap, 3),
  "typical_gap_deeper_half", round(typical_deep_gap, 3),
  "gap_ratio", round(gap_ratio, 3),
  "n_products_tested", n_products_tested,
  "n_deeper_wider", n_deeper_wider,
  "wilcoxon_p", signif(wtest$p.value, 3),
  "spearman_rho", round(unname(spearman$estimate), 3),
  "spearman_p", round(spearman$p.value, 3),
  "n_big_ranges", nrow(big),
  "big_ranges_min_share", round(min(big$pct_deeper), 4),
  "big_ranges_max_share", round(max(big$pct_deeper), 4),
  "n_repeated_color_pairs", nrow(repeated_colors),
  "n_order_flags", nrow(order_flags)
) %>% mutate(value = as.character(value))
write_csv(headline, "output/tables/headline_numbers.csv")


## ----sensitivity--------------------------------------------------------------
# Sensitivity check: add back the three clearance products (only the shades their pages still showed)
all_rows <- shades_raw %>%
  mutate(L = lightness_Lstar(decode_colour(hex)[, "r"], decode_colour(hex)[, "g"], decode_colour(hex)[, "b"]))
tibble(dataset = c("Main analysis", "With the 3 clearance products added back"),
       `number of shades` = c(nrow(shades), nrow(all_rows)),
       `share below L* 55` = percent(c(mean(shades$L_star < 55), mean(all_rows$L < 55)), accuracy = 0.1),
       `share below L* 35` = percent(c(mean(shades$L_star < 35), mean(all_rows$L < 35)), accuracy = 0.1)) %>%
  knitr::kable(caption = "The overall result barely moves if the dropped products are included")


## ----ref.label = knitr::all_labels(), eval = FALSE, echo = TRUE---------------
## NA

