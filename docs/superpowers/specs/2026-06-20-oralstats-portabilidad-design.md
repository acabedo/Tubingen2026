# Diseño: Portabilidad y prueba en limpio de OralStats

**Fecha:** 2026-06-20
**Autor:** Adrián Cabedo Nebot (con Claude)
**Ámbito:** `Oralstats/` (app Shiny en R que invoca Python, Praat y binarios de sistema)

---

## 1. Problema

OralStats funciona en la máquina de desarrollo pero su portabilidad es frágil. El
objetivo es **garantizar que la app se abra y funcione en cualquier sistema
operativo (macOS, Windows, Linux)**, que **todas las opciones de Python y de Praat
sean usables**, y disponer de un **procedimiento para probarla en limpio** (como si
se descargara por primera vez) sin contaminar el entorno de desarrollo.

### Puntos frágiles detectados en el estado actual

- **R sin fijar versiones.** ~18 paquetes obligatorios (`shiny`, `bslib`,
  `shinyjs`, `ggplot2`, `dplyr`, `tidyr`, `DT`, `av`, `plotly`, `RColorBrewer`,
  `data.table`, `mgcv`, `ggeffects`, `ggfun`, `jsonlite`, `seewave`, `tuneR`,
  `udpipe`) más decenas de opcionales vía `requireNamespace()` (`readxl`, `irr`,
  `httr`, `ggwordcloud`, `partykit`, `ggparty`, `randomForest`, `praatpicture`,
  `rPraat`, `pagedown`, `base64enc`, `stopwords`, `audio.whisper`, `whisper`…).
  No hay `renv.lock` ni `DESCRIPTION`: nada reproduce el entorno.
- **Python por venv global y descubrimiento frágil.** La app NO usa `reticulate`:
  llama por `system2()` a un intérprete que busca en `~/.virtualenvs/bert-env`
  (`.python_venv_path`, `app.R:4853`) y, si no, en `Sys.which("python3")` y rutas
  fijas (`.python_sys_candidates`, `app.R:4863`). El usuario debe crear ese venv a
  mano; no hay versiones fijadas ni `requirements.txt`.
- **Praat externo opcional pero por rutas fijas.** Se localiza con
  `Sys.which("praat")` + rutas hardcodeadas por SO (`.praat_bin_cached`,
  `app.R:11906`). Solo lo necesita el modo "Script Praat"; existen dos
  alternativas (R nativo con `seewave`/`tuneR`, y Parselmouth).
- **Binarios de sistema asumidos:** `ffmpeg`, `pandoc`, Chrome/`wkhtmltopdf` (para
  informes PDF). Ni renv ni reticulate los gestionan.
- **Desajuste de arranque:** el README arranca con
  `shiny::runApp("Oralstats/Oralstats.R")` pero el fichero real es
  `Oralstats/app.R`.

---

## 2. Decisiones de diseño (aprobadas)

### 2.1 Modelo de distribución

**Vía principal: instalación local en R/RStudio con `renv` + `reticulate`.**
Es el stack de reproducibilidad documentado por Posit para proyectos R+Python.
`renv` fija los paquetes de R; `reticulate` crea y gestiona un venv de Python
**propio del proyecto** declarado por `requirements`. Conserva la aceleración
nativa (MPS en Apple Silicon, CUDA en Windows/Linux: `get_best_device()` en los
scripts Python), que es justo lo que se perdería en un contenedor.

**Red de seguridad: Docker.** Encapsula R + Python + Praat + ffmpeg + pandoc y se
construye desde cero en cada `docker build`. Sirve para (a) usuarios sin R y (b)
como base de la prueba en limpio reproducible. Compromiso conocido: dentro de
Docker se pierde MPS/GPU de Apple → el ML pesado iría por CPU.

Descartadas como vía principal: hospedada (Posit Connect/shinyapps.io limita
torch/WhisperX/GPU, Praat externo y audios grandes) y ejecutable de escritorio
(empaquetado multi-SO demasiado costoso de mantener).

### 2.2 Alcance de Python en 3 niveles

`pysentimiento` y `funasr` ya arrastran `torch`, así que torch es inevitable para
sentimiento/emoción. Lo que de verdad complica el multi-SO es WhisperX + pyannote.
Se escalona:

| Nivel | Paquetes | Política |
|---|---|---|
| **1 — Núcleo acústico** | `parselmouth`, `tgt` | Siempre instalado. Ligero, sin torch. Cubre el flujo PRAAT/Parselmouth. (El modo R nativo `seewave`/`tuneR` ni siquiera necesita Python.) |
| **2 — Texto/emoción** | `pysentimiento`, `funasr`, `soundfile` (+torch) | Instalado por defecto pero **aislado**: si su instalación falla, la app arranca igual y solo se desactiva esa pestaña. |
| **3 — Transcripción/diarización** | `whisperx`, `pyannote.audio` | **Opt-in**: botón "instalar transcripción" o seguir en Colab. Requiere token de HuggingFace para diarización. |

Garantía: "funciona en cualquier SO desde cero" se cumple siempre para el nivel 1;
los niveles frágiles no tumban el arranque.

---

## 3. Arquitectura de la solución

### A. Reproducibilidad de R — `renv`
- Inicializar `renv` en `Oralstats/` (`renv::init()`), dejando que detecte
  automáticamente las dependencias del código.
- Revisar que `renv.lock` incluya los obligatorios **y** los opcionales
  (`requireNamespace`), que `renv` a veces no captura si no se cargan. Añadir los
  que falten explícitamente.
