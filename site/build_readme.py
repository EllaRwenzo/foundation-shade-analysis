"""Write README.md from the numbers the R report saved (run after knitting the report)."""
import csv, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
H = {r["key"]: r["value"] for r in csv.DictReader(open(os.path.join(ROOT, "output/tables/headline_numbers.csv"), encoding="utf-8"))}
B = list(csv.DictReader(open(os.path.join(ROOT, "output/tables/brand_summary.csv"), encoding="utf-8")))
B.sort(key=lambda r: -float(r["pct_deeper_half"]))
pct = lambda x: f"{float(x) * 100:.0f}%"
n = int(H["n_shades"])
SITE = "https://ellarwenzo.github.io/foundation-shade-analysis/"

rows = "\n".join(
    f"| {r['brand']} | {r['products']} | {r['shades']} | {float(r['lightest']):.1f} | {float(r['deepest']):.1f} | {pct(r['pct_deep'])} | {pct(r['pct_deeper_half'])} |"
    for r in B)

readme = f"""# Foundation Shade Inclusivity Analysis

**How evenly do 10 beauty brands spread their foundation shades from light to deep?**

I built an original dataset of **{n:,} foundation shades** from **{H['n_products']} products** across **{H['n_brands']} brands**
by reading every shade swatch on the brands' official US product pages. I converted each swatch
from HEX to RGB to CIELAB lightness (L\\*) in R, then used descriptive statistics, a paired
statistical test and ggplot2 charts to see where the shades fall on the light-to-deep scale.

- **Live project page:** [ellarwenzo.github.io/foundation-shade-analysis]({SITE}) (interactive shade explorer and charts)
- **Full R report:** [report.html]({SITE}report.html) (all code, tables, charts and write-up; source in `analysis/shade_analysis.Rmd`)
- **Data:** [`data/clean/shades_clean.csv`](data/clean/shades_clean.csv) (one row per shade)

![Every shade, lightest to deepest](output/charts/03_shade_strip_by_brand.png)

## Key findings

- **Most shades are light.** {pct(1 - float(H['share_deeper_half']))} of the {n:,} shades are in the lighter half of the
  lightness scale. Only {pct(H['share_deep'])} are in the Deep band (L\\* below 35), where Monk skin tones 8–10 sit.
- **No brand reaches an even split.** The share of shades in the deeper half ranges from
  {pct(B[-1]['pct_deeper_half'])} ({B[-1]['brand']}) to {pct(B[0]['pct_deeper_half'])} ({B[0]['brand']}).
- **Deep shades are spaced further apart.** The typical gap between neighboring shades is
  {float(H['typical_gap_lighter_half']):.1f} lightness points in a product's lighter half and {float(H['typical_gap_deeper_half']):.1f} in its deeper half
  (about {float(H['gap_ratio']):.1f}×). This held in {H['n_deeper_wider']} of {H['n_products_tested']} products (Wilcoxon signed-rank test, p < 0.001).
- **More shades does not mean more balance.** The {H['n_big_ranges']} biggest ranges (40+ shades) put only
  {pct(H['big_ranges_min_share'])}–{pct(H['big_ranges_max_share'])} of their shades in the deeper half (Spearman ρ = {float(H['spearman_rho']):.2f}, p = {float(H['spearman_p']):.2f}).

| Brand | Products | Shades | Lightest L\\* | Deepest L\\* | Deep band | Deeper half |
|---|---:|---:|---:|---:|---:|---:|
{rows}

![Share of shades in each band](output/charts/04_depth_bands_by_brand.png)
![Spacing between neighboring shades](output/charts/05_spacing_light_vs_deep.png)

## The question

When a brand makes a foundation in many shades, are those shades spread evenly from light to
deep, or bunched at the light end? I look at four things:

1. **Reach:** how light and how deep each brand's range goes.
2. **Balance:** the share of shades in the deeper half of the lightness scale.
3. **Spacing:** whether deep shades are as close together as light shades.
4. **Size vs. balance:** whether products with more shades are more balanced.

## Data

- **Sources:** official US websites of e.l.f., Maybelline, Huda Beauty, Charlotte Tilbury,
  Hourglass, L'Oréal Paris, Laura Mercier, NYX Professional Makeup, Rare Beauty and Makeup by Mario.
- **Collected:** September 28, 2026.
- **Scope:** every foundation, skin tint, CC cream and glow filter in each brand's Foundation
  section, with every shade listed (sold-out shades included). Powders, concealers, primers,
  brushes, minis and one-shade products are not included.
- **Dropped:** three products the brands are clearing out, where 10% or fewer of the shades could be
  bought (see `data/raw/products.csv`). Adding them back barely changes the results (Section 13 of the report).
- **Checked:** every saved shade list was re-read from the live product pages and matched
  (details in `collection/README.md`).

**How swatch colors were read** (scripts in `collection/`):

| Swatch type | Brands | Method |
|---|---|---|
| Color code | e.l.f., Maybelline, Huda Beauty, Hourglass, L'Oréal Paris, Laura Mercier, NYX | The page paints each swatch with a color code; recorded exactly. |
| Image | Charlotte Tilbury, Rare Beauty, Makeup by Mario | Middle 50% of the swatch photo, brightest and darkest 25% of pixels dropped, the rest averaged. |

### Data dictionary (`data/clean/shades_clean.csv`)

| Column | Meaning |
|---|---|
| brand, product, shade | As shown on the brand's site |
| product_type | Foundation, Skin tint, CC cream or Glow filter (from the product name) |
| hex | Swatch color, for example `#BA8656` |
| R, G, B | Red, green, blue (0–255) |
| L_star | CIELAB lightness, 0 = black, 100 = white (main measure) |
| a_star, b_star | Other CIELAB values (red–green, yellow–blue), kept for undertone work |
| depth_band | Light (75+), Medium (55–75), Tan (35–55), Deep (below 35) |
| rank_in_product | 1 = the product's lightest shade |
| gap_to_next | Lightness difference to the next deeper shade in the same product |
| product_half | Lighter or deeper half of the product's own range |
| swatch_type | Color code or image |
| in_stock | TRUE/FALSE where the site showed stock; blank otherwise |
| source_url, date_collected | Where and when the swatch was read |

## Method in one line

`swatch → HEX → R, G, B → linear light → Y = 0.2126R + 0.7152G + 0.0722B → L* = 116·Y^(1/3) − 16 → bands, gaps, test`

The depth bands are four equal 20-point slices of L\\* between 15 and 95, which is the span of
Google's Monk Skin Tone Scale (tones 1–10). The spacing test compares, inside each product, the
typical gap between neighboring shades in its lighter half vs. its deeper half (Wilcoxon signed-rank,
paired, no bell-curve assumption).

## Limitations

- Swatches are screen colors, not the product on skin, and brands don't calibrate them against each other.
- {H['n_repeated_color_pairs']} pairs of shades share one swatch color, and in {H['n_order_flags']} spots a higher-numbered shade has a
  clearly lighter swatch than the one before it, so swatches are approximate.
- Lightness only; undertone is saved (a\\*, b\\*) but not analyzed yet.
- One day and ten brands; lineups change and these brands are not a random sample.

## Reproduce it

1. Install R and RStudio, then run once in the R console:
   `install.packages(c("dplyr", "tidyr", "readr", "stringr", "forcats", "ggplot2", "farver", "scales", "knitr", "rmarkdown"))`
2. Open `foundation-shade-analysis.Rproj`, then run `source("run_all.R")`.
   This knits `analysis/shade_analysis.Rmd` into `docs/report.html` and rewrites the clean data,
   tables and charts.
3. Optional: `python3 site/build_site.py` rebuilds the project page `docs/index.html` from those outputs.

## Folder guide

```
analysis/     shade_analysis.Rmd (the full analysis) and shade_analysis.R (same code, plain script)
data/raw/     shades_raw.csv (every swatch as collected) and products.csv (product list + include/exclude)
data/clean/   shades_clean.csv (analysis-ready)
data/raw_pages/, data/excluded_pages/   one text file per product page, as captured
collection/   swatch_reader.js (browser script), combine_pages.py, README.md
output/       charts (PNG) and tables (CSV) written by the report
docs/         project page (index.html) and knitted report, served by GitHub Pages
site/         scripts that build docs/index.html and this README
tableau/      Tableau-ready CSV and steps
```

## Credits

Monk Skin Tone Scale by Dr. Ellis Monk and Google (skintone.google), CC BY 4.0.
Built with R: dplyr, tidyr, readr, stringr, forcats, ggplot2, farver, scales, R Markdown.
"""
open(os.path.join(ROOT, "README.md"), "w", encoding="utf-8").write(readme)
print("wrote README.md")
