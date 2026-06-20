# Portabilidad de OralStats — Plan de Implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hacer que OralStats se instale y arranque de forma reproducible en macOS, Windows y Linux, con todas las funciones de Python y Praat usables, y disponer de una prueba de instalación en limpio.

**Architecture:** `renv` fija los paquetes de R; `reticulate` gestiona un virtualenv de Python **propio del proyecto** (`oralstats-env`) declarado en tres `requirements-*.txt` por niveles. Helpers de R en `R/portability.R` resuelven el intérprete Python y detectan binarios de sistema. Un `run.R` reproduce el entorno y arranca la app. La prueba en limpio se hace con un script reversible en el Mac y con un `Dockerfile` que construye desde cero.

**Tech Stack:** R (Shiny, renv, reticulate, testthat), Python ≥3.9 (virtualenv + pip), Docker, bash.

## Global Constraints

- Plataformas objetivo: **macOS, Windows, Linux** — todo código de detección de rutas debe contemplar las tres (`.Platform$OS.type`, `Sys.info()[["sysname"]]`).
- Python mínimo: **3.9**.
- **Nivel 1 (parselmouth + tgt) siempre garantizado.** Los niveles 2 (`pysentimiento`, `funasr`, `soundfile`) y 3 (`whisperx`, `pyannote.audio`) **no deben impedir el arranque** si fallan o faltan.
- **No romper instalaciones existentes:** la resolución de Python debe mantener *fallback* a `~/.virtualenvs/bert-env` y al `python3` del PATH.
- El arranque debe abrir la app con **un único comando** (`Rscript run.R`).
- Todos los scripts asumen el directorio de trabajo `Oralstats/`.
- Nombre del virtualenv del proyecto: **`oralstats-env`** (constante `ORALSTATS_VENV`).

---

## File Structure

- Create: `Oralstats/R/portability.R` — helpers: `ORALSTATS_VENV`, `oralstats_python()`, `check_system_deps()`.
- Create: `Oralstats/requirements-core.txt` / `requirements-text.txt` / `requirements-asr.txt` — dependencias Python por nivel.
- Create: `Oralstats/setup_python.R` — `oralstats_bootstrap(level)` + tail ejecutable como script.
- Create: `Oralstats/run.R` — lanzador único (renv restore → bootstrap → runApp).
- Create: `Oralstats/tests/test_portability.R` — test de los helpers.
- Create: `Oralstats/Dockerfile` + `Oralstats/.dockerignore` — imagen reproducible / prueba en limpio.
- Create: `Oralstats/test_clean_install.sh` — prueba en limpio reversible en el Mac.
- Create: `Oralstats/renv.lock`, `Oralstats/renv/activate.R`, `Oralstats/.Rprofile` — generados por `renv::init()`.
- Modify: `Oralstats/app.R` — sourcear `R/portability.R`; usar `oralstats_python()` en `.python_venv_path`; ampliar `run_diagnostico()`; botones de instalación por nivel.
- Modify: `README.md:174` — corregir el arranque (`Oralstats.R` → `run.R` / `runApp("Oralstats")`).

---

## Task 1: Reproducibilidad de R con renv

**Files:**
- Create: `Oralstats/renv.lock`, `Oralstats/renv/activate.R`, `Oralstats/.Rprofile` (vía `renv::init()`)
- Modify: ninguno manual (renv autodetecta)

**Interfaces:**
- Consumes: nada.
- Produces: `renv.lock` con versiones exactas; activación automática vía `.Rprofile` → `renv/activate.R`. Tareas posteriores asumen que `reticulate`, `testthat`, `shiny` y los paquetes obligatorios están en el lock.

- [ ] **Step 1: Inicializar renv en el proyecto**

Run (desde `Oralstats/`):
```bash
Rscript -e "install.packages('renv', repos='https://cloud.r-project.org'); renv::init(bare = FALSE)"
```
Expected: crea `renv/`, `.Rprofile` y un `renv.lock` inicial; renv escanea el código y detecta dependencias.

