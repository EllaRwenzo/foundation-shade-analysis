# Build the Tableau Public version (about 20 minutes, free)

Tableau Public gives you a second shareable link. Everything you publish there is public, which is
fine for this data.

1. Go to public.tableau.com, create a free account, then choose **Create > Web Authoring**.
   (You can also download the free Tableau Public desktop app.)
2. **Connect to data:** upload `shades_for_tableau.csv` from this folder.

## Sheet 1: "Every shade, light to deep"
3. Drag **L Star** to **Columns**. Then open the **Analysis** menu and untick **Aggregate Measures**, so every shade becomes its own mark.
4. Right-click the L Star axis > **Edit Axis** > tick **Reversed** (light on the left, deep on the right).
5. Drag **Brand** to **Rows**.
6. In the Marks card, change the mark type to **Gantt Bar** (thin lines) or **Circle**.
7. Drag **L Star** onto **Color**. Click Color > **Edit Colors** > choose the **Brown** palette and tick **Reversed**
   so deeper shades are darker. (Tableau can't paint each mark with its own HEX code, so lightness
   stands in for the color.)
8. Drag **Product**, **Shade**, **Hex** and **Depth Band** onto **Tooltip**.
9. Sort Brand by the share of deeper shades: right-click Brand > Sort > **Field**, **Average** of a field you
   make with **Analysis > Create Calculated Field**: name it `Deeper Half Flag`, formula `IIF([L Star] < 55, 1, 0)`.

## Sheet 2: "Share of shades in each band"
10. New sheet. **Brand** to Rows, **Depth Band** to Color, and the count of rows to Columns
    (drag **shades_for_tableau.csv (Count)**).
11. Click the count pill > **Quick Table Calculation > Percent of Total**, then **Compute Using > Depth Band**.
12. Sort the colors by **Band Order** (Light, Medium, Tan, Deep) and pick four browns, light to dark.

## Dashboard
13. **New Dashboard**, drag in both sheets, add a title ("Foundation Shade Inclusivity") and a one-line
    note: "1,161 shades from 46 products and 10 brands, collected Sept 28, 2026. L* = lightness (0 black, 100 white)."
14. Click **Publish**. Copy the link from your Tableau Public profile and add it to your resume or GitHub README.
