"""Make the Tableau-ready CSV from the clean data (run after the R report)."""
import csv, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rows = list(csv.DictReader(open(os.path.join(ROOT, "data/clean/shades_clean.csv"), encoding="utf-8")))
order = {"Light": 1, "Medium": 2, "Tan": 3, "Deep": 4}
fields = ["brand", "product", "product_type", "shade", "hex", "R", "G", "B", "L_star", "depth_band", "band_order",
          "in_deeper_half", "rank_in_product", "gap_to_next", "product_half", "swatch_type", "in_stock", "source_url"]
with open(os.path.join(ROOT, "tableau/shades_for_tableau.csv"), "w", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(fh, fieldnames=fields)
    w.writeheader()
    for r in rows:
        w.writerow({**{k: r[k] for k in fields if k in r}, "band_order": order[r["depth_band"]],
                    "in_deeper_half": "Yes" if float(r["L_star"]) < 55 else "No"})
print(len(rows), "rows written to tableau/shades_for_tableau.csv")