- [ ] **Step 2: Asegurar dependencias que renv puede no autodetectar**

`renv` a veces no captura paquetes cargados solo vía `requireNamespace()` o que se necesitan en tiempo de ejecución. Forzar su inclusión:
```bash
Rscript -e "renv::install(c('reticulate','testthat','readxl','irr','httr','ggwordcloud','partykit','ggparty','randomForest','praatpicture','rPraat','pagedown','base64enc','stopwords','av'))"
```
Expected: instala y deja disponibles esos paquetes en la librería de renv.

- [ ] **Step 3: Snapshot del lockfile**

Run:
```bash
Rscript -e "renv::snapshot(prompt = FALSE)"
```
Expected: `renv.lock` actualizado con todas las versiones.

- [ ] **Step 4: Verificar que restore funciona en limpio**

Run:
```bash
Rscript -e "renv::status()"
```
Expected: mensaje "The project is already synchronised with the lockfile." (o equivalente sin discrepancias).

- [ ] **Step 5: Commit**

```bash
git add Oralstats/renv.lock Oralstats/renv/activate.R Oralstats/.Rprofile Oralstats/renv/settings.json Oralstats/.gitignore
git commit -m "build: reproducibilidad de R con renv (renv.lock)"
```

---

## Task 2: Requirements de Python por niveles + bootstrap con reticulate

**Files:**
- Create: `Oralstats/requirements-core.txt`, `requirements-text.txt`, `requirements-asr.txt`
- Create: `Oralstats/R/portability.R` (solo `ORALSTATS_VENV` + `oralstats_python()` en esta tarea; `check_system_deps()` se añade en Task 3)
- Create: `Oralstats/setup_python.R`

**Interfaces:**
- Consumes: `reticulate` (de Task 1).
- Produces:
  - Constante `ORALSTATS_VENV <- "oralstats-env"`.
  - `oralstats_python()` → `character(1)`: ruta al intérprete Python a usar, o `NA_character_`.
  - `oralstats_bootstrap(level = c("core","text","asr","all"))` → `invisible(character(1))`: crea el venv si falta e instala los requirements del nivel. Idempotente.

- [ ] **Step 1: Crear los tres ficheros de requirements**

`Oralstats/requirements-core.txt`:
```
praat-parselmouth
tgt
```

`Oralstats/requirements-text.txt`:
```
pysentimiento
funasr
soundfile
```

`Oralstats/requirements-asr.txt`:
```
whisperx
pyannote.audio
```

- [ ] **Step 2: Escribir el test de `oralstats_python()` (falla primero)**

`Oralstats/tests/test_portability.R`:
```r
# Test de los helpers de portabilidad. Ejecutar desde Oralstats/:
#   Rscript tests/test_portability.R
source("R/portability.R")

# oralstats_python() devuelve NA o la ruta a un intérprete existente
py <- oralstats_python()
stopifnot(length(py) == 1L)
stopifnot(is.na(py) || file.exists(py))

cat("OK: oralstats_python\n")
```

- [ ] **Step 3: Ejecutar el test para verificar que falla**

Run (desde `Oralstats/`):
```bash
Rscript tests/test_portability.R
```
Expected: FALLA con error "cannot open file 'R/portability.R'" (el helper aún no existe).

- [ ] **Step 4: Implementar `R/portability.R` (constante + `oralstats_python()`)**

