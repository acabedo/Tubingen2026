#!/usr/bin/env Rscript
# Lanzador único de OralStats: reproduce el entorno y arranca la app.
# Uso:  Rscript run.R     (desde la carpeta Oralstats/)

# Trabajar siempre desde el directorio de este script.
.args <- commandArgs(FALSE)
.file <- sub("^--file=", "", grep("^--file=", .args, value = TRUE))
if (length(.file) == 1 && nzchar(.file)) setwd(dirname(normalizePath(.file)))

# 1) Reproducir paquetes de R con renv (si está inicializado).
if (file.exists("renv/activate.R")) {
  source("renv/activate.R")
  if (requireNamespace("renv", quietly = TRUE)) {
    tryCatch(renv::restore(prompt = FALSE),
             error = function(e) message("Aviso: renv::restore falló: ", conditionMessage(e)))
  }
}

# 2) Bootstrap del entorno Python del proyecto (core+text por defecto).
source("R/portability.R")
source("setup_python.R")
tryCatch(
  oralstats_bootstrap(level = Sys.getenv("ORALSTATS_PY_LEVEL", "text")),
  error = function(e) message("Aviso: bootstrap de Python falló (la app arrancará igual): ",
                              conditionMessage(e))
)

# 3) Arrancar la app (app.R en este directorio).
shiny::runApp(".", launch.browser = TRUE)
