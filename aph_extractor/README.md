# Análisis Prosódico del Habla (APH)

Aplicación R/Shiny para el análisis prosódico tridimensional del habla siguiendo la metodología APH (Cantero Serena 2019): análisis melódico (F0), dinámico (intensidad) y rítmico (distancias interonset / IOI).

---

## Demo online

**[▶ Abrir demo (GitHub Pages)](https://acabedo.github.io/aph/)**

> **Nota sobre el tiempo de carga:** la demo se ejecuta mediante [Shinylive](https://shiny.posit.co/py/docs/shinylive.html) (R en WebAssembly, directamente en el navegador, sin servidor). La primera carga descarga el entorno de ejecución de R (~50 MB); puede tardar entre 30 y 90 segundos según la conexión. En local, la app arranca en menos de 3 segundos con `shiny::runApp("app.R")`.

> **Funciones desactivadas en la demo:** algunas funciones no están disponibles en la versión online por limitaciones de WebAssembly, como la **exportación a HTML** o la **exportación en masa**. Para acceder a todas las funcionalidades, descarga `app.R` y ejecútalo localmente desde **RStudio** o **[Positron](https://positron.posit.co/)**.

---

## Archivos

| Archivo / Carpeta | Descripción |
|---|---|
| `app.R` | Aplicación Shiny principal |
| `docs/` | Demo exportada con Shinylive (GitHub Pages) |
| `Extraccion_datos_v6.praat` | Script Praat para extraer F0, intensidad y tiempos desde TextGrids |
| `Extraccion_datos_v5.praat` | Versión anterior del script de extracción |
| `whisper_batch_align.praat` | Script Praat para segmentación con Silero VAD + transcripción Whisper + alineación fonémica |

---

## Requisitos

- R ≥ 4.2
- Paquetes R: `shiny`, `plotly`, `dplyr`, `DT`, `readr`
- Praat ≥ 6.4.62 (para los scripts `.praat`)
- Para `whisper_batch_align.praat`: Praat con soporte Silero/Whisper (plugin WhisperPraat o equivalente) y modelo `ggml-large-v3-turbo-q8_0.bin` en `~/Library/Preferences/Praat Prefs/models/`

Instalar paquetes R desde la consola:

```r
install.packages(c("shiny", "plotly", "dplyr", "DT", "readr"))
```

---

## Uso

### 1. Ejecutar la app

```r
shiny::runApp("app.R")
```

O desde RStudio: abrir `app.R` y pulsar **Run App**.

### 2. Cargar datos

**Opción A — Datos de ejemplo integrados**

Ir a la pestaña *Pegar CSV* y pulsar **Pegar datos de ejemplo**. La app incluye cuatro frases de ejemplo:

| ID | Frase | Nota |
|---|---|---|
| `ejemplo` | «Cuando el Villarreal gane la liga me teñiré el pelo» | F0 simulado |
| `ejemplo2` | «Es el vecino el que elige al alcalde…» | F0 simulado |
| `ejemplo3` | «Lo peor que hacen los malos es obligarnos a dudar de los buenos» | F0 simulado |
| `cantero2019` | «sigo en contacto con ellos» | Datos reales — Cantero Serena (2019) |

**Opción B — CSV propio**

Pegar el contenido del CSV directamente en el área de texto, o cargar el archivo con **Cargar CSV**. El CSV debe tener separador de tabulaciones y la siguiente cabecera:

```
file	tier_num	tier_name	label	time_start	time_end	duration_ms	f0_mean_hz	int_mean_db	f0_q1_hz	f0_q2_hz	f0_q3_hz	f0_q4_hz	q1_to_q2_pct	q2_to_q3_pct	q3_to_q4_pct
```

Las columnas `f0_q1_hz`–`q3_to_q4_pct` son opcionales (se usan para mostrar cuartiles Q1–Q4 e inflexiones internas). Se generan con `Extraccion_datos_v6.praat`.

### 3. Navegar y visualizar

- **Pestaña Gráfico APH**: gráfico interactivo Plotly con curvas melódica, dinámica y rítmica.
- Selector de archivo (*file*), tier y *utterance* en el panel lateral.
- Botones ⏮ ◀ ▶ ⏭ para navegar entre *utterances* sin tocar el ratón.
- Botón **✕ Ocultar / ☰ Mostrar** para expandir el gráfico a pantalla completa.
- Umbral de ascenso tonal (%) para marcar picos e inflexiones.
- Opción de mostrar cuartiles Q1–Q4 para vocales con inflexión interna.

### 4. Exportar

- **Exportar HTML**: descarga el gráfico + tabla en un único archivo `.html` autocontenido. *(Desactivado en la demo online)*
- **Exportar PNG**: usa el mecanismo nativo de Plotly (botón de cámara en la barra de herramientas del gráfico).
- **Exportar tabla (.tsv)**: descarga la tabla APH en formato TSV.
- **Exportación en masa**: disponible solo en local. *(Desactivado en la demo online)*

> Para usar todas las funciones de exportación, descarga `app.R` y ejecútalo desde **RStudio** (`shiny::runApp("app.R")`) o desde **[Positron](https://positron.posit.co/)**.

---

## Flujo de trabajo completo (desde audio)

```
Audio WAV
   ↓  whisper_batch_align.praat
TextGrid (tiers: utterances / VAD/word / phones)
   ↓  Extraccion_datos_v6.praat
CSV con F0, intensidad, tiempos, cuartiles
   ↓  app.R (Shiny)
Gráfico APH + tabla + exportación HTML/PNG
```

---

## Formato del CSV

Cada fila representa un intervalo no vacío de un tier de Praat. Los tiers reconocidos son:

| Tipo | Nombres aceptados |
|---|---|
| Utterance | `utterances`, `utterance`, `sentence`, `sentences`, `utt`, `silero` |
| Palabras | `words`, `word`, `VAD/word`, `palabras`, `palabra` |
| Fonemas | `phones`, `phone`, `phonemes`, `phoneme`, `fonemas`, `fonema`, `segments`, `segment` |

Las etiquetas de vocales reconocidas incluyen `a e i o u` (y variantes con diacríticos: á é í ó ú, à è ì ò ù, ä ë ï ö ü) más `@`, `ə`, `a:`, `e:`, `i:`, `o:`, `u:`.

---

## Metodología

El análisis APH cuantifica tres dimensiones prosódicas normalizando todos los valores con la primera vocal de la *utterance* como referencia (= 100):

- **Melódica** (F0): curva de frecuencia fundamental en Hz o porcentaje relativo.
- **Dinámica** (intensidad): curva de intensidad en dB o porcentaje relativo.
- **Rítmica** (IOI): distancia interonset entre vocales — `IOI[1] = time_start[1] - t0` (tiempo desde el inicio de la *utterance* hasta la primera vocal); `IOI[n] = time_start[n] - time_start[n-1]`.

Las **inflexiones tonales** significativas se identifican cuando el ascenso entre cuartiles Q1→Q2 supera el umbral configurado (por defecto 15%).

---

## Referencia

Cantero Serena, F. J. (2019). Análisis prosódico del habla: más allá de la melodía. *Phonica*, 15, 1–37.

---

## Licencia

GPL 3