`Oralstats/R/portability.R`:
```r
# Helpers de portabilidad de OralStats.

# Nombre del virtualenv propio del proyecto (gestionado por reticulate).
ORALSTATS_VENV <- "oralstats-env"

# Devuelve la ruta al intérprete Python que debe usar OralStats.
# Prioridad: (1) venv del proyecto (reticulate),
#            (2) ~/.virtualenvs/bert-env  (compatibilidad hacia atrás),
#            (3) python3/python del PATH.
# Devuelve NA_character_ si no hay ninguno.
oralstats_python <- function() {
  # (1) venv del proyecto gestionado por reticulate
  if (requireNamespace("reticulate", quietly = TRUE) &&
      isTRUE(tryCatch(reticulate::virtualenv_exists(ORALSTATS_VENV),
                      error = function(e) FALSE))) {
    proj <- tryCatch(reticulate::virtualenv_python(ORALSTATS_VENV),
                     error = function(e) NA_character_)
    if (!is.na(proj) && nzchar(proj) && file.exists(proj)) return(proj)
  }

  # (2) bert-env heredado
  home <- Sys.getenv("HOME"); if (!nzchar(home)) home <- Sys.getenv("USERPROFILE")
  legacy <- if (.Platform$OS.type == "windows") {
    file.path(home, ".virtualenvs", "bert-env", "Scripts", "python.exe")
  } else {
    file.path(home, ".virtualenvs", "bert-env", "bin", "python3")
  }
  if (file.exists(legacy)) return(legacy)

  # (3) PATH
  for (cand in c(Sys.which("python3"), Sys.which("python"))) {
    if (nzchar(cand) && file.exists(cand)) return(unname(cand))
  }
  NA_character_
}
```

- [ ] **Step 5: Ejecutar el test para verificar que pasa**

Run (desde `Oralstats/`):
```bash
Rscript tests/test_portability.R
```
Expected: imprime `OK: oralstats_python` y sale con código 0.

- [ ] **Step 6: Implementar `setup_python.R` (bootstrap)**

`Oralstats/setup_python.R`:
```r
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
```

- [ ] **Step 7: Verificar el bootstrap del nivel core**

Run (desde `Oralstats/`):
```bash
Rscript setup_python.R core
Rscript -e "source('R/portability.R'); py <- oralstats_python(); cat(py, '\n'); system2(py, c('-c','import parselmouth, tgt; print(\"nivel-core OK\")'))"
```
Expected: crea `oralstats-env`, instala parselmouth+tgt e imprime `nivel-core OK`.

- [ ] **Step 8: Commit**

```bash
git add Oralstats/requirements-core.txt Oralstats/requirements-text.txt Oralstats/requirements-asr.txt Oralstats/R/portability.R Oralstats/setup_python.R Oralstats/tests/test_portability.R
git commit -m "feat: venv del proyecto por niveles con reticulate (bootstrap)"
```

---

## Task 3: Detección de binarios de sistema (`check_system_deps()`)

**Files:**
- Modify: `Oralstats/R/portability.R` (añadir `check_system_deps()`)
- Modify: `Oralstats/tests/test_portability.R` (añadir asserts)

**Interfaces:**
- Consumes: nada nuevo.
- Produces: `check_system_deps()` → lista nombrada `{praat, ffmpeg, pandoc, chrome}`, cada uno `list(found = logical(1), path = character(1) | NA, hint = character(1))`.

- [ ] **Step 1: Añadir el test (falla primero)**

Añadir al final de `Oralstats/tests/test_portability.R`, antes del `cat(...)` final:
```r
# check_system_deps() devuelve la estructura esperada
deps <- check_system_deps()
stopifnot(all(c("praat", "ffmpeg", "pandoc", "chrome") %in% names(deps)))
for (d in deps) {
  stopifnot(all(c("found", "path", "hint") %in% names(d)))
  stopifnot(is.logical(d$found), length(d$found) == 1L)
}
cat("OK: check_system_deps\n")
```

- [ ] **Step 2: Ejecutar el test para verificar que falla**

Run (desde `Oralstats/`):
```bash
Rscript tests/test_portability.R
```
Expected: FALLA con "could not find function \"check_system_deps\"".

- [ ] **Step 3: Implementar `check_system_deps()`**

