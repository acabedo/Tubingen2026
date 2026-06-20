# Bootstrap del entorno Python del proyecto para OralStats.
# Crea (si no existe) el virtualenv del proyecto e instala los niveles indicados.
# Como script:  Rscript setup_python.R [core|text|asr|all]
# Sourceado desde run.R:  oralstats_bootstrap("text")

if (!exists("ORALSTATS_VENV")) source("R/portability.R")

oralstats_bootstrap <- function(level = "text") {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("Falta el paquete R 'reticulate' (ejecuta renv::restore()).")
  }
  if (!reticulate::virtualenv_exists(ORALSTATS_VENV)) {
    message("Creando virtualenv del proyecto: ", ORALSTATS_VENV)
    reticulate::virtualenv_create(ORALSTATS_VENV)
  }
  py <- reticulate::virtualenv_python(ORALSTATS_VENV)

  reqs <- switch(level,
    core = "requirements-core.txt",
    text = c("requirements-core.txt", "requirements-text.txt"),
    asr  = c("requirements-core.txt", "requirements-text.txt", "requirements-asr.txt"),
    all  = c("requirements-core.txt", "requirements-text.txt", "requirements-asr.txt"),
    stop("Nivel desconocido: ", level)
  )

  system2(py, c("-m", "pip", "install", "--upgrade", "pip"))
  for (r in reqs) {
    if (!file.exists(r)) {
      stop("No se encuentra ", r, " (¿ejecutas desde la carpeta Oralstats/?)")
    }
    message("Instalando ", r, " …")
    status <- system2(py, c("-m", "pip", "install", "-r", r))
    if (!identical(status, 0L)) {
      warning("Fallo instalando ", r, " (status ", status, ").")
    }
  }
  invisible(py)
}

# Tail ejecutable: solo actúa si se invoca como `Rscript setup_python.R <nivel>`.
local({
  a <- commandArgs(trailingOnly = TRUE)
  if (length(a) >= 1 && a[[1]] %in% c("core", "text", "asr", "all")) {
    oralstats_bootstrap(a[[1]])
  }
})
