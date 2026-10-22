Sys.unsetenv(c('SSB_SINGLE_PANEL','SSB_VECTOR_ONLY'))
Sys.setenv(SSB_RENDER_FIGURES='S21')
source('R/06_render_composites_only.R')