Añadir a `Oralstats/R/portability.R`:
```r
# Detecta binarios de sistema externos que OralStats puede usar.
# Devuelve list(praat=, ffmpeg=, pandoc=, chrome=), cada uno list(found, path, hint).
check_system_deps <- function() {
  os <- if (.Platform$OS.type == "windows") "windows"
        else if (Sys.info()[["sysname"]] == "Darwin") "macos"
        else "linux"

  first_existing <- function(cands) {
    cands <- cands[nzchar(cands)]
    hit <- cands[file.exists(cands)]
    if (length(hit)) unname(hit[[1]]) else NA_character_
  }

  praat <- first_existing(c(
    Sys.which("praat"),
    "/Applications/Praat.app/Contents/MacOS/Praat",
    "/usr/bin/praat", "/usr/local/bin/praat",
    "C:/Program Files/Praat/Praat.exe",
    "C:/Program Files (x86)/Praat/Praat.exe"
  ))
  ffmpeg <- first_existing(Sys.which("ffmpeg"))
  pandoc <- first_existing(c(Sys.which("pandoc"),
                             Sys.getenv("RSTUDIO_PANDOC")))
  chrome <- first_existing(c(
    Sys.which("google-chrome"), Sys.which("chromium"),
    Sys.which("chromium-browser"),
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "C:/Program Files/Google/Chrome/Application/chrome.exe"
  ))

  hints <- list(
    praat = c(macos = "brew install --cask praat  (o praat.org)",
              windows = "Descarga Praat.exe de praat.org y añádelo al PATH",
              linux = "sudo apt install praat  (o praat.org)"),
    ffmpeg = c(macos = "brew install ffmpeg",
               windows = "choco install ffmpeg  (o ffmpeg.org)",
               linux = "sudo apt install ffmpeg"),
    pandoc = c(macos = "brew install pandoc",
               windows = "choco install pandoc",
               linux = "sudo apt install pandoc"),
    chrome = c(macos = "Instala Google Chrome (necesario solo para informes PDF)",
               windows = "Instala Google Chrome (necesario solo para informes PDF)",
               linux = "sudo apt install chromium-browser")
  )

  mk <- function(name, path) {
    list(found = !is.na(path) && nzchar(path),
         path  = path,
         hint  = unname(hints[[name]][[os]]))
  }

  list(
    praat  = mk("praat",  praat),
    ffmpeg = mk("ffmpeg", ffmpeg),
    pandoc = mk("pandoc", pandoc),
    chrome = mk("chrome", chrome)
  )
}
```

- [ ] **Step 4: Ejecutar el test para verificar que pasa**

Run (desde `Oralstats/`):
```bash
Rscript tests/test_portability.R
```
Expected: imprime `OK: oralstats_python`, `OK: check_system_deps` y sale con código 0.

- [ ] **Step 5: Commit**

```bash
git add Oralstats/R/portability.R Oralstats/tests/test_portability.R
git commit -m "feat: check_system_deps() para praat/ffmpeg/pandoc/chrome"
```

---

## Task 4: Integrar helpers en app.R (resolución Python + diagnóstico por niveles)

**Files:**
- Modify: `Oralstats/app.R` (sourcear helper cerca de las `library(...)`; reescribir `.python_venv_path`; ampliar `run_diagnostico()`; botones de instalación)

**Interfaces:**
- Consumes: `oralstats_python()`, `check_system_deps()`, `oralstats_bootstrap()` (Tasks 2-3).
- Produces: la app usa el intérprete del venv del proyecto con fallback; el diagnóstico refleja niveles y binarios.

- [ ] **Step 1: Sourcear los helpers junto al bloque de `library(...)`**

En `Oralstats/app.R`, tras la última `library(...)` del bloque de cabecera (alrededor de la línea 45, después de `requireNamespace("praatpicture", quietly = TRUE)`), añadir:
```r
# Helpers de portabilidad (intérprete Python del proyecto + binarios de sistema).
if (file.exists("R/portability.R")) source("R/portability.R")
```

- [ ] **Step 2: Reemplazar el bloque `.python_venv_path` / `.python_sys_candidates`**

