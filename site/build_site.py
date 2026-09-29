"""Build the portfolio web page (docs/index.html) from the R outputs.

Run after knitting analysis/shade_analysis.Rmd:
    python3 site/build_site.py
Every number on the page is read from files the R report wrote, so the page always matches the analysis.
"""
import csv, json, os, shutil, statistics
from html import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
REPO_URL = "https://github.com/EllaRwenzo/foundation-shade-analysis"  # shown as "Code on GitHub" on the page


def read_csv(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


shades = read_csv("data/clean/shades_clean.csv")
brand_stats = read_csv("output/tables/brand_summary.csv")
spacing = {r["brand"]: r for r in read_csv("output/tables/spacing_by_brand.csv")}
H = {r["key"]: r["value"] for r in read_csv("output/tables/headline_numbers.csv")}


def pct(x, digits=0):
    return f"{float(x) * 100:.{digits}f}%"


# ---------- data for the interactive explorer ----------
brand_order = [r["brand"] for r in sorted(brand_stats, key=lambda r: -float(r["pct_deeper_half"]))]
products = []
for b in brand_order:
    rows = [r for r in shades if r["brand"] == b]
    names = []
    for r in rows:
        if r["product"] not in names:
            names.append(r["product"])
    info = []
    for p in names:
        ps = [r for r in rows if r["product"] == p]
        info.append((p, min(float(r["L_star"]) for r in ps), len(ps), sum(float(r["L_star"]) < 55 for r in ps) / len(ps)))
    info.sort(key=lambda t: t[1])  # deepest reach first
    for p, _, n, share in info:
        products.append({"name": p, "brand": brand_order.index(b), "n": n, "deeper": round(share, 4)})

pindex = {(products[i]["brand"], products[i]["name"]): i for i in range(len(products))}
shade_rows = [[pindex[(brand_order.index(r["brand"]), r["product"])], r["shade"], r["hex"], round(float(r["L_star"]), 1)]
              for r in shades]
bstats = {r["brand"]: r for r in brand_stats}
brands = []
for b in brand_order:
    st = bstats[b]
    brands.append({"name": b, "n": int(st["shades"]), "products": int(st["products"]),
                   "deeper": round(float(st["pct_deeper_half"]), 4), "deep": round(float(st["pct_deep"]), 4),
                   "lightest": round(float(st["lightest"]), 1), "deepest": round(float(st["deepest"]), 1),
                   "gapLight": round(float(spacing[b]["lighter half"]), 2), "gapDeep": round(float(spacing[b]["deeper half"]), 2)})

monk_hex = ["#F6EDE4", "#F3E7DB", "#F7EAD0", "#EADABA", "#D7BD96", "#A07E56", "#825C43", "#604134", "#3A312A", "#292420"]


def lstar(hexv):
    def lin(v):
        v = v / 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hexv[i:i + 2], 16) for i in (1, 3, 5))
    y = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    f = y ** (1 / 3) if y > (6 / 29) ** 3 else y / (3 * (6 / 29) ** 2) + 4 / 29
    return 116 * f - 16


monk = [[i + 1, h, round(lstar(h), 1)] for i, h in enumerate(monk_hex)]
default_idx = next(i for i, r in enumerate(shades) if r["product"] == "Soft Glam Satin Foundation" and r["shade"] == "40 Tan Warm")
example = shades[default_idx]

DATA = {"brands": brands, "products": products, "shades": shade_rows, "monk": monk, "defaultShade": default_idx}

# ---------- chips for the stat cards: the real shade closest to each band's median ----------
chips = {}
for band in ["Light", "Medium", "Tan", "Deep"]:
    rows = [r for r in shades if r["depth_band"] == band]
    med = statistics.median(float(r["L_star"]) for r in rows)
    chips[band] = min(rows, key=lambda r: abs(float(r["L_star"]) - med))


def chip_caption(r):
    return f'{escape(r["brand"])} {escape(r["shade"])} · {r["hex"]}'


n_shades = int(H["n_shades"])
top = brands[0]
low = brands[-1]
deepest_brand = min(brands, key=lambda b: b["deepest"])
shallowest_brand = max(brands, key=lambda b: b["deepest"])

