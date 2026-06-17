# etiquetador_oral.R  –  Versión 2.0
# Oralstats Etiquetador

# Permitir uploads de hasta 2 GB (ajusta según necesidad)
options(shiny.maxRequestSize = 2048 * 1024^2)

library(shiny)
library(DT)
library(tuneR)
library(shinyjs)
library(shinythemes)
library(seewave)
library(wrassp)
library(tools)
library(av)
library(rPraat)

HAS_PRAATPICTURE <- requireNamespace("praatpicture", quietly = TRUE)
if (HAS_PRAATPICTURE) library(praatpicture)

# ============================================================
# DIRECTORIO DE LA APP
# Ancla todas las carpetas de trabajo (config, backup, analisis, www) a
# la ubicación de ESTE script, no al working directory desde el que se
# lance (VS Code/Positron, Rscript, consola…). Replica lo que hace el
# botón "Run App" de RStudio, que fija el wd en la carpeta de la app.
# ============================================================
.detectar_app_dir <- function() {
  # 1) Archivo en ejecución vía source()/Run App: 'ofile' en la pila de llamadas
  for (fr in sys.frames()) {
    of <- fr$ofile
    if (!is.null(of) && nzchar(of)) return(dirname(normalizePath(of, mustWork = FALSE)))
  }
  # 2) Rscript: argumento --file=
  ca <- commandArgs(FALSE)
  fa <- grep("^--file=", ca, value = TRUE)
  if (length(fa)) return(dirname(normalizePath(sub("^--file=", "", fa[[1]]), mustWork = FALSE)))
  # 3) Editor de RStudio / Positron
  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      isTRUE(tryCatch(rstudioapi::isAvailable(), error = function(e) FALSE))) {
    p <- tryCatch(rstudioapi::getSourceEditorContext()$path, error = function(e) "")
    if (length(p) && nzchar(p)) return(dirname(normalizePath(p, mustWork = FALSE)))
  }
  # 4) Último recurso: working directory actual
  normalizePath(getwd(), mustWork = FALSE)
}
APP_DIR <- .detectar_app_dir()
if (dir.exists(APP_DIR)) {
  setwd(APP_DIR)
  message("Etiquetador: carpetas de trabajo ancladas a ", APP_DIR)
}

n_anot <- 33

# ============================================================
# DEFINICIONES POR DEFECTO DE VARIABLES DE ANOTACIÓN
# ============================================================
anot_defs_default <- list(

  anot1 = list(
    label   = "Tipo de enunciado (estructura):",
    choices = c("","Enunciado completo","Fragmento","Enunciado suspendido",
                "Respuesta mínima (sí, ya, claro...)","Continuador (ajá, mhm, sí sí...)")
  ),
  anot2 = list(
    label   = "Modalidad oracional:",
    choices = c("","Afirmativa","Negativa","Interrogativa total (sí/no)",
                "Interrogativa parcial (qu-)","Imperativa / directiva",
                "Exclamativa","Dubitativa / mitigada","Optativa / desiderativa")
  ),
  anot3 = list(
    label   = "Estatus informativo:",
    choices = c("","Información nueva","Información dada",
                "Recordatorio / reactivación","Reformulación de lo anterior",
                "Comentario metadiscursivo (sobre cómo se dice)")
  ),
  anot4 = list(
    label   = "Complejidad sintáctica:",
    choices = c("","Simple","Yuxtaposición de enunciados","Coordinación",
                "Subordinación ligera","Subordinación elaborada / estilo cercano a escrito")
  ),
  anot5 = list(
    label   = "Reformulación / expansión:",
    choices = c("","Sin reformulación","Autocorrección puntual",
                "Paráfrasis (decir lo mismo de otra forma)",
                "Expansión aclarativa / explicativa","Resumir / recapitular lo anterior")
  ),
  anot6 = list(
    label   = "Función discursiva global:",
    choices = c("","Narrativa (contar hechos)","Descriptiva","Explicativa / expositiva",
                "Argumentativa (defender un punto de vista)","Instruccional / directiva")
  ),
  anot7 = list(
    label   = "Referencia a discurso ajeno:",
    choices = c("","No hay cita","Cita directa (dijo: \"...\")","Cita indirecta (dijo que...)",
                "Estilo libre / eco del otro")
  ),
  anot8 = list(
    label   = "Temporalidad del contenido:",
    choices = c("","Presente / general","Pasado (relato)","Futuro / proyección",
                "Hipotético / condicional")
  ),
  anot9 = list(
    label   = "Función pragmática básica:",
    choices = c("","Asertiva / informativa","Directiva (petición, orden, consejo)",
                "Expresiva (emoción, reacción)","Fática (mantener contacto)",
                "Metapragmática (hablar del hablar)")
  ),
  anot10 = list(
    label   = "Función interpersonal:",
    choices = c("","Neutra","Gestión de acuerdo / desacuerdo",
                "Gestión de cercanía / complicidad","Gestión de conflicto / tensión")
  ),
  anot11 = list(
    label   = "Atenuación: presencia y tipo global:",
    choices = c("","Sin atenuación","Atenuación débil","Atenuación media","Atenuación fuerte")
  ),
  anot12 = list(
    label   = "Atenuación: orientación principal:",
    choices = c("","Orientada al yo (autoprotección)","Orientada al tú (no dañar al otro)",
                "Orientada al decir (presentación del enunciado)",
                "Orientada a la relación (cuidar el vínculo)")
  ),
  anot13 = list(
    label   = "Atenuación: procedimiento dominante:",
    choices = c("","Léxico (un poco, algo, más bien...)","Modalizadores (creo, me parece, supongo...)",
                "Reformulación / rodeos","Marcadores atenuantes (bueno, hombre, oye...)",
                "Cita / referencia a terceros (según dicen...)","Otros procedimientos")
  ),
  anot14 = list(
    label   = "Intensificación:",
    choices = c("","Sin intensificación","Cuantitativa (mucho, un montón...)",
                "Cualitativa (súper, re-, -ísimo...)","Acto de habla (te lo juro, de verdad...)",
                "Evaluativa (es brutal, es horrible...)","Múltiple (varias combinadas)")
  ),
  anot15 = list(
    label   = "Estrategia de cortesía:",
    choices = c("","No relevante / neutra","Cortesía positiva (acercamiento, elogio)",
                "Cortesía negativa (no imponer, minimizar daño)",
                "Ataque a la imagen del otro","Autoimagen mitigada (autocrítica, modestia)")
  ),
  anot16 = list(
    label   = "Imagen del otro:",
    choices = c("","Neutra","Apoyo / refuerzo del otro","Crítica indirecta",
                "Crítica directa","Broma / ironía sobre el otro")
  ),
  anot17 = list(
    label   = "Autoimagen:",
    choices = c("","Neutra","Autoelogio / autopromoción","Autocrítica seria",
                "Autocrítica irónica / lúdica","Justificación / excusa")
  ),
  anot18 = list(
    label   = "Movimiento conversacional:",
    choices = c("","Inicio de tema / secuencia","Continuación / desarrollo",
                "Respuesta directa al otro","Reacción evaluativa",
                "Cambio de tema","Cierre de secuencia")
  ),
  anot19 = list(
    label   = "Gestión del turno:",
    choices = c("","Toma de turno limpia","Autoseguimiento (seguir con el turno)",
                "Cesión de turno","Interrupción","Solapamiento cooperativo",
                "Solapamiento competitivo")
  ),
  anot20 = list(
    label   = "Relación con el turno previo:",
    choices = c("","Continuación lineal","Contraste / oposición","Aclaración / precisión",
                "Respuesta a pregunta","Desplazamiento temático")
  ),
  anot21 = list(
    label   = "Dinámica interactiva (solapamiento/ritmo):",
    choices = c("","Interacción pausada (pocos solapamientos)","Interacción ágil (turnos breves)",
                "Alta densidad de solapamientos cooperativos",
                "Solapamientos conflictivos / competitivos")
  ),
  anot22 = list(
    label   = "Marcador discursivo principal:",
    choices = c("","Apertura (bueno, oye, mira...)","Conectivo aditivo (y, además, encima...)",
                "Conectivo contrastivo (pero, sin embargo...)",
                "Consecuencia (entonces, así que, por eso...)",
                "Reformulación (o sea, quiero decir...)","Cierre (en fin, nada...)")
  ),
  anot23 = list(
    label   = "Función fática / de contacto:",
    choices = c("","No fática","Asegurar contacto (¿sabes?, ¿no?, ¿eh?)",
                "Apelación directa al otro","Confirmación / feedback mínimo",
                "Preguntas fáticas (¿vale?, ¿sí?)")
  ),
  anot24 = list(
    label   = "Deixis dominante:",
    choices = c("","Personal (yo, tú, nosotros...)","Espacial (aquí, ahí, allí...)",
                "Temporal (ahora, luego, antes...)","Textual / anafórica (eso, lo dicho, aquello...)",
                "Exofórica (esto/eso de aquí y ahora)")
  ),
  anot25 = list(
    label   = "Recursos coloquiales y muletillas:",
    choices = c("","Ninguno destacado","Interjecciones (¡ay!, ¡jo!, ¡uf!...)",
                "Muletillas (en plan, ¿sabes?, ¿vale?, tío/tía...)",
                "Frases hechas / proverbios","Argot / jerga específica")
  ),
  anot26 = list(
    label   = "Paralenguaje (sonidos no verbales):",
    choices = c("","Ninguno","Risa","Risa leve / nasal","Risa solapada con habla",
                "Tos","Carraspeo","Suspiro","Resoplido","Chasquido / clic de lengua",
                "Sollozo / llanto","Otros sonidos no verbales")
  ),
  anot27 = list(
    label   = "Tono emocional (Ekman):",
    choices = c("","Neutra / sin emoción marcada","Alegría","Tristeza","Miedo",
                "Ira / enfado","Asco","Sorpresa","Desprecio")
  ),
  anot28 = list(
    label   = "Solapamientos no verbales:",
    choices = c("","No hay","Risa solapada","Suspiro solapado",
                "Sonidos incidentales del hablante","Solapamiento cooperativo",
                "Solapamiento conflictivo")
  ),
  anot29 = list(
    label   = "Ruido articulatorio / gestual audible:",
    choices = c("","Ninguno","Pensativo (mmm...)","Desaprobación (tsk, clic)",
                "Llamada / atención (chss, besito)","Esfuerzo / molestia","Otros")
  ),
  anot30 = list(
    label   = "Fenómenos respiratorios:",
    choices = c("","Ninguno","Inspiración audible","Expiración marcada",
                "Suspiro largo","Hiperventilación ligera")
  ),
  anot31 = list(
    label   = "Sonidos no verbales como toma de turno:",
    choices = c("","No hay","Mhm / ajá (aceptación)","¿Eh? (petición de aclaración)",
                "Risa como toma de turno","Sonidos que inician turno (chasquido, inspiración)",
                "Otros")
  ),
  anot32 = list(
    label   = "Ruido ambiental con impacto discursivo:",
    choices = c("","Irrelevante","Ruido que interfiere en el turno","Risas de terceros",
                "Golpes / choques / movimiento",
                "Música / sonido que provoca reformulación","Otros")
  ),
  anot33 = list(
    label   = "Actitud vocal no verbal:",
    choices = c("","Neutra","Cercanía / intimidad","Tensión / ansiedad",
                "Confrontativa (bufidos, resoplidos)","Desdén (risita nasal, clic)",
                "Lúdica / irónica")
  )
)

# ============================================================
# CONFIGURACIÓN: carga y guardado de etiquetas personalizadas
# ============================================================
CONFIG_DIR   <- file.path(APP_DIR, "config")
ETIQ_FILE    <- file.path(CONFIG_DIR, "etiquetas_variables.txt")
BACKUP_DIR   <- file.path(APP_DIR, "backup")
ANALISIS_DIR <- file.path(APP_DIR, "analisis")

ensure_dirs <- function() {
  for (d in c(CONFIG_DIR, BACKUP_DIR, ANALISIS_DIR)) {
    if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  }
}

save_etiquetas <- function(defs) {
  ensure_dirs()
  rows <- lapply(names(defs), function(id) {
    def <- defs[[id]]
    ch <- def$choices[def$choices != ""]
    data.frame(id = id, label = def$label,
               choices = paste(ch, collapse = ";"),
               stringsAsFactors = FALSE)
  })
  df <- do.call(rbind, rows)
  write.table(df, ETIQ_FILE, sep = "\t", row.names = FALSE,
              quote = TRUE, fileEncoding = "UTF-8")
}

load_etiquetas <- function() {
  defs <- anot_defs_default
  if (!file.exists(ETIQ_FILE)) return(defs)
  tryCatch({
    df <- read.table(ETIQ_FILE, sep = "\t", header = TRUE,
                     stringsAsFactors = FALSE, quote = "\"",
                     fileEncoding = "UTF-8")
    for (i in seq_len(nrow(df))) {
      id <- df$id[i]
      if (!id %in% names(defs)) next
      defs[[id]]$label <- df$label[i]
      ch <- strsplit(df$choices[i], ";", fixed = TRUE)[[1]]
      defs[[id]]$choices <- c("", ch[nzchar(trimws(ch))])
    }
  }, error = function(e) message("Error cargando etiquetas: ", e$message))
  defs
}