En `Oralstats/app.R` localizar este bloque (≈ líneas 4851-4867):
```r
  # ── Helper: ruta al Python del virtualenv bert-env (cross-platform) ──────────
  # Windows: Scripts\python.exe  |  Unix/Mac: bin/python3
  .python_venv_path <- local({
    home <- Sys.getenv("HOME")
    if (nchar(home) == 0) home <- Sys.getenv("USERPROFILE")  # Windows fallback
    if (.Platform$OS.type == "windows") {
      file.path(home, ".virtualenvs", "bert-env", "Scripts", "python.exe")
    } else {
      file.path(home, ".virtualenvs", "bert-env", "bin", "python3")
    }
  })
  # Candidatos adicionales de Python en Windows (python.exe vs python3)
  .python_sys_candidates <- if (.Platform$OS.type == "windows") {
    c(Sys.which("python3"), Sys.which("python"))
  } else {
    c(Sys.which("python3"), "/usr/local/bin/python3", "/usr/bin/python3")
  }
```
y sustituirlo por:
```r
  # ── Intérprete Python del proyecto (reticulate) con fallback ────────────────
  # oralstats_python() (R/portability.R) prioriza el venv del proyecto
  # 'oralstats-env', luego ~/.virtualenvs/bert-env, luego el PATH.
  .python_venv_path <- if (exists("oralstats_python")) {
    tryCatch(oralstats_python(), error = function(e) NA_character_)
  } else {
    NA_character_
  }
  # Candidatos adicionales de Python (fallback si el venv del proyecto falla)
  .python_sys_candidates <- if (.Platform$OS.type == "windows") {
    c(Sys.which("python3"), Sys.which("python"))
  } else {
    c(Sys.which("python3"), "/usr/local/bin/python3", "/usr/bin/python3")
  }
```
(El resto del código que recorre `c(.python_venv_path, .python_sys_candidates)` sigue funcionando sin cambios.)

- [ ] **Step 3: Ampliar `run_diagnostico()` con binarios de sistema**

En `Oralstats/app.R`, en `run_diagnostico()` (≈ línea 4893), sustituir el cálculo de `ffmpeg_ok` y la lista de retorno por una versión que use `check_system_deps()`:
```r
    sysdeps <- if (exists("check_system_deps")) check_system_deps() else
      list(praat = list(found = FALSE), ffmpeg = list(found = FALSE),
           pandoc = list(found = FALSE), chrome = list(found = FALSE))

    list(
      py_bin       = if (!is.na(py_bin)) py_bin else "(no encontrado)",
      parselmouth  = check_lib("parselmouth"),     # nivel 1
      tgt          = check_lib("tgt"),              # nivel 1
      pysentimiento = check_lib("pysentimiento"),  # nivel 2
      funasr       = check_lib("funasr"),          # nivel 2
      soundfile    = check_lib("soundfile"),       # nivel 2
      whisperx     = check_lib("whisperx"),        # nivel 3
      pyannote     = check_lib("pyannote.audio"),  # nivel 3
      praat        = if (sysdeps$praat$found)  "OK" else "NO",
      ffmpeg       = if (sysdeps$ffmpeg$found) "OK" else "NO",
      pandoc       = if (sysdeps$pandoc$found) "OK" else "NO",
      chrome       = if (sysdeps$chrome$found) "OK" else "NO",
      ts           = format(Sys.time(), "%H:%M:%S")
    )
```

- [ ] **Step 4: Añadir botones de instalación por nivel en la pestaña "Dependencias Python"**

En `Oralstats/app.R`, en el `card-body` del panel de diagnóstico (justo después del `actionButton("btn_diagnostico_python", ...)`, ≈ línea 4618), añadir:
```r
            tags$div(class = "mt-2 d-flex gap-2 flex-wrap",
              actionButton("btn_instalar_nivel2", "Instalar Texto/Emoción (nivel 2)",
                           class = "btn-sm btn-outline-warning"),
              actionButton("btn_instalar_nivel3", "Instalar Transcripción (nivel 3)",
                           class = "btn-sm btn-outline-success")
            ),
```

