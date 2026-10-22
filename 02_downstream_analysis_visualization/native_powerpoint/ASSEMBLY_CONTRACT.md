# Editable PowerPoint figure assembly

Scope: assemble the approved Figure 1–4 and Supplementary Figure S1–S28 in one 32-slide deck. Preserve all 117 registered panels, current HC/AD/Other definitions, statistics, colours and panel identifiers. No scientific reanalysis.

Evidence: the existing registered panel functions and figure source data are authoritative; historical unregistered panel files are excluded. Each slide corresponds to one manuscript figure and carries its English panel legends in speaker notes.

Layout: quantitative grids and wide structural-profile hero panels, retaining the approved figure hierarchy. Use a common portrait 200 × 280 mm canvas; plot area 183 mm wide and no more than 250 mm high. Arial, 8.5 pt figure text; retain current 1.5 pt line specification. Independent editable panel objects, rather than flattened slide screenshots.

Backend: R exclusively (ggplot2/patchwork for plots, officer/rvg for native DrawingML). Install the missing rvg package only into this assembly's isolated R_library directory with author permission. Do not modify the existing analysis environment or statistical outputs.

Exports: a single editable PPTX, reproducible R assembly script, slide/panel/source-data index, contact-sheet previews and an archive/coverage QA report. The deck is vector based, not a 600-dpi raster file; original 600-dpi TIFFs remain in the submission package.

QA: exactly 32 figure slides, all 117 registered panels included once, no obsolete panels, native editable text/vector shapes, no slide-image replacement, numeric figure order, all slide contents within page bounds. Review all slides using R-generated previews and inspect dense full-size pages. State any renderer/viewer limitations explicitly.
