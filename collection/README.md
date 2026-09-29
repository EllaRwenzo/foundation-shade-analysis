# How the shade data was collected

**Date:** September 28, 2026. **Where:** each brand's official US website, in Google Chrome.

## Steps

1. **Find the products.** Open the brand's Foundation section and list every foundation, skin tint,
   CC cream and glow filter. Skip powders, primers, concealers, brushes, minis and one-shade products.
2. **Read every swatch.** On each product page, run `swatch_reader.js` in the browser console
   (instructions at the top of the file). It prints one line per shade: `shade name|HEX`.
   - **Color-code swatches** (e.l.f., Maybelline, Huda Beauty, Hourglass, L'Oréal Paris, Laura Mercier, NYX):
     the page paints each swatch with a color, and the script reads that color exactly.
   - **Image swatches** (Charlotte Tilbury, Rare Beauty, Makeup by Mario): the script loads each swatch
     photo, keeps its middle 50%, ignores background pixels, drops the brightest 25% and darkest 25%
     of what is left (shine and shadow), and averages the rest.
   - Rare Beauty hides sold-out shades on the Liquid Touch page, so the script also reads the brand's
     own swatch files for those shades (same file-name pattern as the visible ones).
3. **Save the page capture.** Each product's lines were saved as one text file in `data/raw_pages/`
   (or `data/excluded_pages/` for the clearance products), with the brand, product name and URL on top.
4. **Combine.** `python3 collection/combine_pages.py` turns the captures into
   `data/raw/shades_raw.csv` (one row per shade) and `data/raw/products.csv` (one row per product,
   with the include/exclude decision). Everything after this is done in R.

## Checks that were run

- **Every saved list was re-read from the live pages.** For all 49 products, a second pass read each
  product page again and compared a SHA-256 fingerprint of the sorted `shade|HEX` lines with the saved file.
  All 49 match. For the image brands this includes re-sampling every swatch photo, which gave the
  exact same colors.
- **The re-check found and fixed 3 missing shades.** On three L'Oréal Paris pages, the shade that is
  selected when the page opens loaded late and was missed on the first pass: Infallible 32H Fresh Wear
  "435 - rose vanilla", True Match Lumi Healthy Luminous "true beige" and Infallible Cushion "130 warm".
  They were added, and those three lists now match the live pages too.
- **Photo swatches were checked by eye.** For Charlotte Tilbury, Rare Beauty and Makeup by Mario, the averaged
  colors were placed next to the original swatch photos on the live pages and matched them.

## Products left out

| Product | Why |
|---|---|
| Huda Beauty #FauxFilter Luminous Matte Foundation | Clearance: 1 of 39 shades in stock; page shows only 4 leftover shades (replaced by Easy Blur) |
| NYX Can't Stop Won't Stop Full Coverage Foundation | Clearance: 0 of 23 listed shades in stock |
| Rare Beauty Positive Light Tinted Moisturizer SPF 20 | Clearance: 2 of 24 shades in stock |
| Charlotte Tilbury Unisex Healthy Glow Tinted Moisturiser | One universal shade, no shade range |
| NYX Total Control Pro Drop Foundation | Page now redirects to another product (discontinued) |
| Makeup by Mario SoftSculpt products | Sculpting and bronzing products, not skin-matching foundations |