- [ ] **Step 5: Añadir los `observeEvent` que lanzan la instalación en segundo plano**

En `Oralstats/app.R`, junto al `observeEvent(input$btn_diagnostico_python, ...)` (≈ línea 4905), añadir:
```r
  lanzar_instalacion <- function(nivel) {
    rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
    system2(rscript, c("setup_python.R", nivel), wait = FALSE)
    showNotification(
      paste0("Instalando nivel '", nivel, "' en segundo plano. Puede tardar varios minutos; ",
             "pulsa 'Verificar ahora' cuando termine."),
      type = "message", duration = 12
    )
  }
  observeEvent(input$btn_instalar_nivel2, lanzar_instalacion("text"))
  observeEvent(input$btn_instalar_nivel3, lanzar_instalacion("asr"))
```

- [ ] **Step 6: Verificar que la app arranca y el diagnóstico no rompe**

Run (desde `Oralstats/`):
```bash
Rscript -e "options(shiny.port=7891); source('R/portability.R'); print(check_system_deps()); cat('helpers OK\n')"
Rscript -e "shiny::runApp('.', launch.browser = FALSE, port = 7891)" &
sleep 8 && curl -sSf http://127.0.0.1:7891 >/dev/null && echo "APP ARRANCA OK"; kill %1 2>/dev/null
```
Expected: imprime la estructura de `check_system_deps`, `helpers OK` y `APP ARRANCA OK`.

- [ ] **Step 7: Commit**

```bash
git add Oralstats/app.R
git commit -m "feat: app usa venv del proyecto y diagnóstico por niveles + binarios"
```

---

## Task 5: Lanzador único `run.R` y corrección del README

**Files:**
- Create: `Oralstats/run.R`
- Modify: `README.md:174`

**Interfaces:**
- Consumes: `R/portability.R`, `setup_python.R`, `app.R`.
- Produces: `Rscript run.R` reproduce el entorno y abre la app.

- [ ] **Step 1: Crear `run.R`**

`Oralstats/run.R`:
```r
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
```

- [ ] **Step 2: Verificar que `run.R` arranca la app**

Run (desde `Oralstats/`):
```bash
ORALSTATS_PY_LEVEL=core Rscript run.R &
sleep 15 && curl -sSf http://127.0.0.1:$(Rscript -e "cat(getOption('shiny.port', 3838))" 2>/dev/null || echo 3838) >/dev/null 2>&1; echo "run.R lanzado"; kill %1 2>/dev/null
```
Expected: la app levanta sin error fatal (se ve la salida de renv/bootstrap y el arranque de Shiny). Cerrar con Ctrl-C / kill.

- [ ] **Step 3: Corregir el README**

En `README.md`, sustituir la línea:
```
   shiny::runApp("Oralstats/Oralstats.R")   # Oralstats v1.8
```
por:
```
   # Primera vez (reproduce el entorno R + Python y arranca):
   Rscript Oralstats/run.R                   # Oralstats v1.8
   # (o, si ya tienes el entorno listo:)  shiny::runApp("Oralstats")
```

- [ ] **Step 4: Commit**

```bash
git add Oralstats/run.R README.md
git commit -m "feat: lanzador único run.R y corrección del arranque en README"
```

---

## Task 6: Prueba en limpio reversible en el Mac (`test_clean_install.sh`)

**Files:**
- Create: `Oralstats/test_clean_install.sh`

**Interfaces:**
- Consumes: `run.R` (Task 5).
- Produces: script que simula instalación desde cero sin contaminar el entorno real.

- [ ] **Step 1: Crear el script**