# ============================================================
# ANÁLISIS POR CUARTILES
# ============================================================
quartile_means <- function(vals, times, t_start, t_end) {
  sel <- times >= t_start & times <= t_end & is.finite(vals) & vals > 0
  v   <- vals[sel]
  if (length(v) < 4) return(rep(NA_real_, 4))
  n  <- length(v)
  br <- round(seq(1, n + 1, length.out = 5))
  sapply(1:4, function(q) {
    idx <- br[q]:(br[q + 1] - 1)
    if (length(idx) == 0) NA_real_ else mean(v[idx], na.rm = TRUE)
  })
}

get_quartile_metrics <- function(pitch_df, int_df, t_start, t_end, pct) {
  dur <- t_end - t_start
  if (dur <= 0 || pct <= 0) {
    na4 <- rep(NA_real_, 4)
    return(list(F0_ini = na4, F0_fin = na4, Int_ini = na4, Int_fin = na4))
  }
  w       <- dur * pct / 100
  ini_end <- t_start + w
  fin_st  <- t_end   - w

  F0_ini <- F0_fin <- Int_ini <- Int_fin <- rep(NA_real_, 4)

  if (!is.null(pitch_df) && nrow(pitch_df) > 0) {
    F0_ini <- quartile_means(pitch_df$f0,        pitch_df$time, t_start, ini_end)
    F0_fin <- quartile_means(pitch_df$f0,        pitch_df$time, fin_st,  t_end)
  }
  if (!is.null(int_df) && nrow(int_df) > 0) {
    Int_ini <- quartile_means(int_df$intensity, int_df$time,   t_start, ini_end)
    Int_fin <- quartile_means(int_df$intensity, int_df$time,   fin_st,  t_end)
  }
  list(F0_ini = F0_ini, F0_fin = F0_fin, Int_ini = Int_ini, Int_fin = Int_fin)
}

quartile_col_names <- c(
  paste0("F0_ini_q",  1:4),
  paste0("F0_fin_q",  1:4),
  paste0("Int_ini_q", 1:4),
  paste0("Int_fin_q", 1:4)
)

# ============================================================
# HELPERS GENERALES
# ============================================================
make_col_order <- function() {
  c("speaker","start","end","label","contexto",
    "n_palabras","palabras_por_seg","fonemas_por_seg",
    "F0_mean","F0_median","F0_sd","F0_range_st","F0_delta_st",
    "F0_final_delta_st","F0_final_pattern",
    "Int_mean","Int_median","Int_sd",
    quartile_col_names,
    paste0("anot", 1:n_anot),
    "observaciones")
}

make_select_from_def <- function(id, def) {
  selectInput(id, def$label, choices = def$choices, width = "100%", multiple = TRUE)
}

ensure_annotation_cols <- function(df) {
  for (i in seq_len(n_anot)) {
    cn <- paste0("anot", i)
    if (!cn %in% names(df)) df[[cn]] <- NA_character_
  }
  for (cn in quartile_col_names) {
    if (!cn %in% names(df)) df[[cn]] <- NA_real_
  }
  if (!"observaciones" %in% names(df)) df$observaciones <- NA_character_
  df
}

