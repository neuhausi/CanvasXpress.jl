#!/usr/bin/env Rscript
# Generates the P1 reference data-model fixtures from the R canvasXpress package.
# Each fixture is the exact `data` object (y/x/z) that R emits, serialized with the
# same htmlwidgets settings (auto_unbox, digits=4, na="null", dataframe="columns").
# The Julia test rebuilds the same inputs and asserts byte/parse equality.
#
# Datasets are chosen single-type per annotation frame so R's mixed-type character
# coercion (space-padded strings) is not a confound — R and a correct Julia impl agree.
suppressMessages(library(canvasXpress))

outdir <- "fixtures"
dir.create(outdir, showWarnings = FALSE)

dump <- function(name, cx) {
    j <- jsonlite::toJSON(cx$x$data, auto_unbox = TRUE, digits = 4,
                          na = "null", null = "null", dataframe = "columns")
    writeLines(as.character(j), file.path(outdir, paste0(name, ".json")))
    cat(name, "->", as.character(j), "\n")
}

# 1. Named numeric matrix, no annotations.
m1 <- matrix(c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12), nrow = 3, byrow = TRUE,
             dimnames = list(c("g1", "g2", "g3"), c("s1", "s2", "s3", "s4")))
dump("matrix_basic", canvasXpress(data = m1, graphType = "Heatmap"))

# 2. Unnamed matrix -> V-prefixed vars and smps.
m2 <- matrix(c(1.5, 2.5, 3.5, 4.5, 5.5, 6.5), nrow = 2, byrow = TRUE)
dump("matrix_nodimnames", canvasXpress(data = m2, graphType = "Heatmap"))

# 3. Matrix + numeric-only sample annotation -> x.
smp3 <- data.frame(Dose = c(5, 10, 15, 20), Age = c(30, 40, 50, 60),
                   row.names = c("s1", "s2", "s3", "s4"))
dump("smpannot_numeric", canvasXpress(data = m1, smpAnnot = smp3, graphType = "Heatmap"))

# 4. Matrix + character-only variable annotation -> z.
var4 <- data.frame(Pathway = c("P1", "P2", "P1"), Class = c("A", "B", "A"),
                   row.names = c("g1", "g2", "g3"))
dump("varannot_char", canvasXpress(data = m1, varAnnot = var4, graphType = "Heatmap"))

# 5. Matrix with NA/NaN (-> null) + numeric smpAnnot + character varAnnot.
m5 <- m1
m5[1, 2] <- NA
m5[3, 4] <- NaN
dump("matrix_missing",
     canvasXpress(data = m5, smpAnnot = smp3, varAnnot = var4, graphType = "Heatmap"))