`Oralstats/test_clean_install.sh`:
```bash
#!/usr/bin/env bash
# Prueba de instalación en limpio de OralStats SIN contaminar el entorno real.
# Oculta temporalmente el venv heredado y aísla la caché de renv, reproduce desde
# cero en una copia temporal del repo y arranca la app. Restaura todo al salir.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"          # .../Oralstats
TMP="$(mktemp -d)"
echo ">> Carpeta temporal: $TMP"

# Aislar la caché de renv para no reutilizar librerías ya compiladas.
export RENV_PATHS_ROOT="$TMP/renv-root"

# 1) Ocultar (reversible) el venv heredado bert-env y el venv del proyecto.
BERT="$HOME/.virtualenvs/bert-env"
PROJ="$HOME/.virtualenvs/oralstats-env"
BERT_BAK=""; PROJ_BAK=""
[ -d "$BERT" ] && BERT_BAK="$BERT.cleanbak.$$" && mv "$BERT" "$BERT_BAK" && echo ">> bert-env ocultado"
[ -d "$PROJ" ] && PROJ_BAK="$PROJ.cleanbak.$$" && mv "$PROJ" "$PROJ_BAK" && echo ">> oralstats-env ocultado"

restore() {
  [ -n "$BERT_BAK" ] && [ -d "$BERT_BAK" ] && mv "$BERT_BAK" "$BERT" && echo ">> bert-env restaurado"
  [ -n "$PROJ_BAK" ] && [ -d "$PROJ_BAK" ] && mv "$PROJ_BAK" "$PROJ" && echo ">> oralstats-env restaurado"
  echo ">> Copia temporal conservada en $TMP (bórrala con: rm -rf \"$TMP\")"
}
trap restore EXIT

# 2) Copiar el repo a la carpeta temporal (sin librerías ni caches).
rsync -a --exclude 'renv/library' --exclude 'renv/python' --exclude '.git' \
      "$REPO_ROOT/" "$TMP/Oralstats/"

# 3) Reproducir desde cero y arrancar.
cd "$TMP/Oralstats"
Rscript -e "install.packages('renv', repos='https://cloud.r-project.org'); renv::restore(prompt = FALSE)"
echo ">> Arrancando OralStats desde cero. Revisa el checklist de smoke-test del spec."
Rscript run.R
```

- [ ] **Step 2: Hacerlo ejecutable**

Run (desde `Oralstats/`):
```bash
chmod +x test_clean_install.sh
```

- [ ] **Step 3: Verificar sintaxis del script**

Run:
```bash
bash -n test_clean_install.sh && echo "SINTAXIS OK"
```
Expected: imprime `SINTAXIS OK` (no ejecuta la instalación completa, solo valida la sintaxis).

- [ ] **Step 4: Commit**

```bash
git add Oralstats/test_clean_install.sh
git commit -m "test: script de instalación en limpio reversible (macOS/Linux)"
```

---

## Task 7: Dockerfile reproducible (prueba en limpio garantizada / opción sin R)

**Files:**
- Create: `Oralstats/Dockerfile`, `Oralstats/.dockerignore`

**Interfaces:**
- Consumes: `renv.lock`, `R/portability.R`, `setup_python.R`, `app.R`.
- Produces: imagen que construye el entorno desde cero y sirve la app en el puerto 3838.

- [ ] **Step 1: Crear `.dockerignore`**

`Oralstats/.dockerignore`:
```
renv/library/
renv/python/
.git/
*.Rproj.user
.DS_Store
samples/
```

- [ ] **Step 2: Crear el `Dockerfile`**

`Oralstats/Dockerfile`:
```dockerfile
# OralStats — imagen reproducible (R + Python + Praat + ffmpeg + pandoc).
FROM rocker/shiny:4.4.1

# Binarios de sistema. NOTA: si 'praat' no está en los repos de la base,
# descárgalo de praat.org (binario estático) y colócalo en /usr/local/bin/praat.
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-pip \
      ffmpeg pandoc \
      libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv/oralstats
COPY . /srv/oralstats

# Paquetes de R vía renv.
RUN R -e "install.packages('renv', repos='https://cloud.r-project.org')" \
 && R -e "renv::restore(prompt = FALSE)"

# Entorno Python del proyecto (nivel core+text).
RUN R -e "setwd('/srv/oralstats'); source('R/portability.R'); source('setup_python.R'); oralstats_bootstrap('text')"

EXPOSE 3838
CMD ["R", "-e", "shiny::runApp('/srv/oralstats', host = '0.0.0.0', port = 3838)"]
```

