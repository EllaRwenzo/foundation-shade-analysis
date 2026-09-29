"""Combine the per-product text files captured in the browser into two raw CSVs.

data/raw/shades_raw.csv  - one row per shade, exactly as read from the product pages
data/raw/products.csv    - one row per product, with the include / exclude decision
"""
import csv, glob, os, re

DATE = "2026-09-28"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Stock facts read from the product data on collection day (only recorded where the site exposed it)
EXTRA_STOCK = {  # product -> (shades in the product's full shade list, shades in stock)
    "#FauxFilter Luminous Matte Foundation": (39, 1),
}
EXCLUDE = {
    "#FauxFilter Luminous Matte Foundation": "Clearance: 1 of 39 shades in stock; page shows only 4 leftover shades",
    "Can't Stop Won't Stop Full Coverage Foundation": "Clearance: 0 of 23 listed shades in stock",
    "Positive Light Tinted Moisturizer SPF 20": "Clearance: 2 of 24 shades in stock",
}
STOCK_SITES = {"Charlotte Tilbury", "Rare Beauty", "Makeup by Mario", "Laura Mercier", "NYX Professional Makeup"}

def parse(path):
    meta, rows = {}, []
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip():
            continue
        key = line.split("|", 1)[0]
        if key in {"BRAND", "PRODUCT", "URL", "METHOD", "NOTE", "N", "EXCLUDED_REASON"}:
            meta[key] = line.split("|", 1)[1]
            continue
        parts = line.split("|")
        name, hexv, rest = parts[0].strip(), parts[1].strip().upper(), [p.strip() for p in parts[2:]]
        oos = "OOS" in rest
        rows.append({"shade": re.sub(r"\s+", " ", name), "hex": "#" + hexv, "oos": oos})
    assert int(meta["N"]) == len(rows), path
    return meta, rows

shade_rows, product_rows = [], []
files = sorted(glob.glob(os.path.join(ROOT, "data/raw_pages/*.txt"))) + sorted(glob.glob(os.path.join(ROOT, "data/excluded_pages/*.txt")))
for f in files:
    meta, rows = parse(f)
    brand, product = meta["BRAND"], meta["PRODUCT"]
    swatch_type = "color code" if meta["METHOD"] == "css_swatch_color" else "image"
    stock_recorded = brand in STOCK_SITES or product in EXTRA_STOCK
    for r in rows:
        in_stock = "" if not stock_recorded else ("FALSE" if r["oos"] else "TRUE")
        if product == "#FauxFilter Luminous Matte Foundation":
            in_stock = "TRUE" if r["shade"] == "Peaches N Cream 245B" else "FALSE"
        shade_rows.append({"brand": brand, "product": product, "shade": r["shade"], "hex": r["hex"],
                           "swatch_type": swatch_type, "in_stock": in_stock,
                           "source_url": meta["URL"], "date_collected": DATE})
    listed, in_stock_n = EXTRA_STOCK.get(product, (len(rows), sum(not r["oos"] for r in rows) if stock_recorded else ""))
    product_rows.append({"brand": brand, "product": product, "shades_collected": len(rows),
                         "shades_in_full_list": listed, "shades_in_stock": in_stock_n if stock_recorded else "",
                         "swatch_type": swatch_type, "included": "no" if product in EXCLUDE else "yes",
                         "exclusion_reason": EXCLUDE.get(product, ""), "source_url": meta["URL"],
                         "date_collected": DATE, "collection_note": meta.get("NOTE", "")})

brand_order = ["e.l.f.", "Maybelline", "Huda Beauty", "Charlotte Tilbury", "Hourglass", "L'Oreal Paris",
               "Laura Mercier", "NYX Professional Makeup", "Rare Beauty", "Makeup by Mario"]
shade_rows.sort(key=lambda r: (brand_order.index(r["brand"]), r["product"]))
product_rows.sort(key=lambda r: (brand_order.index(r["brand"]), r["product"]))
with open(os.path.join(ROOT, "data/raw/shades_raw.csv"), "w", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(fh, fieldnames=list(shade_rows[0].keys())); w.writeheader(); w.writerows(shade_rows)
with open(os.path.join(ROOT, "data/raw/products.csv"), "w", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(fh, fieldnames=list(product_rows[0].keys())); w.writeheader(); w.writerows(product_rows)
print(len(shade_rows), "shade rows;", len(product_rows), "products;",
      sum(p["included"] == "yes" for p in product_rows), "included products;",
      sum(p["shades_collected"] for p in product_rows if p["included"] == "yes"), "included shades")