html = open(os.path.join(ROOT, "site", "template.html"), encoding="utf-8").read()
repl = {
    "{{N_SHADES}}": f"{n_shades:,}",
    "{{N_PRODUCTS}}": H["n_products"],
    "{{N_BRANDS}}": H["n_brands"],
    "{{SHARE_DEEPER}}": pct(H["share_deeper_half"]),
    "{{SHARE_LIGHTER}}": pct(1 - float(H["share_deeper_half"])),
    "{{SHARE_DEEP}}": pct(H["share_deep"]),
    "{{GAP_RATIO}}": f'{float(H["gap_ratio"]):.1f}',
    "{{GAP_LIGHT}}": f'{float(H["typical_gap_lighter_half"]):.1f}',
    "{{GAP_DEEP}}": f'{float(H["typical_gap_deeper_half"]):.1f}',
    "{{N_WIDER}}": H["n_deeper_wider"],
    "{{N_TESTED}}": H["n_products_tested"],
    "{{N_UNBALANCED}}": H["n_unbalanced_products"],
    "{{MEDIAN_OWN_HALF}}": pct(H["median_share_in_deeper_half_of_own_range"]),
    "{{SPEARMAN_RHO}}": f'{float(H["spearman_rho"]):.2f}',
    "{{SPEARMAN_P}}": f'{float(H["spearman_p"]):.2f}',
    "{{N_BIG}}": H["n_big_ranges"],
    "{{BIG_MIN}}": pct(H["big_ranges_min_share"]),
    "{{BIG_MAX}}": pct(H["big_ranges_max_share"]),
    "{{N_REPEATED}}": H["n_repeated_color_pairs"],
    "{{N_ORDER_FLAGS}}": H["n_order_flags"],
    "{{TOP_BRAND}}": escape(top["name"]), "{{TOP_SHARE}}": pct(top["deeper"]),
    "{{LOW_BRAND}}": escape(low["name"]), "{{LOW_SHARE}}": pct(low["deeper"]),
    "{{DEEPEST_BRAND}}": escape(deepest_brand["name"]), "{{DEEPEST_L}}": f'{deepest_brand["deepest"]:.1f}',
    "{{SHALLOW_BRAND}}": escape(shallowest_brand["name"]), "{{SHALLOW_L}}": f'{shallowest_brand["deepest"]:.1f}',
    "{{EX_HEX}}": example["hex"], "{{EX_R}}": example["R"], "{{EX_G}}": example["G"], "{{EX_B}}": example["B"],
    "{{EX_L}}": f'{float(example["L_star"]):.1f}', "{{EX_BAND}}": example["depth_band"],
    "{{EX_NAME}}": escape(f'e.l.f. Soft Glam Satin Foundation, shade {example["shade"]}'),
    "{{CHIP_LIGHT}}": chips["Light"]["hex"], "{{CHIP_MEDIUM}}": chips["Medium"]["hex"],
    "{{CHIP_TAN}}": chips["Tan"]["hex"], "{{CHIP_DEEP}}": chips["Deep"]["hex"],
    "{{CAP_LIGHT}}": chip_caption(chips["Light"]), "{{CAP_MEDIUM}}": chip_caption(chips["Medium"]),
    "{{CAP_TAN}}": chip_caption(chips["Tan"]), "{{CAP_DEEP}}": chip_caption(chips["Deep"]),
    "{{REPO_URL}}": escape(REPO_URL),
    "{{DATA_JSON}}": json.dumps(DATA, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/"),
}
for k, v in repl.items():
    html = html.replace(k, str(v))
assert "{{" not in html, [line for line in html.splitlines() if "{{" in line][:5]

# The knitted report bundles jQuery, which contains one literal U+FFFD character inside a JavaScript
# string. Write it as the equivalent JavaScript escape so the file is clean UTF-8 text everywhere.
report_path = os.path.join(DOCS, "report.html")
if os.path.exists(report_path):
    rep = open(report_path, encoding="utf-8").read()
    if "\ufffd" in rep:
        open(report_path, "w", encoding="utf-8").write(rep.replace("\ufffd", "\\uFFFD"))

os.makedirs(os.path.join(DOCS, "charts"), exist_ok=True)
os.makedirs(os.path.join(DOCS, "data"), exist_ok=True)
for f in ["01_lightness_histogram.png", "03_shade_strip_by_brand.png", "04_depth_bands_by_brand.png",
          "05_spacing_light_vs_deep.png", "06_shade_count_vs_balance.png", "07_shade_wall_all_products.png"]:
    shutil.copy(os.path.join(ROOT, "output", "charts", f), os.path.join(DOCS, "charts", f))
shutil.copy(os.path.join(ROOT, "data", "clean", "shades_clean.csv"), os.path.join(DOCS, "data", "shades_clean.csv"))
head_part, body_part = html.split("<!--BODY-->")
full_page = ("<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
             "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">\n"
             + head_part + "</head>\n<body>\n" + body_part + "</body>\n</html>\n")
with open(os.path.join(DOCS, "index.html"), "w", encoding="utf-8") as fh:   # GitHub Pages version
    fh.write(full_page)
with open(os.path.join(ROOT, "site", "artifact.html"), "w", encoding="utf-8") as fh:  # content-only version
    fh.write(head_part + body_part)
print("wrote docs/index.html", len(full_page) // 1024, "KB")
