SSB manuscript figures — editable PowerPoint assembly
====================================================

Primary deliverable: SSB_All_Figures_editable_20261015.pptx

Coverage: Figure 1–4, then Supplementary Figure S1–S28, one figure per slide.
All 117 current registered panels are included. Historical, superseded panels
are not included. The scientific data, statistics and group definitions have
not been changed for this assembly.

Page format: portrait 200 × 280 mm, suitable for manuscript figure assembly.
Figure area: 183 mm wide, maximum 250 mm high. Figure text: Arial 8.5 pt.
Group colours and original panel identifiers are retained. Full English panel
legends are in the speaker notes. Figure 1 remains HC / AD / Other throughout.

Editing in Microsoft PowerPoint:
  1. Select a panel group to move or resize the whole panel.
  2. Right-click > Group > Ungroup (repeat for nested groups when necessary)
     to edit native vector text, points, lines and other shapes.
  3. Install Arial on the editing computer to avoid font substitution.
  4. Dense volcano plots contain many editable points; allow time for opening
     and ungrouping. Keep an untouched master copy before editing.

The plots are native DrawingML vector shapes, not flattened slide screenshots
or linked Office charts. Editing an axis label does not recompute statistics.
To update the quantitative content, edit the corresponding R source and rerun.
Vector PowerPoint files do not have a fixed dpi; the original 600-dpi TIFFs
remain available in the existing submission figure folders.

Reproducibility:
  Run assemble_all_figures.R from the analysis project root with Rscript.
  It reads the existing approved plot definitions and results; statistical
  analysis is not rerun. Original write helpers are disabled during loading.
  Optional environment variables: SSB_PROJECT_ROOT, SSB_PPT_OUT.
  R dependencies: ggplot2, patchwork, officer, rvg, data.table, xml2, ragg,
  png, zip, openxlsx, and the dependencies of the existing R figure workflow.
  rvg 0.4.2 was installed in this folder's isolated R_library, not in the
  original analysis environment. Makevars records the local compiler choice.
  For another machine, install rvg using install.packages('rvg') as appropriate.

Files:
  Slide_panel_index.xlsx: slide order, figure/panel identifiers, geometry,
                         plotting-data Excel and original per-panel R scripts.
  previews/: R-rendered slide-layout previews.
  qa/: coverage, native-shape/text audit, contact sheets, versions and checksums.

Quality-control scope:
  All slide layouts are inspected using R previews. The PPTX archive is checked
  for slide/panel coverage, editable text/vector shapes and absence of raster
  panel replacements. Reserved non-data header strips in previews are repainted
  independently to avoid device clipping; pixel QA confirms quantitative content
  is unchanged. These previews are not a native PowerPoint application
  rendering; Microsoft PowerPoint was not available in this environment.
