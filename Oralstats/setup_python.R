# Bootstrap del entorno Python del proyecto para OralStats.
# Crea (si no existe) el virtualenv del proyecto e instala los niveles indicados.
# Como script:  Rscript setup_python.R [core|text|asr|all]
# Sourceado desde run.R:  oralstats_bootstrap("text")

if (!exists("ORALSTATS_VENV")) source("R/portability.R")

# ── Selección de un Python compatible para CREAR el venv del proyecto ──────────
# La pila ML (torch, tokenizers, whisperx) solo tiene wheels fiables hasta 3.12;
# en 3.13+/3.14 pip intenta compilar desde fuente y falla sin toolchains (Rust…).
.ORALSTATS_PY_MIN <- c(3L, 9L)
.ORALSTATS_PY_MAX <- c(3L, 12L)

# (major, minor) de un intérprete, o NULL si no se puede determinar.
.oralstats_py_version <- function(py) {
  # print(a, b) -> "3 12"; sin comillas en el snippet para evitar líos de quoting
  # en el shell (system2 no entrecomilla; usamos shQuote como en el resto del código).
  v <- tryCatch(
    system2(py, c("-c", shQuote("import sys; print(sys.version_info[0], sys.version_info[1])")),
            stdout = TRUE, stderr = FALSE),
    error = function(e) character(0)
  )
  if (length(v) != 1) return(NULL)
  parts <- strsplit(trimws(v), "\\s+")[[1]]
  if (length(parts) != 2 || !all(grepl("^[0-9]+$", parts))) return(NULL)
  as.integer(parts)
}

.oralstats_py_compatible <- function(ver) {
  if (is.null(ver)) return(FALSE)
  ge <- ver[1] > .ORALSTATS_PY_MIN[1] ||
        (ver[1] == .ORALSTATS_PY_MIN[1] && ver[2] >= .ORALSTATS_PY_MIN[2])
  le <- ver[1] < .ORALSTATS_PY_MAX[1] ||
        (ver[1] == .ORALSTATS_PY_MAX[1] && ver[2] <= .ORALSTATS_PY_MAX[2])
  ge && le
}

# Elige un intérprete Python 3.9-3.12 sobre el que basar el venv del proyecto.
# Prioridad: $ORALSTATS_PYTHON -> python3.12/3.11/3.10/3.9 del PATH -> python3/python.
# Devuelve la ruta, o NA_character_ si no hay ninguno compatible.
oralstats_choose_python <- function() {
  override <- Sys.getenv("ORALSTATS_PYTHON", "")
  if (nzchar(override)) {
    if (file.exists(override) && .oralstats_py_compatible(.oralstats_py_version(override))) {
      return(override)
    }
    warning("ORALSTATS_PYTHON='", override, "' no existe o no es Python 3.9-3.12; se ignora.")
  }
  for (name in c("python3.12", "python3.11", "python3.10", "python3.9", "python3", "python")) {
    p <- Sys.which(name)
    if (nzchar(p) && .oralstats_py_compatible(.oralstats_py_version(p))) return(unname(p))
  }
  NA_character_
}

oralstats_bootstrap <- function(level = "text") {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("Falta el paquete R 'reticulate' (ejecuta renv::restore()).")
  }
  if (!reticulate::virtualenv_exists(ORALSTATS_VENV)) {
    py_base <- oralstats_choose_python()
    if (is.na(py_base)) {
      warning("No se encontró Python 3.9-3.12. Los niveles 2/3 (torch/whisperx) ",
              "pueden fallar al no haber wheels para Python muy reciente (3.13+/3.14). ",
              "Instala Python 3.12 (o define ORALSTATS_PYTHON=/ruta/a/python3.12). ",
              "Creando el venv con el Python por defecto de reticulate…")
      reticulate::virtualenv_create(ORALSTATS_VENV)
    } else {
      message("Creando virtualenv del proyecto: ", ORALSTATS_VENV, " (Python: ", py_base, ")")
      reticulate::virtualenv_create(ORALSTATS_VENV, python = py_base)
    }
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
