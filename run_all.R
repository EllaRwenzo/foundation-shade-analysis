# Rebuild everything: clean data, tables, charts and the HTML report.
# Open foundation-shade-analysis.Rproj in RStudio first, then run: source("run_all.R")
needed <- c("dplyr", "tidyr", "readr", "stringr", "forcats", "ggplot2", "farver", "scales", "knitr", "rmarkdown")
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) install.packages(missing)

rmarkdown::render("analysis/shade_analysis.Rmd", output_dir = "docs", output_file = "report.html")
knitr::purl("analysis/shade_analysis.Rmd", output = "analysis/shade_analysis.R", documentation = 1, quiet = TRUE)
message("Done. Open docs/report.html to read the report.")