- [ ] **Step 3: Construir la imagen (prueba en limpio reproducible)**

Run (desde `Oralstats/`):
```bash
docker build -t oralstats:test .
```
Expected: build completo sin error. (Si `praat` no estaba disponible, la app igualmente arranca: Praat es opcional.)

- [ ] **Step 4: Arrancar el contenedor y comprobar que responde**

Run:
```bash
docker run --rm -d -p 3838:3838 --name oralstats_test oralstats:test
sleep 20 && curl -sSf http://127.0.0.1:3838 >/dev/null && echo "CONTENEDOR OK"
docker stop oralstats_test
```
Expected: imprime `CONTENEDOR OK`.

- [ ] **Step 5: Commit**

```bash
git add Oralstats/Dockerfile Oralstats/.dockerignore
git commit -m "build: Dockerfile reproducible (R+Python+ffmpeg+pandoc)"
```

---

## Task 8 (opcional): CI multi-SO de instalación en limpio

**Files:**
- Create: `.github/workflows/clean-install.yml`

**Interfaces:**
- Consumes: `renv.lock`, `run.R`, `tests/test_portability.R`.
- Produces: verificación automática en macOS, Windows y Ubuntu de que el entorno se reproduce y los helpers pasan.

- [ ] **Step 1: Crear el workflow**

`.github/workflows/clean-install.yml`:
```yaml
name: clean-install
on:
  workflow_dispatch:
  push:
    branches: [ portabilidad-oralstats ]

jobs:
  reproduce:
    strategy:
      fail-fast: false
      matrix:
        os: [ macos-latest, windows-latest, ubuntu-latest ]
    runs-on: ${{ matrix.os }}
    defaults:
      run:
        working-directory: Oralstats
    steps:
      - uses: actions/checkout@v4
      - uses: r-lib/actions/setup-r@v2
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - name: Restaurar paquetes R
        run: Rscript -e "install.packages('renv', repos='https://cloud.r-project.org'); renv::restore(prompt = FALSE)"
      - name: Bootstrap Python (core)
        run: Rscript setup_python.R core
      - name: Test de helpers de portabilidad
        run: Rscript tests/test_portability.R
```

- [ ] **Step 2: Verificar sintaxis YAML**

Run (desde la raíz del repo):
```bash
Rscript -e "yaml::yaml.load_file('.github/workflows/clean-install.yml'); cat('YAML OK\n')"
```
Expected: imprime `YAML OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/clean-install.yml
git commit -m "ci: instalación en limpio multi-SO (macOS/Windows/Ubuntu)"
```

---

## Self-Review

**Spec coverage:**
- A (renv) → Task 1. ✓
- B (venv del proyecto vía reticulate, requirements por niveles, refactor del intérprete) → Tasks 2 y 4. ✓
- C (check_system_deps + guía por SO) → Task 3 (+ mostrado en Task 4). ✓
- D (run.R + fix README) → Task 5. ✓
- E (prueba en limpio manual + Docker + CI opcional) → Tasks 6, 7, 8. ✓
- F (diagnóstico por niveles + botones de instalación) → Task 4 (steps 3-5). ✓
- Checklist de smoke-test del spec §4 → referenciado en Task 6 step 3.

**Placeholder scan:** sin TBD/TODO; todos los pasos de código muestran el código completo. ✓

**Type consistency:** `ORALSTATS_VENV`, `oralstats_python()`, `oralstats_bootstrap(level)`, `check_system_deps()` (claves `found`/`path`/`hint`) se usan con los mismos nombres y firmas en Tasks 2, 3, 4, 5, 7. ✓