- El usuario reproduce con `renv::restore()`.
- **Interfaz:** `renv.lock` (versiones exactas) + `renv/activate.R`.

### B. Reproducibilidad de Python — venv del proyecto vía `reticulate`
- Tres ficheros declarativos en `Oralstats/`:
  - `requirements-core.txt` → `praat-parselmouth`, `tgt`
  - `requirements-text.txt` → `pysentimiento`, `funasr`, `soundfile`
  - `requirements-asr.txt` → `whisperx`, `pyannote.audio`
- **Bootstrap** (`Oralstats/setup_python.R`): en el primer arranque crea el venv
  del proyecto con `reticulate::virtualenv_create()` e instala nivel 1 (+2). Idempotente:
  si el venv ya existe y satisface el nivel, no reinstala.
- **Refactor en `app.R`:** la resolución del intérprete (`.python_venv_path` y las
  llamadas `system2`) pasa a apuntar al venv del proyecto con
  `reticulate::virtualenv_python(<nombre_proyecto>)`, **con fallback** al
  `~/.virtualenvs/bert-env` actual para no romper instalaciones existentes.
- **Interfaz:** función `oralstats_python()` que devuelve la ruta al intérprete
  correcto; todas las llamadas `system2(python_bin, …)` la usan.

### C. Binarios de sistema — detección + guía por SO
- Centralizar `check_system_deps()` que detecte `praat`, `ffmpeg`, `pandoc`,
  Chrome y devuelva estado + sugerencia de instalación por SO.
- Mostrar el resultado en la pestaña "Dependencias Python" existente
  (`app.R:4603`), reutilizando el `run_diagnostico()` actual.
- Praat **opcional** (3 modos de pitch); `ffmpeg`/`pandoc` recomendados.
- **Interfaz:** `check_system_deps()` → lista nombrada `{praat, ffmpeg, pandoc,
  chrome}` con `{found: bool, path, hint}`.

### D. Arranque unificado — `run.R`
- Lanzador único `Oralstats/run.R` que: (1) `renv::restore()` si hace falta, (2)
  ejecuta `setup_python.R` (bootstrap del venv), (3) `shiny::runApp("app.R")`.
- Corrige el desajuste `Oralstats.R` ↔ `app.R`: actualizar el README para usar
  `run.R` (o `shiny::runApp("Oralstats")`, que toma `app.R` por convención).

### E. Prueba en limpio — dos niveles
- **Manual, en el propio Mac (`Oralstats/test_clean_install.sh`):** copia el repo a
  una carpeta temporal, **oculta temporalmente** `~/.virtualenvs/bert-env` y la
  caché de renv (renombrándolas, reversible), ejecuta el bootstrap desde cero,
  arranca la app y presenta un checklist de *smoke-test* por pestaña. Al terminar
  restaura lo ocultado. No toca el entorno real de desarrollo.
- **Garantía multi-SO reproducible (`Oralstats/Dockerfile`):** imagen con R +
  Python + praat + ffmpeg + pandoc que se construye desde cero en cada
  `docker build`. Es la prueba en limpio de verdad y la opción "cero R".
- **Opcional (`.github/workflows/clean-install.yml`):** matriz macOS/Windows/Ubuntu
  que hace `renv::restore()` + bootstrap + arranque headless de la app (verifica
  que levanta sin error). Marcado como mejora posterior, no bloqueante.

### F. Diagnóstico in-app por niveles
- Ampliar `run_diagnostico()` (`app.R:4873`) para distinguir qué nivel está
  instalado y ofrecer botones "instalar nivel 2 / nivel 3" que disparen la
  instalación del `requirements-*.txt` correspondiente en el venv del proyecto.

---

## 4. Smoke-test por pestaña (checklist de la prueba en limpio)

Tras la instalación en limpio, verificar manualmente:

1. **Arranque:** la app abre en el navegador sin error en consola.
2. **Carga / Crear análisis → Parselmouth (nivel 1):** procesar un par WAV+TextGrid
   de `samples/` y obtener F0/intensidad.
3. **Crear análisis → Script Praat:** solo si Praat está instalado; si no, el modo
   debe avisar con elegancia, no romper.
4. **Crear análisis → R nativo:** funciona sin Python ni Praat.
5. **Sentimientos y Emociones (nivel 2):** análisis textual con `pysentimiento` y,
   con audio, emoción con `funasr`.
6. **Transcripción → WhisperX (nivel 3):** solo si se instaló el add-on.
7. **Informe PDF/HTML:** requiere `pandoc` (+ Chrome para PDF).
8. **Pestaña "Dependencias Python":** el diagnóstico refleja correctamente el
   estado real de cada nivel y binario.

---

## 5. Fuera de alcance (YAGNI)

- Ejecutable de escritorio empaquetado.
- Despliegue hospedado en Posit Connect/shinyapps.io.
- GPU passthrough dentro de Docker.
- Reescribir las llamadas `system2` a Python como llamadas nativas `reticulate`
  (basta con que `reticulate` gestione el venv y dé la ruta del intérprete).

---

## 6. Criterios de éxito

- Una máquina sin OralStats reproduce el entorno con un único comando de arranque
  (`Rscript run.R` o `source("run.R")`) y la app abre.
- El nivel 1 (Parselmouth/Praat acústico) funciona en macOS, Windows y Linux.
- Los niveles 2 y 3 se instalan bajo demanda y su ausencia o fallo no impide
  arrancar la app.
- `test_clean_install.sh` y/o `docker build` reproducen una instalación desde cero
  sin contaminar el entorno de desarrollo.
- El README arranca la app con la ruta correcta.
