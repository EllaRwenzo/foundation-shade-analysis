/*
  Swatch reader — paste into the browser console on a brand's product page.

  How to use:
    1. Open a foundation product page on the brand's official US website (for example
       https://www.elfcosmetics.com/products/soft-glam-satin-foundation).
    2. Open the browser console (Chrome: View > Developer > JavaScript Console).
    3. Paste this whole file and press Enter. It prints one line per shade: "shade name|HEX".

  Two kinds of swatches:
    - Color code: the page paints the swatch with a color. The script reads that color exactly.
    - Image: the swatch is a small photo. The script loads the photo, keeps the middle 50% of it,
      ignores see-through and white background pixels, sorts the rest by brightness, drops the
      brightest 25% (shine) and darkest 25% (shadow), and averages what is left.

  Brand websites change their page code often, so a reader may need small updates later.
  These readers match the pages as they were on September 28, 2026.
*/
(async function readSwatches() {
  const waitFor = async (test, ms = 10000) => {
    const start = Date.now();
    while (!test() && Date.now() - start < ms) await new Promise(r => setTimeout(r, 300));
  };
  const rgbToHex = css => {
    const m = css.match(/\d+(\.\d+)?/g);
    return m ? m.slice(0, 3).map(v => Math.round(+v).toString(16).padStart(2, "0")).join("").toUpperCase() : "";
  };
  const firstColor = (el, skip = ["rgb(255, 255, 255)", "rgb(0, 0, 0)"]) => {
    for (const d of [el, ...el.querySelectorAll("*")]) {
      const bg = getComputedStyle(d).backgroundColor;
      if (bg.startsWith("rgb(") && !skip.includes(bg)) return rgbToHex(bg);
    }
    return "";
  };

  // Average color of the middle of a swatch photo (trimmed mean, see note above)
  async function sampleImage(url) {
    const img = new Image();
    img.crossOrigin = "anonymous";
    await new Promise((ok, fail) => { img.onload = ok; img.onerror = fail; img.src = url; setTimeout(fail, 15000); });
    const W = img.naturalWidth, H = img.naturalHeight;
    const canvas = document.createElement("canvas");
    canvas.width = W; canvas.height = H;
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(img, 0, 0);
    const w = Math.max(1, Math.floor(W * 0.5)), h = Math.max(1, Math.floor(H * 0.5));
    const data = ctx.getImageData(Math.floor(W * 0.25), Math.floor(H * 0.25), w, h).data;
    const px = [];
    for (let i = 0; i < data.length; i += 4) {
      const r = data[i], g = data[i + 1], b = data[i + 2], a = data[i + 3];
      if (a < 200) continue;                                             // see-through
      const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
      if (mn > 235 && mx - mn < 15) continue;                            // white background
      px.push([r, g, b, 0.2126 * r + 0.7152 * g + 0.0722 * b]);
    }
    if (!px.length) return "";
    px.sort((p, q) => p[3] - q[3]);
    const lo = Math.floor(px.length * 0.25), hi = Math.max(lo + 1, Math.ceil(px.length * 0.75));
    const mid = px.slice(lo, hi);
    const avg = k => Math.round(mid.reduce((s, p) => s + p[k], 0) / mid.length);
    return [avg(0), avg(1), avg(2)].map(v => v.toString(16).padStart(2, "0")).join("").toUpperCase();
  }
  const shopifyProduct = () => fetch("/products/" + location.pathname.split("/products/")[1].split("/")[0] + ".js").then(r => r.json());

  const host = location.hostname;
  let rows = [];  // [shade name, HEX]

  if (host.includes("elfcosmetics")) {                       // color code
    await waitFor(() => document.querySelector('[role="list"] [role="listitem"][data-variant-id]'));
    const seen = new Set();
    for (const el of document.querySelectorAll('[role="list"] [role="listitem"][data-variant-id]')) {
      const name = el.getAttribute("aria-label");
      if (seen.has(name)) continue; seen.add(name);
      let hex = ""; for (const d of [el, ...el.querySelectorAll("*")]) { const bg = getComputedStyle(d).backgroundColor; if (bg.startsWith("rgb(") && bg !== "rgb(255, 255, 255)") hex = rgbToHex(bg); }
      rows.push([name, hex]);
    }
  } else if (host.includes("hudabeauty")) {                  // color code
    await waitFor(() => [...document.querySelectorAll('input[type="radio"]')].some(r => /swatch-Shade/i.test(r.name)));
    const seen = new Set();
    for (const r of document.querySelectorAll('input[type="radio"]')) {
      if (!/swatch-Shade/i.test(r.name) || seen.has(r.value)) continue; seen.add(r.value);
      const label = document.querySelector('label[for="' + r.id + '"]') || r.closest("label");
      rows.push([r.value, label ? firstColor(label, ["rgb(255, 255, 255)"]) : ""]);
    }
  } else if (host.includes("hourglasscosmetics")) {          // color code
    await waitFor(() => document.querySelectorAll('button[aria-label^="Select "]').length > 2);
    const seen = new Set();
    for (const b of document.querySelectorAll('button[aria-label^="Select "]')) {
      const name = b.getAttribute("aria-label").replace(/^Select\s+/, "").trim();
      const hex = firstColor(b);
      if (seen.has(name) || !hex) continue; seen.add(name);
      rows.push([name, hex]);
    }
  } else if (host.includes("lauramercier")) {                // color code (Shopify swatch setting)
    await waitFor(() => document.querySelectorAll('label[title] [style*="--swatch--background"]').length > 2);
    const product = await shopifyProduct();
    const byName = {};
    for (const l of document.querySelectorAll("label[title]")) {
      const s = l.querySelector('[style*="--swatch--background"]'); if (!s) continue;
      const m = s.getAttribute("style").match(/--swatch--background:\s*([^;]+);/);
      byName[l.getAttribute("title").trim()] ??= m ? m[1].trim().replace("#", "").toUpperCase() : "";
    }
    rows = product.variants.map(v => [v.title, byName[v.title] || byName[v.option1] || ""]);
  } else if (host.includes("nyxcosmetics")) {                // color code
    await waitFor(() => document.querySelector(".c-product-main__swatches-grouped .c-swatch[data-js-value]"));
    const seen = new Set();
    for (const a of document.querySelector(".c-product-main__swatches-grouped").querySelectorAll(".c-swatch")) {
      const name = (a.getAttribute("data-js-value") || "").trim(); if (!name || seen.has(name)) continue; seen.add(name);
      const m = (a.getAttribute("style") || "").match(/background-color:\s*#([0-9a-fA-F]{6})/);
      rows.push([name, m ? m[1].toUpperCase() : ""]);
    }
  } else if (host.includes("lorealparisusa")) {              // color code
    await waitFor(() => document.querySelectorAll('a[aria-label^="see "] span[style*="background-color"]').length > 2);
    const seen = new Set();
    for (const a of document.querySelectorAll('a[aria-label^="see "]')) {
      const span = a.querySelector('span[style*="background-color"]'); if (!span) continue;
      const label = a.getAttribute("aria-label"); const name = label.slice(label.lastIndexOf(" in ") + 4).trim();
      if (seen.has(name)) continue; seen.add(name);
      rows.push([name, rgbToHex(getComputedStyle(span).backgroundColor)]);
    }
  } else if (host.includes("maybelline")) {                  // color code
    await waitFor(() => document.querySelectorAll(".shade-selector__item input[data-color]").length > 2);
    const seen = new Set();
    for (const i of document.querySelectorAll(".shade-selector__item input[data-color]")) {
      const id = i.getAttribute("data-variant-id") || i.getAttribute("data-name"); if (seen.has(id)) continue; seen.add(id);
      const name = ((i.getAttribute("data-display-name") || "") + " " + (i.getAttribute("data-description-name") || "")).trim();
      rows.push([name, (i.getAttribute("data-color") || "").toUpperCase()]);
    }
  } else if (host.includes("charlottetilbury")) {            // image
    const pick = () => [...document.querySelectorAll("a[aria-label]")].filter(a => a.querySelector("picture, img") && a.getBoundingClientRect().width < 120 && a.getBoundingClientRect().width > 20);
    await waitFor(() => pick().length > 2);
    const seen = new Set(), items = [];
    for (const a of pick()) {
      const name = a.getAttribute("aria-label").split(" - ")[0].trim(); if (!name || seen.has(name)) continue; seen.add(name);
      const img = a.querySelector("img");
      const srcset = [...a.querySelectorAll("source")].map(s => (s.getAttribute("srcset") || "").split(" ")[0]).filter(Boolean);
      const u = new URL((img && (img.getAttribute("src") || img.getAttribute("data-src"))) || srcset[0] || "", location.href); u.search = "";
      items.push([name, u.href + "?w=200&h=200&fm=png"]);
    }
    const hexes = await Promise.all(items.map(([, url]) => sampleImage(url).catch(() => "")));
    rows = items.map(([name], i) => [name, hexes[i]]);
  } else if (host.includes("rarebeauty")) {                  // image
    await waitFor(() => [...document.querySelectorAll('label[for^="option1-"]')].some(l => l.querySelector("img")));
    await new Promise(r => setTimeout(r, 1500));
    const product = await shopifyProduct();
    const byName = {};
    for (const l of document.querySelectorAll('label[for^="option1-"]')) {
      const img = l.querySelector("img"); if (!img) continue;
      byName[document.getElementById(l.htmlFor).value] = (img.getAttribute("data-srcset") || img.getAttribute("src") || "").split(" ")[0].replace(/\?.*/, "");
    }
    // Sold-out shades can be hidden on the page; their swatch files follow the same name pattern
    const known = Object.keys(byName)[0], raw = byName[known], at = raw.toLowerCase().lastIndexOf(known.toLowerCase());
    const pre = raw.slice(0, at), post = raw.slice(at + known.length);
    const items = product.variants.map(v => [v.title, new URL(byName[v.title] || (pre + v.title.toLowerCase() + post), location.href).href + "?width=200"]);
    const hexes = await Promise.all(items.map(([, url]) => sampleImage(url).catch(() => "")));
    rows = items.map(([name], i) => [name, hexes[i]]);
  } else if (host.includes("makeupbymario")) {               // image
    await waitFor(() => [...document.querySelectorAll("button img[alt]")].filter(i => i.alt.includes(" - ")).length > 2);
    const product = await shopifyProduct();
    const byName = {};
    for (const img of document.querySelectorAll("button img[alt]")) {
      if (!img.alt.includes(" - ")) continue;
      byName[img.alt.split(" - ").slice(1).join(" - ").trim()] ??= (img.getAttribute("src") || img.currentSrc || "").replace(/\?.*/, "");
    }
    const items = product.variants.map(v => [v.title, new URL(byName[v.title], location.href).href + "?width=200"]);
    const hexes = await Promise.all(items.map(([, url]) => sampleImage(url).catch(() => "")));
    rows = items.map(([name], i) => [name, hexes[i]]);
  } else {
    console.warn("No reader for this site yet:", host);
    return;
  }

  const out = rows.map(([name, hex]) => name.replace(/\s+/g, " ").trim() + "|" + hex).join("\n");
  console.log(rows.length + " shades\n" + out);
  return out;
})();