# ============================================================
# UI
# ============================================================
ui <- fluidPage(
  title = "Oralstats Etiquetador v2.0",
  theme = shinythemes::shinytheme("united"),
  useShinyjs(),

  tags$head(tags$style(HTML("
    body { background-color: #eef2f7; }
    .app-footer { margin-top:10px; padding:8px 0 4px; font-size:11px;
                  color:#9ca3af; text-align:center; }
    .app-footer a { color:#9ca3af; text-decoration:underline; }
    .app-container { max-width:1400px; margin:0 auto 20px auto; }
    .navbar,.navbar-default { border-radius:0; }
    h2,h3,h4,h5 { font-weight:600; color:#1f2933; }
    .sidebar-card,.main-card,.annotations-card,.export-bar {
      background-color:#ffffff; border-radius:12px;
      box-shadow:0 6px 18px rgba(15,23,42,0.08);
      padding:16px 18px; margin-bottom:16px; }
    .sidebar-card { min-height:calc(100vh - 80px); overflow-y:auto;
                    position:sticky; top:20px; }
    .export-bar { border-top:2px solid #e5e7eb; }
    .control-label { font-weight:600; color:#374151; }
    .form-control,.selectize-input { border-radius:8px; }
    .btn { border-radius:999px; font-weight:500; }
    .btn-primary,.btn-success,.btn-info,.btn-danger,.btn-secondary { border:none; }
    .tabbable>.nav-tabs { border-bottom:none; margin-bottom:10px; }
    .nav-tabs>li>a { border-radius:999px !important; margin-right:4px; padding:6px 12px; }
    .nav-tabs>li.active>a,.nav-tabs>li.active>a:focus,.nav-tabs>li.active>a:hover {
      background-color:#2563eb; color:#ffffff !important; }
    #table,#context_table { font-size:13px; }
    #annotation_status { font-size:12px; color:#10b981; margin-top:6px; }
    .anot-box { border:2px solid #e5e7eb; border-radius:10px; padding:12px 14px; background:#fafafa; }
    #sequential_position { font-weight:500; color:#4b5563; margin-bottom:6px; }
    .small-helper-text { font-size:11px; color:#6b7280; margin-top:4px; }
    .export-title { letter-spacing:.05em; text-transform:uppercase;
                    font-size:11px; color:#6b7280; margin-bottom:8px; }
    .file-status-active { background:#f0fdf4; border:1px solid #86efac;
      border-radius:8px; padding:8px 10px; margin-bottom:8px; }
    .file-status-active .file-label { font-size:12px; color:#15803d; font-weight:600; }
    .file-status-active .file-name  { font-size:13px; font-weight:500; color:#1f2937; }
    .file-status-active .file-meta  { font-size:11px; color:#6b7280; }
    .emo-row { display:flex; gap:6px; flex-wrap:wrap; margin-bottom:10px; }
    .emo-btn { font-size:26px; line-height:1; padding:6px 8px; border:2px solid #e5e7eb;
               border-radius:10px; background:#fff; cursor:pointer; transition:.15s; }
    .emo-btn:hover { border-color:#93c5fd; background:#eff6ff; }
    .emo-btn.emo-selected { border-color:#2563eb; background:#dbeafe; }
    .emo-label { font-size:10px; color:#6b7280; text-align:center; margin-top:2px; }
  "))),

  div(class = "app-container",

    titlePanel(div(
      style = "display:flex; align-items:center; justify-content:space-between;",
      span("Etiquetador de datos orales. Versión 2.0"),
      span(style = "font-size:12px; color:#6b7280;", "Oralstats – explorador prosódico")
    )),

    fluidRow(

      # ====================== SIDEBAR ======================
      column(3, div(class = "sidebar-card",

        # ---- Carga de archivos (Estado A / Estado B) ----
        uiOutput("sidebar_file_ui"),

        # ---- Sección activa (solo cuando hay análisis cargado) ----
        div(id = "sidebar_active_section",

          hr(),

          uiOutput("sidebar_segment_info"),

          fluidRow(
            column(6, actionButton("play_segment", "▶ Segmento",
                                   class = "btn-success btn-sm", style = "width:100%;")),
            column(6, actionButton("play_with_context", "▶ Contexto",
                                   class = "btn-info btn-sm", style = "width:100%;"))
          ),
          div(style = "display:flex; gap:6px; margin-top:6px;",
            numericInput("context_before", "Antes (s):",
                         value = 0, min = 0, max = 5, step = 0.5, width = "50%"),
            numericInput("context_after",  "Despues (s):",
                         value = 0, min = 0, max = 5, step = 0.5, width = "50%")
          ),

          hr(),

          h5("Navegación secuencial", style = "margin-top:0;"),
          fluidRow(
            column(6, actionButton("prev_row","<= Anterior",
                                   class = "btn-secondary btn-sm", style = "width:100%;")),
            column(6, actionButton("next_row","Siguiente =>",
                                   class = "btn-secondary btn-sm", style = "width:100%;"))
          ),
          br(),
          textOutput("sequential_position"),
          numericInput("goto_row","Ir a fila:", value = 1, min = 1, step = 1, width = "100%"),
          actionButton("goto_row_btn","Ir",
                       class = "btn-secondary btn-sm", style = "width:100%; margin-top:5px;")
        )
      )),

      # ====================== COLUMNA DERECHA ======================
      column(9,

        div(class = "main-card",
          tabsetPanel(

            # ====================== ANOTACIONES (primer tab) ======================
            tabPanel("Anotaciones", br(),

              fluidRow(
                column(10, uiOutput("annotation_tabs_ui")),
                column(2, br(),
                  actionButton("save_annotation","Guardar",
                               class = "btn-primary btn-sm", style = "width:100%;"),
                  br(), br(),
                  textOutput("annotation_status")
                )
              ),
              br(),
              textAreaInput("observaciones","Observaciones:",
                            placeholder = "Notas...", rows = 2, width = "100%")
            ),

            tabPanel("Tabla",
              div(style = "padding: 6px 0 2px;",
                checkboxInput("show_contexto", "Mostrar columna 'contexto'", value = FALSE)
              ),
              DTOutput("table")
            ),

            tabPanel("Contexto", br(),
              fluidRow(
                column(4, numericInput("context_rows","Filas de contexto (+-):",
                                       value = 5, min = 1, max = 20, step = 1, width = "100%")),
                column(8, div(class = "small-helper-text", br(),
                              "El contexto se muestra en orden temporal con formato ",
                              tags$code("speaker: texto")))
              ),
              hr(), DTOutput("context_table")
            ),

            tabPanel("Analisis fonetico", br(),
              fluidRow(column(12,
                actionButton("play_segment1","Reproducir segmento",
                             icon = icon("play"), class = "btn-success btn-sm",
                             style = "margin-right:5px;"),
                actionButton("compute_all","Calcular F0/Int de todos los segmentos",
                             class = "btn-danger btn-sm"),
                div(class = "small-helper-text",
                    "Calcula métricas acústicas para todas las filas."),
                hr()
              )),
              fluidRow(column(12, uiOutput("video_player"))),
              br(),
              fluidRow(
                column(6, plotOutput("oscillo_plot",  height = 250)),
                column(6, plotOutput("spectro_plot",  height = 250))
              ),
              br(),
              plotOutput("pitch_plot", height = 300)
            ),

            tabPanel("Metricas", br(),
              h5("Análisis prosódico de la fila actual"),
              verbatimTextOutput("metrics_display")
            ),

            tabPanel("Praatpicture", br(),
              if (HAS_PRAATPICTURE) {
                tagList(
                  fluidRow(
                    column(3, checkboxInput("pp_show_wave",  "Oscilograma", TRUE)),
                    column(3, checkboxInput("pp_show_spec",  "Espectrograma", TRUE)),
                    column(3, checkboxInput("pp_show_pitch", "F0", TRUE)),
                    column(3, checkboxInput("pp_show_int",   "Intensidad", FALSE))
                  ),
                  actionButton("render_praatpic", "Renderizar",
                               class = "btn-info btn-sm", style = "margin-bottom:10px;"),
                  plotOutput("praatpicture_plot", height = 500)
                )
              } else {
                div(
                  class = "small-helper-text",
                  style = "padding:20px;",
                  tags$b("El paquete 'praatpicture' no está instalado."),
                  br(),
                  "Instálalo con: ",
                  tags$code("install.packages('praatpicture')")
                )
              }
            ),

            # ====================== CONFIGURACIÓN ======================
            tabPanel("Estadísticas", br(),
              tabsetPanel(type = "tabs",
                tabPanel("Barras", br(),
                  fluidRow(
                    column(5,
                      selectInput("stat_cat_var", "Variable categórica:",
                                  choices = NULL, width = "100%")
                    ),
                    column(4,
                      radioButtons("stat_bar_type", "Mostrar como:",
                                   choices = c("Absoluto" = "abs",
                                               "Porcentaje" = "pct"),
                                   inline = TRUE)
                    ),
                    column(3, br(),
                      actionButton("stat_bar_update", "Actualizar",
                                   class = "btn-primary btn-sm",
                                   style = "width:100%;")
                    )
                  ),
                  plotOutput("stat_barplot", height = 420)
                ),
                tabPanel("Boxplots", br(),
                  fluidRow(
                    column(5,
                      selectInput("stat_num_var", "Variable numérica:",
                                  choices = NULL, width = "100%")
                    ),
                    column(4,
                      selectInput("stat_group_var", "Agrupar por (opcional):",
                                  choices = NULL, width = "100%")
                    ),
                    column(3, br(),
                      actionButton("stat_box_update", "Actualizar",
                                   class = "btn-primary btn-sm",
                                   style = "width:100%;")
                    )
                  ),
                  plotOutput("stat_boxplot", height = 380),
                  br(),
                  verbatimTextOutput("stat_summary")
                )
              )
            ),

            tabPanel("Configuración", br(),
              h6("⚙️ Parámetros acústicos"),
              fluidRow(
                column(6, numericInput("quartile_pct",
                           "Porcentaje cuartiles (%):",
                           value = 20, min = 5, max = 50, step = 5, width = "100%")),
                column(6, br(),
                  actionButton("open_var_editor", "Editar variables",
                               icon = icon("edit"), class = "btn-info btn-sm",
                               style = "width:100%;"),
                  br(), br(),
                  actionButton("reset_var_defs", "Restaurar por defecto",
                               class = "btn-danger btn-sm", style = "width:100%;")
                )
              )
            )
          )
        )
      )
    ),

    div(class = "app-footer",
      HTML("&copy; 2026 Adrián Cabedo Nebot &middot;
           <a href='https://creativecommons.org/licenses/by/4.0/deed.es' target='_blank'>
           CC BY 4.0</a>")
    )
  )
)

# ============================================================
# SERVER
# ============================================================
server <- function(input, output, session) {

  `%||%` <- function(a, b) if (!is.null(a)) a else b

  video_temp_dir <- tempdir()
  addResourcePath("tmpvideo", video_temp_dir)

  ensure_dirs()

  # ---- Valores reactivos ----
  rv <- reactiveValues(
    df              = NULL,
    df_full         = NULL,
    audio_path      = NULL,
    audio_cached    = NULL,
    selected_segment= NULL,
    pitch_data      = NULL,   # pitch para la gráfica del segmento actual
    video_path      = NULL,
    video_url       = NULL,
    is_video        = FALSE,
    selected_start  = NULL,
    selected_end    = NULL,
    acoustic_done   = FALSE,
    selected_row_index = NULL,
    sequential_index   = 1,
    current_filename   = NULL,
    initial_backup_done= FALSE,
    anot_defs         = load_etiquetas(),
    praatpic_temp_wav = NULL,
    analysis_scan_trigger = 0,
    pending_tg_path       = NULL,
    pending_tg_base       = NULL
  )

  autosave_status <- reactiveVal("")

  # Ocultar sección activa hasta que se cargue un análisis
  shinyjs::hide("sidebar_active_section")

  output$annotation_status <- renderText(autosave_status())

  # ============================================================
  # EMOCIONES (anot27)
  # ============================================================
  emo_list <- list(
    list(id = "neutral",  emoji = "\U0001f610", label = "Neutra"),
    list(id = "joy",      emoji = "\U0001f604", label = "Alegría"),
    list(id = "sadness",  emoji = "\U0001f622", label = "Tristeza"),
    list(id = "fear",     emoji = "\U0001f628", label = "Miedo"),
    list(id = "anger",    emoji = "\U0001f620", label = "Ira"),
    list(id = "disgust",  emoji = "\U0001f922", label = "Asco"),
    list(id = "surprise", emoji = "\U0001f632", label = "Sorpresa"),
    list(id = "contempt", emoji = "\U0001f612", label = "Desprecio")
  )
  selected_emotion <- reactiveVal(NULL)

  output$emotion_ui <- renderUI({
    sel <- selected_emotion()
    div(class = "emo-row",
      lapply(emo_list, function(e) {
        is_sel <- !is.null(sel) && sel == e$label
        btn_class <- paste0("btn emo-btn", if (is_sel) " emo-selected" else "")
        div(style = "text-align:center;",
          tags$button(e$emoji,
            id     = paste0("emo_btn_", e$id),
            class  = btn_class,
            onclick = sprintf(
              "Shiny.setInputValue('emo_clicked', '%s', {priority: 'event'});",
              e$label)
          ),
          div(class = "emo-label", e$label)
        )
      })
    )
  })

  output$emotion_value_display <- renderUI({
    sel <- selected_emotion()
    lik <- if (!is.null(input$emotion_likert)) input$emotion_likert else 3L
    val <- if (!is.null(sel)) sprintf("%s - %d", sel, lik) else "(sin selección)"
    div(style = "margin-top:6px; font-size:13px; color:#374151;",
      tags$b("Valor guardado: "), val)
  })

  write_emotion_to_anot27 <- function() {
    sel <- selected_emotion()
    if (is.null(sel) || is.null(rv$df_full) || is.null(rv$selected_row_index)) return()
    i   <- rv$selected_row_index
    lik <- if (!is.null(input$emotion_likert)) input$emotion_likert else 3L
    rv$df_full$anot27[i] <- sprintf("%s - %d", sel, lik)
    tryCatch(save_analysis_file(rv$df_full, rv$current_filename, make_backup_copy = FALSE),
             error = function(e) NULL)
    autosave_status(sprintf("✓ Emoción guardada (fila %d)", i))
  }

  observeEvent(input$emo_clicked, {
    selected_emotion(input$emo_clicked)
    write_emotion_to_anot27()
  })

  observeEvent(input$emotion_likert, {
    if (!is.null(selected_emotion())) write_emotion_to_anot27()
  }, ignoreInit = TRUE)

  # Al cambiar de fila: sincronizar el estado de emociones desde anot27
  observeEvent(rv$selected_row_index, {
    req(rv$df_full, rv$selected_row_index)
    val <- rv$df_full$anot27[rv$selected_row_index]
    if (!is.na(val) && nzchar(val)) {
      parts <- strsplit(val, "\\s*-\\s*")[[1]]
      if (length(parts) >= 2) {
        sel_lbl <- trimws(parts[1])
        lik_val <- suppressWarnings(as.integer(trimws(parts[length(parts)])))
        selected_emotion(sel_lbl)
        if (!is.na(lik_val) && lik_val >= 1 && lik_val <= 5)
          updateSliderInput(session, "emotion_likert", value = lik_val)
      } else {
        selected_emotion(trimws(val))
      }
    } else {
      selected_emotion(NULL)
      updateSliderInput(session, "emotion_likert", value = 3)
    }
  }, ignoreInit = TRUE)

  # ============================================================
  # SISTEMA DE CARGA DE ARCHIVOS
  # ============================================================

  scan_analysis_files <- function() {
    force(rv$analysis_scan_trigger)
    ensure_dirs()
    files <- sort(list.files(ANALISIS_DIR, pattern = "^analisis_.*\\.txt$",
                             full.names = FALSE))
    files <- files[files != "analisis_todos.txt"]
    if (length(files) == 0) return(c("(no hay análisis guardados)" = ""))
    labels <- tools::file_path_sans_ext(sub("^analisis_", "", files))
    setNames(files, labels)
  }

  find_audio_for_base <- function(base) {
    dir <- file.path("www", "audios")
    for (ext in c(".wav", ".WAV", ".mp3", ".mp4")) {
      p <- file.path(dir, paste0(base, ext))
      if (file.exists(p)) return(p)
    }
    NULL
  }

  activate_analysis <- function(df, filename_base, audio_path) {
    withProgress(message = "Cargando análisis...", value = 0.3, {
      tryCatch(load_audio(audio_path), error = function(e) {
        showNotification(paste("Error audio:", e$message), type = "error")
        stop(e)
      })
      df <- prepare_df(df)
      rv$df_full          <- df
      rv$df               <- df
      rv$current_filename <- filename_base
      rv$sequential_index <- 1
      rv$acoustic_done    <- FALSE
      incProgress(0.7)
    })
    shinyjs::show("sidebar_active_section")
    rv$analysis_scan_trigger <- rv$analysis_scan_trigger + 1
    showNotification(
      sprintf("Análisis cargado: %d grupos entonativos.", nrow(df)),
      type = "message", duration = 4)
  }

  # --- Estado A / Estado B ---
  output$sidebar_file_ui <- renderUI({
    if (is.null(rv$current_filename)) {
      # Estado A: sin análisis
      tagList(
        h5("Abrir análisis", style = "margin-top:0; margin-bottom:8px;"),
        selectInput("existing_analysis", NULL,
                    choices  = scan_analysis_files(),
                    width    = "100%",
                    selected = ""),
        actionButton("open_existing", "Abrir",
                     icon  = icon("folder-open"),
                     class = "btn-primary btn-sm",
                     style = "width:100%; margin-bottom:10px;"),
        hr(),
        p(style = "font-size:12px; color:#6b7280; margin-bottom:6px;",
          "¿Primer uso con un archivo nuevo?"),
        fileInput("new_tg_upload",
                  "Subir TextGrid:",
                  accept = c(".TextGrid", ".textgrid"),
                  width  = "100%"),
        fileInput("new_audio_upload",
                  "Subir audio (si no está en www/audios):",
                  accept = c(".wav", ".mp3"),
                  width  = "100%")
      )
    } else {
      # Estado B: análisis activo
      base <- tools::file_path_sans_ext(
        sub("^analisis_", "", basename(rv$current_filename)))
      n <- if (!is.null(rv$df_full)) nrow(rv$df_full) else 0
      div(class = "file-status-active",
        div(class = "file-label", "Análisis activo"),
        div(class = "file-name",  base),
        div(class = "file-meta",  sprintf("%d grupos entonativos", n)),
        br(),
        actionButton("change_analysis", "Cambiar archivo",
                     icon  = icon("exchange-alt"),
                     class = "btn-secondary btn-sm",
                     style = "width:100%;")
      )
    }
  })

  # Abrir análisis existente (carga rápida)
  observeEvent(input$open_existing, {
    req(nzchar(input$existing_analysis))
    path <- file.path(ANALISIS_DIR, input$existing_analysis)
    if (!file.exists(path)) {
      showNotification("Archivo no encontrado.", type = "error"); return()
    }
    df <- tryCatch(
      read.table(path, sep = "\t", header = TRUE, stringsAsFactors = FALSE,
                 fileEncoding = "UTF-8", quote = "", na.strings = ""),
      error = function(e) {
        showNotification(paste("Error leyendo análisis:", e$message), type = "error")
        NULL
      })
    if (is.null(df)) return()

    base       <- tools::file_path_sans_ext(sub("^analisis_", "", basename(path)))
    audio_path <- find_audio_for_base(base)
    if (is.null(audio_path)) {
      showNotification(
        sprintf("Audio no encontrado en www/audios/ para: %s", base),
        type = "error"); return()
    }
    activate_analysis(df, basename(path), audio_path)
  })

  # Cambiar de archivo (vuelve a Estado A)
  observeEvent(input$change_analysis, {
    rv$current_filename <- NULL
    rv$df_full          <- NULL
    rv$df               <- NULL
    rv$audio_cached     <- NULL
    rv$audio_path       <- NULL
    rv$sequential_index <- 1
    rv$selected_row_index <- NULL
    shinyjs::hide("sidebar_active_section")
  })

  # Procesar TextGrid pendiente (llamado desde new_tg_upload y new_audio_upload)
  process_pending_tg <- function(tg_path, base, audio_path) {
    analysis_file <- file.path(ANALISIS_DIR, paste0("analisis_", base, ".txt"))
    if (file.exists(analysis_file)) {
      rv$pending_tg_path <- tg_path
      rv$pending_tg_base <- base
      showModal(modalDialog(
        title = "Análisis existente",
        p(sprintf("Ya existe un análisis guardado para '%s'.", base)),
        p("¿Quieres cargarlo (rápido) o regenerar los grupos entonativos desde el TextGrid?"),
        footer = tagList(
          actionButton("load_existing_from_tg", "Cargar análisis guardado",
                       class = "btn-primary"),
          actionButton("regen_from_tg", "Regenerar GEs desde TextGrid",
                       class = "btn-warning"),
          modalButton("Cancelar")
        )
      ))
      return()
    }
    tg <- tryCatch(tg.read(tg_path), error = function(e) NULL)
    if (is.null(tg)) {
      showNotification("No se pudo leer el TextGrid.", type = "error"); return()
    }
    rv$pending_tg_path <- tg_path
    rv$pending_tg_base <- base
    if (is_mfa_textgrid(tg)) {
      showModal(modalDialog(
        title = "Generar grupos entonativos",
        p("Se detectaron los tiers 'phones' y 'words'."),
        p("Se generarán GEs automáticamente usando los siguientes umbrales:"),
        fluidRow(
          column(6, numericInput("ge_pause_min", "Pausa mínima (s):",
                                 value = 0.3, min = 0.05, step = 0.05, width = "100%")),
          column(6, numericInput("ge_f0_reset", "Reset F0 mínimo (st):",
                                 value = 5, min = 1, step = 0.5, width = "100%"))
        ),
        p(style="font-size:11px;color:#6b7280;",
          "Nota: el criterio de reset F0 se aplica en una versión futura."),
        footer = tagList(
          actionButton("ge_confirm", "Generar GEs", class = "btn-primary"),
          modalButton("Cancelar")
        )
      ))
    } else {
      # TextGrid genérico: cargar directamente
      do_load_files(audio_path, tg_path, paste0(base, ".TextGrid"))
      shinyjs::show("sidebar_active_section")
      rv$analysis_scan_trigger <- rv$analysis_scan_trigger + 1
    }
  }

  # Nuevo audio subido: copiar a www/audios y reanudar TG pendiente si lo hay
  observeEvent(input$new_audio_upload, {
    req(input$new_audio_upload)
    dest_dir <- file.path("www", "audios")
    if (!dir.exists(dest_dir)) dir.create(dest_dir, recursive = TRUE)
    dest <- file.path(dest_dir, input$new_audio_upload$name)
    file.copy(input$new_audio_upload$datapath, dest, overwrite = TRUE)
    showNotification(sprintf("Audio guardado: %s", input$new_audio_upload$name),
                     type = "message", duration = 3)
    # Si hay un TextGrid pendiente esperando este audio, procesarlo ahora
    if (!is.null(rv$pending_tg_path) && !is.null(rv$pending_tg_base)) {
      base_audio <- tools::file_path_sans_ext(input$new_audio_upload$name)
      if (base_audio == rv$pending_tg_base) {
        process_pending_tg(rv$pending_tg_path, rv$pending_tg_base, dest)
      }
    }
  })

  # Nuevo TextGrid subido
  observeEvent(input$new_tg_upload, {
    req(input$new_tg_upload)
    base       <- tools::file_path_sans_ext(input$new_tg_upload$name)
    audio_path <- find_audio_for_base(base)
    if (is.null(audio_path)) {
      # Guardar TG pendiente; el observer de audio lo retomará
      rv$pending_tg_path <- input$new_tg_upload$datapath
      rv$pending_tg_base <- base
      showNotification(
        sprintf("TextGrid guardado. Ahora sube el audio '%s'.", base),
        type = "warning", duration = 8)
      return()
    }
    process_pending_tg(input$new_tg_upload$datapath, base, audio_path)
  })

  # Cargar análisis guardado (desde modal)
  observeEvent(input$load_existing_from_tg, {
    removeModal()
    req(rv$pending_tg_base)
    base          <- rv$pending_tg_base
    analysis_file <- file.path(ANALISIS_DIR, paste0("analisis_", base, ".txt"))
    audio_path    <- find_audio_for_base(base)
    df <- tryCatch(
      read.table(analysis_file, sep = "\t", header = TRUE, stringsAsFactors = FALSE,
                 fileEncoding = "UTF-8", quote = "", na.strings = ""),
      error = function(e) { showNotification(paste("Error:", e$message), type="error"); NULL })
    if (!is.null(df) && !is.null(audio_path))
      activate_analysis(df, paste0("analisis_", base, ".txt"), audio_path)
  })

  # Regenerar GEs desde TextGrid (desde modal, sin análisis previo)
  observeEvent(input$regen_from_tg, {
    removeModal()
    req(rv$pending_tg_path, rv$pending_tg_base)
    base       <- rv$pending_tg_base
    audio_path <- find_audio_for_base(base)
    tg <- tryCatch(tg.read(rv$pending_tg_path), error = function(e) NULL)
    if (is.null(tg) || is.null(audio_path)) {
      showNotification("Error al leer TextGrid o audio no encontrado.", type="error")
      return()
    }
    if (is_mfa_textgrid(tg)) {
      showModal(modalDialog(
        title = "Regenerar grupos entonativos",
        fluidRow(
          column(6, numericInput("ge_pause_min", "Pausa mínima (s):",
                                 value = 0.3, min = 0.05, step = 0.05, width = "100%")),
          column(6, numericInput("ge_f0_reset",  "Reset F0 mínimo (st):",
                                 value = 5, min = 1, step = 0.5, width = "100%"))
        ),
        footer = tagList(
          actionButton("ge_confirm", "Generar GEs", class = "btn-primary"),
          modalButton("Cancelar")
        )
      ))
    } else {
      do_load_files(audio_path, rv$pending_tg_path, paste0(base, ".TextGrid"))
      shinyjs::show("sidebar_active_section")
      rv$analysis_scan_trigger <- rv$analysis_scan_trigger + 1
    }
  })

  # Confirmar generación de GEs
  observeEvent(input$ge_confirm, {
    removeModal()
    req(rv$pending_tg_path, rv$pending_tg_base)
    base       <- rv$pending_tg_base
    audio_path <- find_audio_for_base(base)
    pause_min  <- if (!is.null(input$ge_pause_min)) input$ge_pause_min else 0.3
    tg <- tryCatch(tg.read(rv$pending_tg_path), error = function(e) NULL)
    if (is.null(tg) || is.null(audio_path)) {
      showNotification("Error al leer TextGrid.", type = "error"); return()
    }
    withProgress(message = "Generando grupos entonativos...", value = 0.3, {
      df <- parse_textgrid(tg, mfa_mode = TRUE, pause_min = pause_min)
      if (is.null(df)) {
        showNotification("No se generaron GEs. Revisa los tiers del TextGrid.",
                         type = "error"); return()
      }
      df <- prepare_df(df)
      incProgress(0.4)
      tryCatch(load_audio(audio_path), error = function(e) {
        showNotification(paste("Error audio:", e$message), type = "error"); stop(e)
      })
      rv$df_full          <- df
      rv$df               <- df
      rv$current_filename <- paste0(base, ".TextGrid")
      rv$sequential_index <- 1
      rv$acoustic_done    <- FALSE
      tryCatch(
        save_analysis_file(df, rv$current_filename, make_backup_copy = FALSE),
        error = function(e) NULL)
      incProgress(0.3)
    })
    shinyjs::show("sidebar_active_section")
    rv$analysis_scan_trigger <- rv$analysis_scan_trigger + 1
    showNotification(
      sprintf("GEs generados: %d grupos entonativos guardados.", nrow(rv$df_full)),
      type = "message", duration = 5)
  })

  # ============================================================
  # UI DINÁMICA: panel de anotaciones
  # ============================================================
  output$annotation_tabs_ui <- renderUI({
    defs <- rv$anot_defs
    mk <- function(id) make_select_from_def(id, defs[[id]])

    div(class = "anot-box",
    tabsetPanel(type = "pills",
      tabPanel("Estructura",
        fluidRow(
          column(4, mk("anot1"), mk("anot2")),
          column(4, mk("anot3"), mk("anot4")),
          column(4, mk("anot5"), mk("anot6"))
        ),
        fluidRow(column(6, mk("anot7")), column(6, mk("anot8")))
      ),
      tabPanel("Pragmática",
        fluidRow(
          column(4, mk("anot9"),  mk("anot10")),
          column(4, mk("anot11"), mk("anot12")),
          column(4, mk("anot13"), mk("anot14"))
        ),
        fluidRow(column(6, mk("anot15")), column(6, mk("anot16"))),
        fluidRow(column(6, mk("anot17")))
      ),
      tabPanel("Discurso e interaccion",
        fluidRow(
          column(4, mk("anot18"), mk("anot19")),
          column(4, mk("anot20"), mk("anot21")),
          column(4, mk("anot22"), mk("anot23"))
        ),
        fluidRow(column(6, mk("anot24")), column(6, mk("anot25")))
      ),
      tabPanel("Paralinguistico / no verbal",
        fluidRow(
          column(4, mk("anot26")),
          column(4, mk("anot28"), mk("anot29")),
          column(4, mk("anot30"))
        ),
        br(),
        fluidRow(
          column(6, mk("anot31"), mk("anot32")),
          column(6, mk("anot33"))
        )
      ),
      tabPanel("Emociones",
        br(),
        h6("Tono emocional (Ekman)"),
        uiOutput("emotion_ui"),
        sliderInput("emotion_likert", "Intensidad:", min = 1, max = 5,
                    value = 3, step = 1, width = "55%", ticks = TRUE),
        uiOutput("emotion_value_display")
      )
    ) # end tabsetPanel
    ) # end div.anot-box
  })

  # ============================================================
  # EDITOR DE VARIABLES
  # ============================================================
  observeEvent(input$open_var_editor, {
    defs <- rv$anot_defs
    # Construir UI del modal dinámicamente
    rows <- lapply(names(defs), function(id) {
      def <- defs[[id]]
      ch_str <- paste(def$choices[def$choices != ""], collapse = "\n")
      fluidRow(
        column(1, tags$b(id)),
        column(4, textInput(paste0("ve_label_", id), "Etiqueta:",
                            value = def$label, width = "100%")),
        column(7, textAreaInput(paste0("ve_choices_", id),
                                "Categorias (una por linea):",
                                value = ch_str, rows = 3, width = "100%"))
      )
    })

    showModal(modalDialog(
      title   = "Editor de variables de anotacion",
      size    = "l",
      easyClose = FALSE,
      div(style = "max-height:60vh; overflow-y:auto;", tagList(rows)),
      footer  = tagList(
        actionButton("ve_save",   "Guardar cambios", class = "btn-primary"),
        actionButton("ve_cancel", "Cancelar",        class = "btn-default")
      )
    ))
  })

  observeEvent(input$ve_cancel, removeModal())

  observeEvent(input$ve_save, {
    new_defs <- rv$anot_defs
    for (id in names(new_defs)) {
      lbl_val <- input[[paste0("ve_label_", id)]]
      ch_val  <- input[[paste0("ve_choices_", id)]]
      if (!is.null(lbl_val) && nzchar(trimws(lbl_val))) {
        new_defs[[id]]$label <- trimws(lbl_val)
      }
      if (!is.null(ch_val)) {
        ch_lines <- strsplit(ch_val, "\n", fixed = TRUE)[[1]]
        ch_clean <- trimws(ch_lines)
        ch_clean <- ch_clean[nzchar(ch_clean)]
        new_defs[[id]]$choices <- c("", ch_clean)
      }
    }
    rv$anot_defs <- new_defs
    save_etiquetas(new_defs)
    removeModal()
    showNotification("Variables actualizadas y guardadas.", type = "message", duration = 3)
  })

  observeEvent(input$reset_var_defs, {
    rv$anot_defs <- anot_defs_default
    if (file.exists(ETIQ_FILE)) file.remove(ETIQ_FILE)
    showNotification("Variables restauradas a los valores por defecto.", type = "message", duration = 3)
  })

  # ============================================================
  # ============================================================
  # FUNCIONES INTERNAS
  # ============================================================

  play_sound <- function(path) {
    os <- Sys.info()[["sysname"]]
    path <- normalizePath(path, winslash = "\\", mustWork = FALSE)
    if (os == "Darwin") {
      system2("afplay", shQuote(path), wait = FALSE)
    } else if (os == "Windows") {
      shell(sprintf("powershell -c (New-Object Media.SoundPlayer %s).PlaySync();",
                    shQuote(path)), wait = FALSE)
    } else {
      ok <- try(system2("aplay",  shQuote(path), wait = FALSE), silent = TRUE)
      if (inherits(ok, "try-error"))
        try(system2("paplay", shQuote(path), wait = FALSE), silent = TRUE)
    }
  }

  get_analysis_filename <- function(original_filename) {
    base_name <- tools::file_path_sans_ext(basename(original_filename))
    base_name <- sub("^analisis_", "", base_name)   # evitar doble prefijo
    ensure_dirs()
    file.path(ANALISIS_DIR, paste0("analisis_", base_name, ".txt"))
  }

  make_backup <- function(file_path) {
    if (!file.exists(file_path)) return(NULL)
    ts   <- format(Sys.time(), "%Y%m%d_%H%M%S")
    base <- basename(file_path)
    bk   <- file.path(BACKUP_DIR,
                      paste0(tools::file_path_sans_ext(base), "_backup_", ts,
                             ".", tools::file_ext(base)))
    file.copy(file_path, bk, overwrite = TRUE)
    bk
  }

  save_analysis_file <- function(df, filename, make_backup_copy = FALSE) {
    analysis_file <- get_analysis_filename(filename)
    if (make_backup_copy && file.exists(analysis_file)) {
      bp <- make_backup(analysis_file)
      message("Backup: ", bp)
    }
    write.table(df, analysis_file, sep = "\t", row.names = FALSE,
                quote = FALSE, na = "", fileEncoding = "UTF-8")
    update_consolidated_file(df, filename)
    analysis_file
  }

  update_consolidated_file <- function(df, filename) {
    ensure_dirs()
    cf <- file.path(ANALISIS_DIR, "analisis_todos.txt")
    df_with <- df
    df_with$filename <- basename(filename)
    if (file.exists(cf)) {
      existing <- tryCatch(
        read.table(cf, sep = "\t", header = TRUE, stringsAsFactors = FALSE,
                   fileEncoding = "UTF-8", quote = "", na.strings = ""),
        error = function(e) NULL
      )
      if (!is.null(existing)) {
        existing <- existing[existing$filename != basename(filename), ]
        if (nrow(existing) > 0) {
          all_cols <- union(names(existing), names(df_with))
          for (cn in setdiff(all_cols, names(existing))) existing[[cn]] <- NA
          for (cn in setdiff(all_cols, names(df_with)))  df_with[[cn]]  <- NA
          existing <- existing[, all_cols, drop = FALSE]
          df_with  <- df_with[,  all_cols, drop = FALSE]
          df_with  <- rbind(existing, df_with)
        }
      }
    }
    write.table(df_with, cf, sep = "\t", row.names = FALSE,
                quote = FALSE, na = "", fileEncoding = "UTF-8")
  }

  load_previous_analysis <- function(filename) {
    af <- get_analysis_filename(filename)
    if (!file.exists(af)) return(NULL)
    tryCatch(
      read.table(af, sep = "\t", header = TRUE, stringsAsFactors = FALSE,
                 fileEncoding = "UTF-8", quote = "", na.strings = ""),
      error = function(e) { message("Error cargando análisis previo: ", e$message); NULL }
    )
  }

  # ---- compute_measures (wrassp/seewave) ----
  compute_measures <- function(row_index) {
    df <- rv$df_full
    req(df, rv$audio_cached)

    start_t <- as.numeric(df$start[row_index])
    end_t   <- as.numeric(df$end[row_index])
    if (is.na(start_t) || is.na(end_t) || end_t <= start_t) return(NULL)

    pct <- if (is.null(input$quartile_pct) || is.na(input$quartile_pct))
             20 else input$quartile_pct

    tryCatch({
        # --- R: wrassp/ksvF0 ---
        wave_full <- rv$audio_cached
        fs  <- wave_full@samp.rate
        seg <- seewave::cutw(wave_full, from = start_t, to = end_t, output = "Wave", f = fs)
        tmp <- tempfile(fileext = ".wav")
        tuneR::writeWave(seg, filename = tmp)
        on.exit(unlink(tmp), add = TRUE)

        # F0
        f0_obj <- try(wrassp::ksvF0(tmp, toFile = FALSE), silent = TRUE)
        F0 <- F0_median <- F0_sd <- F0_range_st <-
          F0_delta_st <- F0_final_delta_st <- NA_real_
        F0_final_pattern <- NA_character_
        f0_times <- f0_vals <- numeric(0)

        if (!inherits(f0_obj, "try-error")) {
          f0_raw   <- f0_obj$F0
          f0_times_all <- seq(attr(f0_obj, "startTime"),
                              by = attr(f0_obj, "sampleRate")^-1,
                              length.out = length(f0_raw))
          sel     <- f0_raw > 0
          f0_vals  <- f0_raw[sel]
          f0_times <- f0_times_all[sel]

          if (length(f0_vals) > 0) {
            F0        <- mean(f0_vals,   na.rm = TRUE)
            F0_median <- median(f0_vals, na.rm = TRUE)
            F0_sd     <- if (length(f0_vals) > 1) sd(f0_vals, na.rm = TRUE) else NA_real_
            if (length(f0_vals) > 1) {
              # rango sobre percentiles 10–90 para excluir outliers
              f0_filt <- f0_vals[f0_vals >= quantile(f0_vals, 0.10) &
                                 f0_vals <= quantile(f0_vals, 0.90)]
              if (length(f0_filt) >= 2) {
                f0_min <- min(f0_filt); f0_max <- max(f0_filt)
              } else {
                f0_min <- min(f0_vals);  f0_max <- max(f0_vals)
              }
              if (f0_min > 0 && f0_max > 0) F0_range_st <- 12 * log2(f0_max / f0_min)
              f0_s <- f0_vals[1]; f0_e <- f0_vals[length(f0_vals)]
              if (f0_s > 0 && f0_e > 0) F0_delta_st <- 12 * log2(f0_e / f0_s)
              dur    <- f0_times_all[length(f0_times_all)] - f0_times_all[1]
              fin_st <- f0_times_all[length(f0_times_all)] - dur * 0.2
              sel_fin <- f0_times >= fin_st
              fin_f0  <- f0_vals[sel_fin]
              if (sum(sel_fin) >= 4) {
                n  <- length(fin_f0)
                br <- round(seq(1, n + 1, length.out = 5))
                qs <- sapply(1:4, function(q) mean(fin_f0[br[q]:(br[q+1]-1)], na.rm = TRUE))
                if (all(!is.na(qs) & qs > 0)) {
                  F0_final_delta_st <- 12 * log2(qs[4] / qs[1])
                  ds <- 12 * log2(qs[2:4] / qs[1:3])
                  if (all(is.finite(ds))) {
                    cd <- ifelse(ds > 0.5, "A", ifelse(ds < -0.5, "D", "P"))
                    F0_final_pattern <- paste0(cd, collapse = "")
                  }
                }
              }
            }
          }
        }

        # Intensidad
        rms_obj <- try(wrassp::rmsana(tmp, toFile = FALSE), silent = TRUE)
        Int <- Int_median <- Int_sd <- NA_real_
        in_vals <- in_times <- numeric(0)
        if (!inherits(rms_obj, "try-error")) {
          rms_raw <- rms_obj$rms
          sel_r   <- rms_raw > 0
          if (any(sel_r)) {
            in_vals    <- rms_raw[sel_r]
            in_db      <- 10 * log10(in_vals^2 + 1e-10)
            Int        <- mean(in_db,   na.rm = TRUE)
            Int_median <- median(in_db, na.rm = TRUE)
            Int_sd     <- if (length(in_db) > 1) sd(in_db, na.rm = TRUE) else NA_real_
          }
        }

        # Cuartiles con datos wrassp (tiempos relativos al segmento)
        qm <- get_quartile_metrics(
          pitch_df = if (length(f0_vals) > 0)
                       data.frame(time = f0_times, f0 = f0_vals)
                     else NULL,
          int_df   = if (length(in_vals) > 0)
                       data.frame(time = seq_along(in_vals) * 0.01,
                                  intensity = 10 * log10(in_vals^2 + 1e-10))
                     else NULL,
          t_start  = 0, t_end = end_t - start_t, pct = pct
        )

      list(
        F0               = F0,
        F0_median        = F0_median,
        F0_sd            = F0_sd,
        Int              = Int,
        Int_median       = Int_median,
        Int_sd           = Int_sd,
        F0_range_st      = F0_range_st,
        F0_delta_st      = F0_delta_st,
        F0_final_delta_st= F0_final_delta_st,
        F0_final_pattern = F0_final_pattern,
        F0_ini_q1 = qm$F0_ini[1], F0_ini_q2 = qm$F0_ini[2],
        F0_ini_q3 = qm$F0_ini[3], F0_ini_q4 = qm$F0_ini[4],
        F0_fin_q1 = qm$F0_fin[1], F0_fin_q2 = qm$F0_fin[2],
        F0_fin_q3 = qm$F0_fin[3], F0_fin_q4 = qm$F0_fin[4],
        Int_ini_q1= qm$Int_ini[1],Int_ini_q2= qm$Int_ini[2],
        Int_ini_q3= qm$Int_ini[3],Int_ini_q4= qm$Int_ini[4],
        Int_fin_q1= qm$Int_fin[1],Int_fin_q2= qm$Int_fin[2],
        Int_fin_q3= qm$Int_fin[3],Int_fin_q4= qm$Int_fin[4]
      )
    }, error = function(e) {
      showNotification(paste("Error en compute_measures:", e$message), type = "error")
      NULL
    })
  }

  # ============================================================
  # PROCESAMIENTO DE TEXTGRID
  # ============================================================

  # Detecta si el TextGrid es de MFA (tiers "words" y "phones")
  is_mfa_textgrid <- function(tg) {
    tier_names <- sapply(seq_len(tg.getNumberOfTiers(tg)), function(i) {
      tryCatch(tg.getTierName(tg, i), error = function(e) "")
    })
    any(grepl("words", tier_names, ignore.case = TRUE)) &&
      any(grepl("phones", tier_names, ignore.case = TRUE))
  }

  # Construye intonational phrases desde tier de palabras
  build_ips_from_words_tier <- function(tg, words_tier_idx,
                                         pause_min = 0.15,
                                         speaker_label = "IP") {
    n <- tg.getNumberOfIntervals(tg, words_tier_idx)
    ips <- list()
    ip_start <- NULL; ip_end <- NULL; ip_words <- character(0)

    flush_ip <- function() {
      if (!is.null(ip_start) && length(ip_words) > 0) {
        ips[[length(ips) + 1]] <<- list(
          start = ip_start, end = ip_end,
          label = paste(ip_words, collapse = " ")
        )
      }
    }

    for (j in seq_len(n)) {
      lbl <- trimws(tg.getLabel(tg, words_tier_idx, j))
      ts  <- tg.getIntervalStartTime(tg, words_tier_idx, j)
      te  <- tg.getIntervalEndTime(tg, words_tier_idx, j)
      dur <- te - ts

      if (!nzchar(lbl) || lbl %in% c("sp","<eps>","SIL","sil","<SIL>")) {
        # pausa: terminar IP si es suficientemente larga
        if (dur >= pause_min) {
          flush_ip()
          ip_start <- NULL; ip_end <- NULL; ip_words <- character(0)
        } else {
          # pausa corta: no cortar
        }
      } else {
        if (is.null(ip_start)) ip_start <- ts
        ip_end  <- te
        ip_words <- c(ip_words, lbl)
      }
    }
    flush_ip()

    if (length(ips) == 0) return(NULL)

    data.frame(
      speaker = rep(speaker_label, length(ips)),
      start   = sapply(ips, `[[`, "start"),
      end     = sapply(ips, `[[`, "end"),
      label   = sapply(ips, `[[`, "label"),
      stringsAsFactors = FALSE
    )
  }

  # Parsear TextGrid genérico → data.frame
  parse_textgrid <- function(tg, mfa_mode = FALSE, pause_min = 0.15) {
    nTiers <- tg.getNumberOfTiers(tg)
    tier_names <- sapply(seq_len(nTiers), function(i) {
      nm <- tryCatch(tg.getTierName(tg, i), error = function(e) paste0("Tier_", i))
      if (is.null(nm) || !nzchar(nm)) paste0("Tier_", i) else as.character(nm)
    })

    if (mfa_mode && is_mfa_textgrid(tg)) {
      # Agrupar tiers por hablante y extraer tier de words
      words_idx <- which(grepl("words", tier_names, ignore.case = TRUE))
      all_ip_dfs <- lapply(words_idx, function(wi) {
        spk <- sub("(_words|_WORDS)$", "", tier_names[wi], ignore.case = TRUE)
        if (!tg.isIntervalTier(tg, wi)) return(NULL)
        build_ips_from_words_tier(tg, wi, pause_min = pause_min,
                                  speaker_label = if (nzchar(spk)) spk else "IP")
      })
      all_ip_dfs <- Filter(Negate(is.null), all_ip_dfs)
      if (length(all_ip_dfs) == 0) return(NULL)
      return(do.call(rbind, all_ip_dfs))
    }

    # Modo por hablante: cada tier = un hablante
    all_tiers <- lapply(seq_len(nTiers), function(ti) {
      if (!tg.isIntervalTier(tg, ti)) return(NULL)
      n <- tg.getNumberOfIntervals(tg, ti)
      data.frame(
        speaker = rep(tier_names[ti], n),
        start   = sapply(seq_len(n), function(i) tg.getIntervalStartTime(tg, ti, i)),
        end     = sapply(seq_len(n), function(i) tg.getIntervalEndTime(tg, ti, i)),
        label   = sapply(seq_len(n), function(i) tg.getLabel(tg, ti, i)),
        stringsAsFactors = FALSE
      )
    })
    all_tiers <- Filter(Negate(is.null), all_tiers)
    if (length(all_tiers) == 0) return(NULL)
    do.call(rbind, all_tiers)
  }

  # ============================================================
  # PREPARAR DATA FRAME DESDE DATOS CRUDOS
  # ============================================================
  prepare_df <- function(df) {
    # columnas base
    base_cols <- c("F0_mean","F0_median","F0_sd","Int_mean","Int_median","Int_sd",
                   "F0_range_st","F0_delta_st","F0_final_delta_st","F0_final_pattern",
                   "n_palabras","palabras_por_seg","fonemas_por_seg")
    for (cn in base_cols) {
      if (!cn %in% names(df))
        df[[cn]] <- if (cn == "F0_final_pattern") NA_character_ else NA_real_
    }

    # cuartiles
    for (cn in quartile_col_names) {
      if (!cn %in% names(df)) df[[cn]] <- NA_real_
    }

    # anotaciones
    for (i in seq_len(n_anot)) {
      cn <- paste0("anot", i)
      if (!cn %in% names(df)) df[[cn]] <- NA_character_
    }
    if (!"observaciones" %in% names(df)) df$observaciones <- NA_character_

    # filtrar etiquetas vacías y ordenar
    if ("label" %in% names(df))
      df <- df[!is.na(df$label) & nzchar(trimws(df$label)), ]
    if ("start" %in% names(df))
      df <- df[order(df$start, na.last = TRUE), ]

    # palabras, fonemas y velocidad
    for (i in seq_len(nrow(df))) {
      if (!is.na(df$label[i]) && nzchar(trimws(df$label[i]))) {
        words <- strsplit(trimws(df$label[i]), "\\s+")[[1]]
        df$n_palabras[i] <- length(words[nzchar(words)])
        dur <- df$end[i] - df$start[i]
        if (!is.na(dur) && dur > 0) {
          df$palabras_por_seg[i] <- df$n_palabras[i] / dur
          nfonemas <- nchar(gsub("[[:space:][:punct:]]", "", df$label[i]))
          if (nfonemas > 0) df$fonemas_por_seg[i] <- nfonemas / dur
        }
      }
    }

    # contexto ±5
    if (!"contexto" %in% names(df)) df$contexto <- NA_character_
    n_rows <- nrow(df)
    for (i in seq_len(n_rows)) {
      filas_ctx <- max(1, i - 5):min(n_rows, i + 5)
      ctx <- mapply(function(sp, lb) {
        sp <- trimws(ifelse(is.na(sp), "", sp))
        lb <- trimws(ifelse(is.na(lb), "", lb))
        if (!nzchar(lb)) return("")
        if (nzchar(sp)) paste0(sp, ": ", lb) else lb
      }, df$speaker[filas_ctx], df$label[filas_ctx])
      df$contexto[i] <- paste(ctx[nzchar(ctx)], collapse = " | ")
    }

    # reordenar columnas
    col_ord <- make_col_order()
    df[, col_ord[col_ord %in% names(df)]]
  }

  # Restaurar análisis previo en un df nuevo
  restore_previous <- function(df, previous_data) {
    if (is.null(previous_data)) return(df)
    metric_cols <- c("F0_mean","F0_median","F0_sd","Int_mean","Int_median","Int_sd",
                     "F0_range_st","F0_delta_st","F0_final_delta_st","F0_final_pattern",
                     quartile_col_names)
    for (i in seq_len(nrow(df))) {
      mi <- which(
        abs(previous_data$start - df$start[i]) < 0.001 &
        abs(previous_data$end   - df$end[i])   < 0.001 &
        previous_data$label == df$label[i]
      )
      if (length(mi) == 0) next
      mi <- mi[1]
      for (mc in metric_cols) {
        if (mc %in% names(previous_data) && !is.na(previous_data[[mc]][mi]))
          df[[mc]][i] <- previous_data[[mc]][mi]
      }
      for (j in seq_len(n_anot)) {
        cn <- paste0("anot", j)
        if (cn %in% names(previous_data) &&
            !is.na(previous_data[[cn]][mi]) &&
            nzchar(previous_data[[cn]][mi]))
          df[[cn]][i] <- previous_data[[cn]][mi]
      }
      if ("observaciones" %in% names(previous_data) &&
          !is.na(previous_data$observaciones[mi]))
        df$observaciones[i] <- previous_data$observaciones[mi]
    }
    df
  }

  # Cargar audio (ruta o subido)
  load_audio <- function(path, is_mp4 = FALSE) {
    ext <- tolower(tools::file_ext(path))
    tmp_wav <- tempfile(fileext = ".wav")
    if (ext %in% c("mp3","mp4")) {
      av::av_audio_convert(path, tmp_wav, format = "wav")
      rv$audio_path   <- tmp_wav
      rv$audio_cached <- readWave(tmp_wav)
    } else {
      rv$audio_path   <- path
      rv$audio_cached <- readWave(path)
    }
    if (ext == "mp4") {
      vf <- paste0("video_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".mp4")
      vd <- file.path(video_temp_dir, vf)
      file.copy(path, vd, overwrite = TRUE)
      rv$video_path <- vd; rv$video_url <- paste0("tmpvideo/", vf); rv$is_video <- TRUE
    } else {
      rv$video_path <- NULL; rv$video_url <- NULL; rv$is_video <- FALSE
    }
  }

  # Pipeline completo de carga
  do_load_files <- function(audio_path, trans_path, trans_name) {
    t_start <- Sys.time()
    withProgress(message = "Cargando archivos...", value = 0, {

      incProgress(0.1, detail = "Audio...")
      tryCatch(
        load_audio(audio_path),
        error = function(e) {
          showNotification(paste("Error audio:", e$message), type = "error"); return()
        }
      )

      incProgress(0.3, detail = "Transcripcion...")
      df <- NULL
      tryCatch({
        ext <- tolower(tools::file_ext(trans_path))
        if (ext %in% c("csv","txt")) {
          df <- read.table(trans_path, header = TRUE,
                           sep = if (ext == "csv") "," else "\t",
                           stringsAsFactors = FALSE)
        } else if (ext == "textgrid") {
          tg <- tg.read(trans_path)
          df <- parse_textgrid(tg, mfa_mode = is_mfa_textgrid(tg), pause_min = 0.3)
        }
      }, error = function(e) {
        showNotification(paste("Error transcripción:", e$message), type = "error")
      })
      if (is.null(df)) return()

      incProgress(0.55, detail = "Procesando columnas...")
      df <- prepare_df(df)

      incProgress(0.75, detail = "Restaurando análisis previo...")
      rv$current_filename <- trans_name
      prev <- load_previous_analysis(trans_name)
      if (!is.null(prev)) {
        df <- restore_previous(df, prev)
        showNotification(sprintf("Análisis previo restaurado: %d filas", nrow(prev)),
                         type = "message", duration = 4)
      }

      incProgress(0.9, detail = "Guardando...")
      rv$df_full <- df
      rv$df      <- df
      rv$acoustic_done   <- FALSE
      rv$sequential_index<- 1

      bk <- !rv$initial_backup_done
      tryCatch({
        save_analysis_file(df, trans_name, make_backup_copy = bk)
        if (bk) rv$initial_backup_done <- TRUE
      }, error = function(e)
        showNotification(paste("Error guardando:", e$message), type = "warning"))


      incProgress(1, detail = "Completado")
    })

    elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))
    if (!is.null(rv$audio_cached)) {
      showNotification(
        sprintf("Cargado en %.1f s | Audio: %.1f s | %d filas",
                elapsed,
                length(rv$audio_cached@left) / rv$audio_cached@samp.rate,
                nrow(rv$df_full)),
        type = "message", duration = 6
      )
    }
  }


  # ============================================================
  # VISTA REACTIVA (fila actual)
  # ============================================================
  df_to_display <- reactive({
    req(rv$df_full)
    idx <- max(1, min(rv$sequential_index, nrow(rv$df_full)))
    row <- rv$df_full[idx, , drop = FALSE]
    data.frame(Fila = idx, speaker = row$speaker, label = row$label,
               contexto = row$contexto, stringsAsFactors = FALSE)
  })

  observe({ rv$df <- df_to_display() })

  # ============================================================
  # NAVEGACIÓN
  # ============================================================
  observeEvent(input$next_row, {
    req(rv$df_full)
    if (rv$sequential_index < nrow(rv$df_full))
      rv$sequential_index <- rv$sequential_index + 1
    else showNotification("Última fila.", type = "warning", duration = 2)
  })
  observeEvent(input$prev_row, {
    req(rv$df_full)
    if (rv$sequential_index > 1)
      rv$sequential_index <- rv$sequential_index - 1
    else showNotification("Primera fila.", type = "warning", duration = 2)
  })
  observeEvent(input$goto_row_btn, {
    req(rv$df_full)
    f <- as.integer(input$goto_row)
    if (is.na(f) || f < 1 || f > nrow(rv$df_full)) {
      showNotification(sprintf("Fila entre 1 y %d.", nrow(rv$df_full)), type = "warning")
    } else {
      rv$sequential_index <- f
    }
  })

  output$sequential_position <- renderText({
    req(rv$df_full)
    sprintf("Fila %d de %d", rv$sequential_index, nrow(rv$df_full))
  })

  output$sidebar_segment_info <- renderUI({
    req(rv$df_full, rv$selected_row_index)
    i   <- rv$selected_row_index
    row <- rv$df_full[i, , drop = FALSE]
    spk <- if (!is.null(row$speaker) && !is.na(row$speaker)) as.character(row$speaker) else "—"
    lbl <- if (!is.null(row$label)   && !is.na(row$label))   as.character(row$label)   else "—"
    div(
      style = paste("background:#f1f5f9; border-left:3px solid #2563eb;",
                    "border-radius:6px; padding:8px 10px; margin-bottom:10px;",
                    "font-size:13px; line-height:1.6;"),
      div(tags$span(style = "color:#6b7280; font-weight:600;", "Speaker: "),
          tags$span(style = "color:#2563eb; font-weight:500;", spk)),
      div(tags$span(style = "color:#6b7280; font-weight:600;", "Label: "),
          tags$span(style = "color:#374151; font-style:italic;", lbl))
    )
  })

  # ============================================================
  # TABLA PRINCIPAL
  # ============================================================
  output$table <- renderDT({
    req(rv$df)
    ctx_idx <- which(names(rv$df) == "contexto") - 1L
    col_defs <- if (length(ctx_idx) > 0 && !isTRUE(input$show_contexto))
      list(list(targets = ctx_idx, visible = FALSE))
    else
      list()
    datatable(rv$df, selection = "single", editable = TRUE,
              options = list(pageLength = 20, scrollX = TRUE,
                             columnDefs = col_defs),
              rownames = FALSE)
  }, server = TRUE)

  proxy <- dataTableProxy("table")

  observeEvent(input$table_cell_edit, {
    info <- input$table_cell_edit
    rv$df[info$row, info$col] <- info$value
  })

  # ============================================================
  # TABLA DE CONTEXTO
  # ============================================================
  output$context_table <- renderDT({
    req(rv$df_full, rv$selected_row_index, input$context_rows)
    idx    <- rv$selected_row_index
    nc     <- input$context_rows
    filas  <- max(1, idx - nc):min(nrow(rv$df_full), idx + nc)
    ctx_df <- data.frame(
      Fila     = filas,
      speaker  = rv$df_full$speaker[filas],
      label    = rv$df_full$label[filas],
      contexto = rv$df_full$contexto[filas],
      es_actual= (filas == idx),
      stringsAsFactors = FALSE
    )
    datatable(ctx_df,
      options = list(pageLength = 2 * nc + 1, scrollX = TRUE,
                     searching = FALSE, paging = FALSE,
                     columnDefs = list(list(targets = 4, visible = FALSE))),
      rownames = FALSE
    ) %>% formatStyle("es_actual", target = "row",
                      backgroundColor = styleEqual(c(TRUE,FALSE), c("#ffffcc","white")))
  })

  # ============================================================
  # OBSERVER PRINCIPAL: cambio de fila seleccionada
  # ============================================================
  observe({
    req(rv$df_full, rv$audio_cached, rv$sequential_index)
    i <- rv$sequential_index
    if (i < 1 || i > nrow(rv$df_full)) return()

    rv$selected_row_index <- i
    start_t <- as.numeric(rv$df_full$start[i])
    end_t   <- as.numeric(rv$df_full$end[i])
    rv$selected_start <- start_t
    rv$selected_end   <- end_t

    if (!is.na(start_t) && !is.na(end_t) && end_t > start_t) {
      tryCatch({
        wave_full <- rv$audio_cached
        fs  <- wave_full@samp.rate
        seg <- seewave::cutw(wave_full, from = start_t, to = end_t, output = "Wave", f = fs)
        rv$selected_segment <- seg
        rv$praatpic_temp_wav <- NULL  # invalidar caché praatpicture

        # Pitch para la gráfica (siempre con ksvF0 para rapidez)
        tmp <- tempfile(fileext = ".wav")
        tuneR::writeWave(seg, filename = tmp)
        f0_obj <- try(wrassp::ksvF0(tmp, toFile = FALSE), silent = TRUE)
        unlink(tmp)
        if (!inherits(f0_obj, "try-error")) {
          fv <- f0_obj$F0
          ft <- seq(attr(f0_obj,"startTime"), by = attr(f0_obj,"sampleRate")^-1,
                    length.out = length(fv))
          pd <- data.frame(time = ft, freq = fv)
          pd <- pd[pd$freq > 0 & pd$freq < 600 & is.finite(pd$freq), ]
          rv$pitch_data <- if (nrow(pd) > 0) pd else NULL
        } else rv$pitch_data <- NULL
      }, error = function(e) message("Error al extraer segmento: ", e$message))
    }

    # Calcular métricas si faltan
    if (is.na(rv$df_full$F0_mean[i]) || is.na(rv$df_full$Int_mean[i])) {
      res <- compute_measures(i)
      if (!is.null(res)) {
        rv$df_full$F0_mean[i]            <- res$F0
        rv$df_full$F0_median[i]          <- res$F0_median
        rv$df_full$F0_sd[i]             <- res$F0_sd
        rv$df_full$Int_mean[i]           <- res$Int
        rv$df_full$Int_median[i]         <- res$Int_median
        rv$df_full$Int_sd[i]            <- res$Int_sd
        rv$df_full$F0_range_st[i]        <- res$F0_range_st
        rv$df_full$F0_delta_st[i]        <- res$F0_delta_st
        rv$df_full$F0_final_delta_st[i]  <- res$F0_final_delta_st
        rv$df_full$F0_final_pattern[i]   <- res$F0_final_pattern
        for (cn in quartile_col_names)
          rv$df_full[[cn]][i] <- res[[cn]]
        if (!is.null(rv$current_filename))
          tryCatch(save_analysis_file(rv$df_full, rv$current_filename, make_backup_copy = FALSE),
                   error = function(e) NULL)
        rv$df <- df_to_display()
        replaceData(proxy, rv$df, resetPaging = FALSE, rownames = FALSE)
      }
    }

    # Cargar anotaciones en los inputs (anot27 se gestiona desde el tab Emociones)
    for (id in anot_ids_auto) {
      val <- rv$df_full[[id]][i]
      sel <- if (is.na(val) || !nzchar(val)) character(0) else
               unlist(strsplit(val, ";\\s*"))
      updateSelectInput(session, id, selected = sel)
    }
    updateTextAreaInput(session, "observaciones",
                        value = ifelse(is.na(rv$df_full$observaciones[i]), "",
                                       rv$df_full$observaciones[i]))
  })

  # ============================================================
  # GUARDAR ANOTACIONES
  # ============================================================
  observeEvent(input$save_annotation, {
    req(rv$df_full, rv$selected_row_index, rv$current_filename)
    i <- rv$selected_row_index
    if (is.null(i) || is.na(i) || i < 1 || i > nrow(rv$df_full)) {
      showNotification("No hay fila válida seleccionada.", type = "error"); return()
    }
    for (id in anot_ids_auto) {
      val <- input[[id]]
      rv$df_full[[id]][i] <- if (is.null(val) || length(val) == 0) NA_character_ else
                               paste(val, collapse = "; ")
    }
    rv$df_full$observaciones[i] <- if (is.null(input$observaciones) ||
                                        !nzchar(input$observaciones)) NA_character_ else
                                    input$observaciones

    tryCatch({
      save_analysis_file(rv$df_full, rv$current_filename, make_backup_copy = FALSE)
    }, error = function(e) {
      showNotification(paste("Error guardando:", e$message), type = "error"); return()
    })

    rv$df <- df_to_display()
    replaceData(proxy, rv$df, resetPaging = FALSE, rownames = FALSE)
    autosave_status(sprintf("Guardado (fila %d)", i))
    showNotification("Anotaciones guardadas.", type = "message", duration = 2)
  })

  # ============================================================
  # AUTO-GUARDADO AL CAMBIAR ANOTACIONES
  # ============================================================
  # anot27 se gestiona aparte desde el tab Emociones; excluirlo del autosave
  anot_ids_auto <- setdiff(paste0("anot", seq_len(n_anot)), "anot27")

  anot_inputs_r <- reactive({
    vals <- lapply(anot_ids_auto, function(id) input[[id]])
    names(vals) <- anot_ids_auto
    vals$observaciones <- input$observaciones
    vals
  })

  anot_inputs_debounced <- debounce(anot_inputs_r, 600)

  observeEvent(anot_inputs_debounced(), {
    req(rv$df_full, rv$selected_row_index, rv$current_filename)
    i <- rv$selected_row_index
    if (is.null(i) || is.na(i) || i < 1 || i > nrow(rv$df_full)) return()

    for (id in anot_ids_auto) {
      val <- input[[id]]
      rv$df_full[[id]][i] <- if (is.null(val) || length(val) == 0) NA_character_ else
                               paste(val, collapse = "; ")
    }
    rv$df_full$observaciones[i] <- if (is.null(input$observaciones) ||
                                        !nzchar(input$observaciones)) NA_character_ else
                                    input$observaciones

    tryCatch(
      save_analysis_file(rv$df_full, rv$current_filename, make_backup_copy = FALSE),
      error = function(e) NULL
    )
    rv$df <- df_to_display()
    replaceData(proxy, rv$df, resetPaging = FALSE, rownames = FALSE)
    autosave_status(sprintf("✓ Auto-guardado (fila %d)", i))
  }, ignoreInit = TRUE)

  # ============================================================
  # CALCULAR TODAS LAS FILAS
  # ============================================================
  observeEvent(input$compute_all, {
    req(rv$df_full, rv$audio_cached)

    n_rows    <- nrow(rv$df_full)
    t_start_g <- Sys.time()
    withProgress(message = "Calculando métricas...", value = 0, {
      for (i in seq_len(n_rows)) {
        res <- compute_measures(i)
        if (!is.null(res)) {
          rv$df_full$F0_mean[i]           <- res$F0
          rv$df_full$F0_median[i]         <- res$F0_median
          rv$df_full$F0_sd[i]            <- res$F0_sd
          rv$df_full$Int_mean[i]          <- res$Int
          rv$df_full$Int_median[i]        <- res$Int_median
          rv$df_full$Int_sd[i]           <- res$Int_sd
          rv$df_full$F0_range_st[i]       <- res$F0_range_st
          rv$df_full$F0_delta_st[i]       <- res$F0_delta_st
          rv$df_full$F0_final_delta_st[i] <- res$F0_final_delta_st
          rv$df_full$F0_final_pattern[i]  <- res$F0_final_pattern
          for (cn in quartile_col_names)
            rv$df_full[[cn]][i] <- res[[cn]]
        }
        incProgress(1/n_rows, detail = sprintf("Fila %d/%d", i, n_rows))
      }
    })
    rv$df <- df_to_display()
    replaceData(proxy, rv$df, resetPaging = FALSE, rownames = FALSE)
    if (!is.null(rv$current_filename))
      tryCatch(save_analysis_file(rv$df_full, rv$current_filename, make_backup_copy = FALSE),
               error = function(e) showNotification(paste("Error guardando:", e$message), type = "error"))
    elapsed <- as.numeric(difftime(Sys.time(), t_start_g, units = "secs"))
    showNotification(
      sprintf("Completado en %.1f min. F0: %d/%d, Int: %d/%d",
              elapsed/60, sum(!is.na(rv$df_full$F0_mean)), n_rows,
              sum(!is.na(rv$df_full$Int_mean)), n_rows),
      type = "message", duration = 6)
  })

  # ============================================================
  # MÉTRICAS
  # ============================================================
  output$metrics_display <- renderPrint({
    req(rv$df_full, rv$selected_row_index)
    i <- rv$selected_row_index
    r <- rv$df_full[i, , drop = FALSE]
    cat("===================================================\n")
    cat("  ANALISIS PROSODICO - Fila", i, "\n")
    cat("===================================================\n\n")
    cat("SEGMENTO:\n")
    cat("  Hablante:", r$speaker, "\n")
    cat("  Inicio:",  sprintf("%.3f s", r$start), "\n")
    cat("  Fin:",     sprintf("%.3f s", r$end), "\n")
    cat("  Duracion:",sprintf("%.3f s", r$end - r$start), "\n")
    cat("  Etiqueta:", r$label, "\n\n")
    # Pausas anterior y posterior
    df_all <- rv$df_full
    pausa_ant <- pausa_post <- NA_real_
    if (i > 1)            pausa_ant  <- as.numeric(r$start) - as.numeric(df_all$end[i - 1])
    if (i < nrow(df_all)) pausa_post <- as.numeric(df_all$start[i + 1]) - as.numeric(r$end)
    fmt_pausa <- function(p) if (!is.na(p) && p >= 0) sprintf("%.3f s", p) else "N/A"
    cat("PAUSAS:\n")
    cat("  Anterior: ",  fmt_pausa(pausa_ant),  "\n")
    cat("  Posterior:",  fmt_pausa(pausa_post), "\n\n")

    cat("TEXTO Y VELOCIDAD:\n")
    cat("  Palabras:",  ifelse(is.na(r$n_palabras), "N/A", r$n_palabras), "\n")
    cat("  Vel. pal/s:", if (!is.na(r$palabras_por_seg)) sprintf("%.2f pal/s", r$palabras_por_seg) else "N/A", "\n")
    cat("  Vel. fon/s:", if (!is.na(r$fonemas_por_seg))  sprintf("%.2f fon/s", r$fonemas_por_seg)  else "N/A", "\n\n")

    cat("F0:\n")
    cat("  Media:",       if (!is.na(r$F0_mean))           sprintf("%.1f Hz",  r$F0_mean)           else "N/A", "\n")
    cat("  Mediana:",     if (!is.na(r$F0_median))         sprintf("%.1f Hz",  r$F0_median)         else "N/A", "\n")
    cat("  SD:",          if (!is.na(r$F0_sd))             sprintf("%.1f Hz",  r$F0_sd)             else "N/A", "\n")
    cat("  Rango(p10-90):", if (!is.na(r$F0_range_st))    sprintf("%.2f st",  r$F0_range_st)       else "N/A", "\n")
    cat("  Inflexion:",   if (!is.na(r$F0_delta_st))       sprintf("%.2f st",  r$F0_delta_st)       else "N/A", "\n")
    cat("  Tonema(20%):", if (!is.na(r$F0_final_delta_st)) sprintf("%.2f st",  r$F0_final_delta_st) else "N/A", "\n")
    cat("  Patron:",      if (!is.na(r$F0_final_pattern))  as.character(r$F0_final_pattern)         else "N/A", "\n\n")

    cat("INTENSIDAD:\n")
    cat("  Media:",   if (!is.na(r$Int_mean))   sprintf("%.1f dB", r$Int_mean)   else "N/A", "\n")
    cat("  Mediana:", if (!is.na(r$Int_median)) sprintf("%.1f dB", r$Int_median) else "N/A", "\n")
    cat("  SD:",      if (!is.na(r$Int_sd))     sprintf("%.1f dB", r$Int_sd)     else "N/A", "\n\n")
    # Cuartiles
    pct <- if (is.null(input$quartile_pct)) 20 else input$quartile_pct
    cat(sprintf("CUARTILES (%d%% inicial):\n", pct))
    cat(sprintf("  F0:  Q1=%.1f  Q2=%.1f  Q3=%.1f  Q4=%.1f Hz\n",
                ifelse(is.na(r$F0_ini_q1),0,r$F0_ini_q1), ifelse(is.na(r$F0_ini_q2),0,r$F0_ini_q2),
                ifelse(is.na(r$F0_ini_q3),0,r$F0_ini_q3), ifelse(is.na(r$F0_ini_q4),0,r$F0_ini_q4)))
    cat(sprintf("  Int: Q1=%.1f  Q2=%.1f  Q3=%.1f  Q4=%.1f dB\n",
                ifelse(is.na(r$Int_ini_q1),0,r$Int_ini_q1), ifelse(is.na(r$Int_ini_q2),0,r$Int_ini_q2),
                ifelse(is.na(r$Int_ini_q3),0,r$Int_ini_q3), ifelse(is.na(r$Int_ini_q4),0,r$Int_ini_q4)))
    cat(sprintf("CUARTILES (%d%% final):\n", pct))
    cat(sprintf("  F0:  Q1=%.1f  Q2=%.1f  Q3=%.1f  Q4=%.1f Hz\n",
                ifelse(is.na(r$F0_fin_q1),0,r$F0_fin_q1), ifelse(is.na(r$F0_fin_q2),0,r$F0_fin_q2),
                ifelse(is.na(r$F0_fin_q3),0,r$F0_fin_q3), ifelse(is.na(r$F0_fin_q4),0,r$F0_fin_q4)))
    cat(sprintf("  Int: Q1=%.1f  Q2=%.1f  Q3=%.1f  Q4=%.1f dB\n",
                ifelse(is.na(r$Int_fin_q1),0,r$Int_fin_q1), ifelse(is.na(r$Int_fin_q2),0,r$Int_fin_q2),
                ifelse(is.na(r$Int_fin_q3),0,r$Int_fin_q3), ifelse(is.na(r$Int_fin_q4),0,r$Int_fin_q4)))
    cat("\nANOTACIONES:\n")
    any_anot <- FALSE
    for (j in seq_len(n_anot)) {
      cn  <- paste0("anot", j)
      val <- r[[cn]]
      if (!is.na(val) && nzchar(trimws(val))) {
        lbl <- rv$anot_defs[[cn]]$label
        cat(sprintf("  [%s] %s: %s\n", cn, lbl, val))
        any_anot <- TRUE
      }
    }
    if (!any_anot) cat("  (sin anotaciones)\n")
    if (!is.na(r$observaciones) && nzchar(trimws(r$observaciones)))
      cat("\nOBSERVACIONES:\n ", gsub("\n","\n  ", r$observaciones), "\n")
    cat("===================================================\n")
  })

  # ============================================================
  # GRÁFICAS
  # ============================================================
  output$video_player <- renderUI({
    if (!rv$is_video || is.null(rv$video_url) || is.null(rv$selected_start)) return(NULL)
    vid_id <- paste0("vid_", round(runif(1) * 1e5))
    tagList(
      h4("Video del segmento"),
      tags$video(id = vid_id, width = "100%", height = "300px",
                 controls = "controls", preload = "auto",
                 tags$source(src = rv$video_url, type = "video/mp4"),
                 "Tu navegador no soporta video."),
      tags$script(HTML(sprintf(
        "(function(){var v=document.getElementById('%s');
         if(v){v.load();v.onloadedmetadata=function(){
           if(Number.isFinite(%f)) v.currentTime=%f;
         };}})();",
        vid_id, round(rv$selected_start,3), round(rv$selected_start,3)
      ))),
      p(sprintf("Segmento: %.2f – %.2f s (%.2f s)",
                rv$selected_start, rv$selected_end,
                rv$selected_end - rv$selected_start),
        style = "color:#666; font-size:12px;")
    )
  })

  output$oscillo_plot <- renderPlot({
    req(rv$selected_segment)
    seewave::oscillo(rv$selected_segment, f = rv$selected_segment@samp.rate,
                     k = 1, colwave = "steelblue")
    title("Oscilograma")
  })

  output$spectro_plot <- renderPlot({
    req(rv$selected_segment)
    seg <- rv$selected_segment
    if (!inherits(seg, "Wave")) { plot.new(); text(0.5,0.5,"No Wave"); return() }
    fs <- seg@samp.rate; n <- length(seg@left)
    if (n < 32) { plot.new(); text(0.5,0.5,"Segmento muy corto"); return() }
    wl <- min(256L, n)
    tryCatch(
      seewave::spectro(seg, f = fs, wl = wl, ovlp = 85, osc = FALSE, scale = TRUE),
      error = function(e) { plot.new(); text(0.5,0.5, paste("Error:", e$message)) }
    )
    title("Espectrograma")
  })

  output$pitch_plot <- renderPlot({
    if (is.null(rv$pitch_data) || nrow(rv$pitch_data) == 0) {
      plot.new(); title("Curva melodica (F0)")
      text(0.5, 0.5, "Sin valores de F0 detectados", cex = 1.2, col = "gray50")
      return()
    }
    plot(rv$pitch_data$time, rv$pitch_data$freq, type = "b", pch = 19,
         col = "dodgerblue3", lwd = 2, cex = 1.2,
         xlab = "Tiempo (s)", ylab = "Frecuencia (Hz)",
         main = sprintf("Curva melodica (F0) – %d puntos", nrow(rv$pitch_data)))
    grid(col = "gray80", lwd = 1)
  })

  # ============================================================
  # PRAATPICTURE
  # ============================================================
  observeEvent(input$render_praatpic, {
    req(HAS_PRAATPICTURE, rv$selected_segment)
    tmp <- tempfile(fileext = ".wav")
    tuneR::writeWave(rv$selected_segment, filename = tmp)
    rv$praatpic_temp_wav <- tmp
  })

  output$praatpicture_plot <- renderPlot({
    req(HAS_PRAATPICTURE, rv$praatpic_temp_wav)
    req(file.exists(rv$praatpic_temp_wav))

    # Construir qué paneles mostrar
    what <- c()
    if (isTRUE(input$pp_show_wave))  what <- c(what, "sound")
    if (isTRUE(input$pp_show_spec))  what <- c(what, "spectrogram")
    if (isTRUE(input$pp_show_pitch)) what <- c(what, "pitch")
    if (isTRUE(input$pp_show_int))   what <- c(what, "intensity")
    if (length(what) == 0) what <- "sound"

    # Proporciones iguales que sumen 100
    n_frames <- length(what)
    base_p   <- floor(100 / n_frames)
    prop     <- rep(base_p, n_frames)
    prop[n_frames] <- 100 - sum(prop[-n_frames])

    tryCatch(
      praatpicture::praatpicture(rv$praatpic_temp_wav,
                                 frames     = what,
                                 proportion = prop),
      error = function(e) {
        plot.new()
        text(0.5, 0.5, paste("Error praatpicture:", e$message), col = "red", cex = 0.9)
      }
    )
  })

  # ============================================================
  # REPRODUCCIÓN DE AUDIO
  # ============================================================
  play_row_audio <- function(context_before = 0, context_after = 0) {
    req(rv$df_full, rv$selected_row_index, rv$audio_cached)
    i <- rv$selected_row_index
    if (is.null(i) || i < 1 || i > nrow(rv$df_full)) {
      showNotification("Sin fila válida.", type = "error"); return()
    }
    start_t <- as.numeric(rv$df_full$start[i])
    end_t   <- as.numeric(rv$df_full$end[i])
    if (is.na(start_t) || is.na(end_t)) {
      showNotification("Tiempos inválidos.", type = "error"); return()
    }
    wave_full <- rv$audio_cached
    total_dur <- length(wave_full@left) / wave_full@samp.rate
    s0 <- max(0, start_t - context_before)
    e0 <- min(total_dur, end_t + context_after)
    fs  <- wave_full@samp.rate
    seg <- seewave::cutw(wave_full, from = s0, to = e0, output = "Wave", f = fs)
    tmp <- tempfile(fileext = ".wav")
    tuneR::writeWave(seg, filename = tmp)
    play_sound(tmp)
    showNotification(sprintf("Reproduciendo %.2f s", e0 - s0),
                     type = "message", duration = 2)
  }

  observeEvent(input$play_segment,   play_row_audio())
  observeEvent(input$play_segment1,  play_row_audio())
  observeEvent(input$play_with_context, {
    cb <- if (is.null(input$context_before) || is.na(input$context_before)) 0 else input$context_before
    ca <- if (is.null(input$context_after)  || is.na(input$context_after))  0 else input$context_after
    play_row_audio(context_before = cb, context_after = ca)
  })

  # ============================================================
  # EXPORTACIÓN
  # ============================================================

  # ============================================================
  # ESTADÍSTICAS
  # ============================================================

  # Columnas numéricas disponibles para boxplot
  stat_num_cols <- c(
    "F0_mean","F0_median","F0_sd","F0_range_st","F0_delta_st","F0_final_delta_st",
    "Int_mean","Int_median","Int_sd",
    "n_palabras","palabras_por_seg","fonemas_por_seg"
  )

  # Helper: etiqueta legible para columnas
  stat_col_label <- function(cn) {
    map <- c(
      F0_mean = "F0 media (Hz)", F0_median = "F0 mediana (Hz)", F0_sd = "F0 SD (Hz)",
      F0_range_st = "Rango F0 (st)", F0_delta_st = "Inflexión F0 (st)",
      F0_final_delta_st = "Tonema delta (st)",
      Int_mean = "Intensidad media (dB)", Int_median = "Intensidad mediana (dB)",
      Int_sd = "Intensidad SD (dB)",
      n_palabras = "N.º palabras", palabras_por_seg = "Palabras/s",
      fonemas_por_seg = "Fonemas/s"
    )
    if (cn %in% names(map)) map[[cn]] else cn
  }

  # Actualizar selectores cuando cambia df_full
  observe({
    req(rv$df_full)
    df <- rv$df_full

    # Variables categóricas: speaker + anotaciones con al menos 2 valores distintos
    cat_choices <- c()
    if ("speaker" %in% names(df) && length(unique(na.omit(df$speaker))) >= 2)
      cat_choices <- c(cat_choices, c("Hablante" = "speaker"))
    for (j in seq_len(n_anot)) {
      cn  <- paste0("anot", j)
      if (!cn %in% names(df)) next
      vals <- na.omit(df[[cn]])
      vals <- vals[nzchar(vals)]
      if (length(unique(vals)) >= 2) {
        lbl <- if (!is.null(rv$anot_defs[[cn]])) rv$anot_defs[[cn]]$label else cn
        lbl <- sub(":$", "", trimws(lbl))
        cat_choices <- c(cat_choices, setNames(cn, lbl))
      }
    }
    if (length(cat_choices) == 0) cat_choices <- c("(sin datos)" = "")
    updateSelectInput(session, "stat_cat_var", choices = cat_choices)

    # Variables numéricas con datos
    num_choices <- sapply(stat_num_cols, function(cn) {
      cn %in% names(df) && sum(!is.na(df[[cn]])) >= 2
    })
    num_avail <- stat_num_cols[num_choices]
    num_labels <- setNames(num_avail, sapply(num_avail, stat_col_label))
    if (length(num_labels) == 0) num_labels <- c("(sin datos)" = "")
    updateSelectInput(session, "stat_num_var", choices = num_labels)

    # Grupo (para boxplot): speaker + anotaciones categóricas con pocos niveles
    grp_choices <- c("(sin agrupación)" = "")
    if ("speaker" %in% names(df) && length(unique(na.omit(df$speaker))) >= 2)
      grp_choices <- c(grp_choices, c("Hablante" = "speaker"))
    for (j in seq_len(n_anot)) {
      cn  <- paste0("anot", j)
      if (!cn %in% names(df)) next
      vals <- na.omit(df[[cn]]); vals <- vals[nzchar(vals)]
      n_lev <- length(unique(vals))
      if (n_lev >= 2 && n_lev <= 10) {
        lbl <- if (!is.null(rv$anot_defs[[cn]])) rv$anot_defs[[cn]]$label else cn
        lbl <- sub(":$", "", trimws(lbl))
        grp_choices <- c(grp_choices, setNames(cn, lbl))
      }
    }
    updateSelectInput(session, "stat_group_var", choices = grp_choices)
  })

  # --- Gráfico de barras ---
  output$stat_barplot <- renderPlot({
    input$stat_bar_update
    req(rv$df_full, nzchar(input$stat_cat_var %||% ""))
    cn   <- input$stat_cat_var
    df   <- rv$df_full
    if (!cn %in% names(df)) return(NULL)
    vals <- df[[cn]]
    vals <- na.omit(vals[nzchar(ifelse(is.na(vals), "", vals))])
    # Separar valores múltiples (guardados con "; ")
    vals <- unlist(strsplit(as.character(vals), ";\\s*"))
    vals <- trimws(vals); vals <- vals[nzchar(vals)]
    if (length(vals) == 0) { plot.new(); text(.5,.5,"Sin datos"); return() }

    tbl <- sort(table(vals), decreasing = TRUE)
    if (input$stat_bar_type == "pct") {
      tbl <- tbl / sum(tbl) * 100
      ylab <- "Porcentaje (%)"
      fmt  <- function(x) sprintf("%.1f%%", x)
    } else {
      ylab <- "Frecuencia (n)"
      fmt  <- function(x) as.character(x)
    }
    lbl <- if (!is.null(rv$anot_defs[[cn]])) sub(":$","",rv$anot_defs[[cn]]$label) else cn
    par(mar = c(8, 5, 3, 1))
    bp <- barplot(tbl, col = "#3b82f6", border = "white",
                  main = lbl, ylab = ylab, las = 2,
                  ylim = c(0, max(tbl) * 1.1),  # margen superior para la etiqueta de la barra más alta
                  cex.names = 0.8, cex.axis = 0.9, cex.main = 1)
    text(bp, tbl + max(tbl) * 0.02, labels = fmt(tbl),
         cex = 0.75, adj = c(0.5, 0))
  })

  # --- Boxplot ---
  output$stat_boxplot <- renderPlot({
    input$stat_box_update
    req(rv$df_full, nzchar(input$stat_num_var %||% ""))
    cn    <- input$stat_num_var
    grp   <- input$stat_group_var
    df    <- rv$df_full
    if (!cn %in% names(df)) return(NULL)
    lbl   <- stat_col_label(cn)

    if (!is.null(grp) && nzchar(grp) && grp %in% names(df)) {
      df2   <- df[!is.na(df[[cn]]) & !is.na(df[[grp]]) & nzchar(df[[grp]]), ]
      grp_v <- factor(df2[[grp]])
      par(mar = c(9, 5, 3, 1))
      boxplot(df2[[cn]] ~ grp_v,
              col = "#93c5fd", border = "#1d4ed8",
              main = lbl, ylab = lbl, xlab = "",
              las = 2, cex.axis = 0.8, outline = FALSE)
      stripchart(df2[[cn]] ~ grp_v, vertical = TRUE,
                 method = "jitter", add = TRUE,
                 pch = 20, col = "#1d4ed880", cex = 0.6)
    } else {
      vals <- na.omit(df[[cn]])
      par(mar = c(3, 5, 3, 1))
      boxplot(vals, col = "#93c5fd", border = "#1d4ed8",
              main = lbl, ylab = lbl, outline = FALSE,
              horizontal = FALSE)
      stripchart(vals, vertical = TRUE, method = "jitter",
                 add = TRUE, pch = 20, col = "#1d4ed880", cex = 0.7)
    }
  })

  # Kurtosis y asimetría (sin paquetes extra)
  stat_skewness <- function(x) {
    x <- na.omit(x); n <- length(x)
    if (n < 3) return(NA_real_)
    m <- mean(x); s <- sd(x)
    if (s == 0) return(NA_real_)
    (sum((x - m)^3) / n) / s^3
  }
  stat_kurtosis <- function(x) {
    x <- na.omit(x); n <- length(x)
    if (n < 4) return(NA_real_)
    m <- mean(x); s <- sd(x)
    if (s == 0) return(NA_real_)
    (sum((x - m)^4) / n) / s^4 - 3   # kurtosis de exceso
  }

  output$stat_summary <- renderPrint({
    input$stat_box_update
    req(rv$df_full, nzchar(input$stat_num_var %||% ""))
    cn  <- input$stat_num_var
    df  <- rv$df_full
    if (!cn %in% names(df)) return(invisible(NULL))
    grp <- input$stat_group_var

    fmt <- function(x) if (is.na(x)) "N/A" else sprintf("%.4g", x)

    print_stats <- function(vals, titulo = NULL) {
      vals <- na.omit(vals)
      if (!is.null(titulo)) cat(sprintf("\n── %s (n=%d) ──\n", titulo, length(vals)))
      else cat(sprintf("n = %d\n", length(vals)))
      cat(sprintf("  Mínimo:    %s\n", fmt(min(vals))))
      cat(sprintf("  Máximo:    %s\n", fmt(max(vals))))
      cat(sprintf("  Mediana:   %s\n", fmt(median(vals))))
      cat(sprintf("  Media:     %s\n", fmt(mean(vals))))
      cat(sprintf("  Asimetría: %s\n", fmt(stat_skewness(vals))))
      cat(sprintf("  Curtosis:  %s  (exceso)\n", fmt(stat_kurtosis(vals))))
    }

    lbl <- stat_col_label(cn)
    cat("===", lbl, "===\n")
    if (!is.null(grp) && nzchar(grp) && grp %in% names(df)) {
      df2  <- df[!is.na(df[[cn]]) & !is.na(df[[grp]]) & nzchar(df[[grp]]), ]
      levs <- sort(unique(df2[[grp]]))
      for (lv in levs) print_stats(df2[[cn]][df2[[grp]] == lv], titulo = lv)
      cat("\n── TOTAL ──\n"); print_stats(df2[[cn]])
    } else {
      print_stats(df[[cn]])
    }
  })

}

shinyApp(ui, server)
