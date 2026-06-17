# ============================================================================
# app.R — Análisis Prosódico del Habla (APH)
# ============================================================================

library(shiny)
library(plotly)
library(dplyr)
library(DT)
library(readr)

options(shiny.maxRequestSize = 200 * 1024^2)  # 200 MB

# ── Constantes ───────────────────────────────────────────────────────────────

VOWELS <- c(
  "a", "e", "i", "o", "u",
  "A", "E", "I", "O", "U",
  "á", "é", "í", "ó", "ú",
  "à", "è", "ì", "ò", "ù",
  "ä", "ë", "ï", "ö", "ü",
  "@", "ə", "a:", "e:", "i:", "o:", "u:"
)

TIER_UTT   <- c("utterance", "utterances", "sentence", "sentences", "utt", "silero")
TIER_WORD  <- c("word", "words", "VAD/word", "palabra", "palabras")
TIER_PHONE <- c("phone", "phones", "phoneme", "phonemes", "segment", "segments", "fonema", "fonemas")

SCRIPT_DIR <- normalizePath(getwd())
SCRIPT1    <- file.path(SCRIPT_DIR, "whisper_batch_align.praat")
SCRIPT2    <- file.path(SCRIPT_DIR, "Extraccion_datos_v6.praat")

# Cuatro frases de ejemplo (tres simuladas + cantero2019 con datos reales del PDF).
# Vocales con inflexión interna significativa (|q1_to_q2_pct| > 15%):
#   ejemplo:     'a' de Villarreal (ascenso focal), 'e' tónica de teñiré (caída)
#   ejemplo2:    'i' tónica de elige (pico focal)
#   ejemplo3:    'o' de peor (pico inicial), 'a' de obliGAR (acento nuclear)
#   cantero2019: 'e' de ellos (inflexión circumfleja, +26.6%) — datos reales PDF
SAMPLE_CSV <- paste(c(
  "file\ttier_num\ttier_name\tlabel\ttime_start\ttime_end\tduration_ms\tf0_mean_hz\tint_mean_db\tf0_q1_hz\tf0_q2_hz\tf0_q3_hz\tf0_q4_hz\tq1_to_q2_pct\tq2_to_q3_pct\tq3_to_q4_pct",
  "ejemplo\t1\tutterances\tCuando el Villarreal gane la liga me teñiré el pelo\t0.00\t3.20\t3200\t213.5\t68.4\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo\t2\twords\tcuando\t0.00\t0.40\t400\t218.2\t69.5\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo\t2\twords\tel\t0.40\t0.50\t100\t224.8\t67.3\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo\t2\twords\tVillarreal\t0.50\t1.05\t550\t255.8\t72.1\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo\t2\twords\tgane\t1.05\t1.35\t300\t234.2\t68.9\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo\t2\twords\tla\t1.35\t1.48\t130\t222.5\t66.8\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo\t2\twords\tliga\t1.48\t1.75\t270\t212.4\t66.2\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo\t2\twords\tme\t1.75\t1.88\t130\t204.7\t64.1\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo\t2\twords\tteñiré\t1.88\t2.35\t470\t191.8\t68.3\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo\t2\twords\tel\t2.35\t2.48\t130\t174.2\t64.0\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo\t2\twords\tpelo\t2.48\t3.20\t720\t158.3\t63.1\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo\t3\tphones\tu\t0.06\t0.12\t60\t215.0\t66.2\t212.0\t215.0\t216.0\t214.0\t-1.4\t0.5\t-0.9",
  "ejemplo\t3\tphones\ta\t0.12\t0.24\t120\t225.1\t70.2\t222.0\t225.0\t227.0\t225.0\t-1.3\t0.9\t-0.9",
  "ejemplo\t3\tphones\to\t0.34\t0.40\t60\t220.5\t67.1\t218.0\t221.0\t222.0\t220.0\t-1.4\t0.5\t-0.9",
  "ejemplo\t3\tphones\te\t0.40\t0.46\t60\t226.3\t65.8\t224.0\t226.0\t228.0\t225.0\t-0.9\t0.9\t-1.3",
  "ejemplo\t3\tphones\ti\t0.55\t0.62\t70\t242.1\t69.4\t238.0\t242.0\t245.0\t241.0\t-1.7\t1.2\t-1.6",
  "ejemplo\t3\tphones\ta\t0.68\t0.76\t80\t262.4\t73.2\t220.0\t262.0\t271.0\t258.0\t19.1\t3.4\t-4.8",
  "ejemplo\t3\tphones\te\t0.80\t0.88\t80\t254.8\t71.5\t251.0\t255.0\t257.0\t254.0\t-1.6\t0.8\t-1.2",
  "ejemplo\t3\tphones\ta\t0.88\t0.96\t80\t247.5\t70.3\t244.0\t248.0\t249.0\t247.0\t-1.6\t0.4\t-0.8",
  "ejemplo\t3\tphones\ta\t1.10\t1.22\t120\t237.8\t69.1\t234.0\t238.0\t240.0\t237.0\t-1.7\t0.8\t-1.3",
  "ejemplo\t3\tphones\te\t1.28\t1.35\t70\t229.6\t67.5\t227.0\t230.0\t231.0\t228.0\t-1.3\t0.4\t-1.3",
  "ejemplo\t3\tphones\ta\t1.39\t1.48\t90\t222.0\t66.9\t219.0\t222.0\t224.0\t221.0\t-1.4\t0.9\t-1.3",
  "ejemplo\t3\tphones\ti\t1.52\t1.58\t60\t215.3\t65.4\t213.0\t215.0\t217.0\t214.0\t-0.9\t0.9\t-1.4",
  "ejemplo\t3\tphones\ta\t1.62\t1.75\t130\t209.7\t66.8\t207.0\t210.0\t211.0\t209.0\t-1.4\t0.5\t-1.0",
  "ejemplo\t3\tphones\te\t1.80\t1.88\t80\t204.1\t64.2\t202.0\t204.0\t206.0\t203.0\t-1.0\t1.0\t-1.5",
  "ejemplo\t3\tphones\te\t1.93\t2.00\t70\t198.4\t68.1\t196.0\t198.0\t200.0\t198.0\t-1.0\t1.0\t-1.0",
  "ejemplo\t3\tphones\ti\t2.06\t2.14\t80\t191.7\t67.4\t189.0\t192.0\t193.0\t191.0\t-1.6\t0.5\t-1.0",
  "ejemplo\t3\tphones\te\t2.20\t2.35\t150\t179.0\t70.2\t158.0\t185.0\t190.0\t183.0\t17.1\t2.7\t-3.7",
  "ejemplo\t3\tphones\te\t2.35\t2.42\t70\t174.8\t64.1\t172.0\t175.0\t176.0\t173.0\t-1.7\t0.6\t-1.7",
  "ejemplo\t3\tphones\te\t2.53\t2.65\t120\t164.2\t65.8\t161.0\t164.0\t166.0\t162.0\t-1.9\t1.2\t-2.4",
  "ejemplo\t3\tphones\to\t2.72\t3.20\t480\t151.7\t62.4\t149.0\t152.0\t153.0\t150.0\t-2.0\t0.7\t-2.0",
  # ── ejemplo2: «Es el vecino el que elige al alcalde…» ─────────────────────
  "ejemplo2\t1\tutterances\tEs el vecino el que elige al alcalde y es el alcalde el que quiere que sean los vecinos el alcalde\t0.00\t5.80\t5800\t202.5\t67.8\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tEs\t0.00\t0.12\t120\t218.0\t67.5\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tel\t0.12\t0.20\t80\t220.3\t66.0\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tvecino\t0.20\t0.70\t500\t223.4\t69.8\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tel\t0.70\t0.80\t100\t225.1\t67.2\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tque\t0.80\t0.92\t120\t228.0\t66.5\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\telige\t0.92\t1.32\t400\t240.5\t71.3\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tal\t1.32\t1.42\t100\t233.8\t69.1\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\talcalde\t1.42\t2.10\t680\t225.3\t68.4\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\ty\t2.10\t2.25\t150\t218.2\t65.3\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tes\t2.25\t2.38\t130\t215.7\t64.8\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tel\t2.38\t2.48\t100\t213.4\t63.9\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\talcalde\t2.48\t3.05\t570\t207.6\t66.2\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tel\t3.05\t3.16\t110\t200.5\t63.1\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tque\t3.16\t3.28\t120\t196.8\t62.8\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tquiere\t3.28\t3.70\t420\t191.2\t65.4\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tque\t3.70\t3.82\t120\t184.7\t63.0\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tsean\t3.82\t4.15\t330\t178.5\t62.4\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tlos\t4.15\t4.28\t130\t172.8\t61.8\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tvecinos\t4.28\t4.80\t520\t165.4\t63.5\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\tel\t4.80\t4.92\t120\t157.6\t61.2\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t2\twords\talcalde\t4.92\t5.80\t880\t147.8\t60.4\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo2\t3\tphones\te\t0.03\t0.10\t70\t218.0\t67.5\t215.0\t218.0\t220.0\t217.0\t-1.4\t0.9\t-1.4",
  "ejemplo2\t3\tphones\te\t0.25\t0.35\t100\t222.4\t68.2\t220.0\t222.0\t224.0\t222.0\t-0.9\t0.9\t-0.9",
  "ejemplo2\t3\tphones\ti\t0.40\t0.50\t100\t228.1\t69.8\t225.0\t228.0\t230.0\t227.0\t-1.3\t0.9\t-1.3",
  "ejemplo2\t3\tphones\to\t0.55\t0.65\t100\t220.8\t68.5\t218.0\t221.0\t222.0\t220.0\t-1.4\t0.5\t-0.9",
  "ejemplo2\t3\tphones\te\t0.95\t1.03\t80\t235.2\t70.1\t232.0\t235.0\t237.0\t234.0\t-1.3\t0.9\t-1.3",
  "ejemplo2\t3\tphones\ti\t1.08\t1.18\t100\t245.3\t71.3\t210.0\t245.0\t249.0\t239.0\t16.7\t1.6\t-4.0",
  "ejemplo2\t3\tphones\te\t1.22\t1.30\t80\t238.1\t70.5\t235.0\t238.0\t240.0\t237.0\t-1.3\t0.8\t-1.3",
  "ejemplo2\t3\tphones\ta\t1.48\t1.58\t100\t232.4\t69.8\t229.0\t232.0\t234.0\t231.0\t-1.3\t0.9\t-1.3",
  "ejemplo2\t3\tphones\ta\t1.68\t1.78\t100\t225.7\t68.7\t223.0\t226.0\t227.0\t225.0\t-1.3\t0.4\t-0.9",
  "ejemplo2\t3\tphones\te\t1.90\t2.05\t150\t218.3\t67.9\t215.0\t218.0\t220.0\t217.0\t-1.4\t0.9\t-1.4",
  "ejemplo2\t3\tphones\te\t2.28\t2.35\t70\t215.1\t65.2\t212.0\t215.0\t217.0\t214.0\t-1.4\t0.9\t-1.4",
  "ejemplo2\t3\tphones\ta\t2.54\t2.64\t100\t220.0\t67.1\t217.0\t220.0\t221.0\t219.0\t-1.4\t0.5\t-0.9",
  "ejemplo2\t3\tphones\ta\t2.68\t2.78\t100\t210.4\t66.0\t208.0\t210.0\t212.0\t210.0\t-1.0\t1.0\t-1.0",
  "ejemplo2\t3\tphones\te\t2.85\t2.98\t130\t203.2\t64.8\t200.0\t203.0\t205.0\t202.0\t-1.5\t1.0\t-1.5",
  "ejemplo2\t3\tphones\ti\t3.32\t3.42\t100\t196.5\t64.2\t194.0\t197.0\t198.0\t196.0\t-1.5\t0.5\t-1.0",
  "ejemplo2\t3\tphones\te\t3.48\t3.62\t140\t190.2\t63.8\t187.0\t190.0\t192.0\t189.0\t-1.6\t1.1\t-1.6",
  "ejemplo2\t3\tphones\te\t3.86\t3.96\t100\t183.4\t62.9\t181.0\t183.0\t185.0\t182.0\t-1.1\t1.1\t-1.6",
  "ejemplo2\t3\tphones\ta\t4.00\t4.12\t120\t176.8\t62.4\t174.0\t177.0\t178.0\t175.0\t-1.7\t0.6\t-1.7",
  "ejemplo2\t3\tphones\to\t4.18\t4.26\t80\t171.5\t61.8\t169.0\t172.0\t173.0\t170.0\t-1.7\t0.6\t-1.7",
  "ejemplo2\t3\tphones\te\t4.32\t4.42\t100\t165.3\t62.5\t163.0\t165.0\t167.0\t164.0\t-1.2\t1.2\t-1.8",
  "ejemplo2\t3\tphones\ti\t4.48\t4.58\t100\t158.9\t61.2\t156.0\t159.0\t161.0\t158.0\t-1.9\t1.3\t-1.9",
  "ejemplo2\t3\tphones\to\t4.62\t4.72\t100\t152.4\t60.4\t150.0\t152.0\t154.0\t151.0\t-1.3\t1.3\t-2.0",
  "ejemplo2\t3\tphones\ta\t4.98\t5.10\t120\t147.2\t60.1\t145.0\t147.0\t149.0\t146.0\t-1.4\t1.4\t-2.0",
  "ejemplo2\t3\tphones\ta\t5.15\t5.28\t130\t138.6\t59.5\t136.0\t139.0\t141.0\t137.0\t-2.2\t1.4\t-2.9",
  "ejemplo2\t3\tphones\te\t5.40\t5.65\t250\t128.5\t58.8\t126.0\t129.0\t130.0\t127.0\t-2.4\t0.8\t-2.3",
  # ── ejemplo3: «Lo peor que hacen los malos es obligarnos a dudar de los buenos» ──
  "ejemplo3\t1\tutterances\tLo peor que hacen los malos es obligarnos a dudar de los buenos\t0.00\t3.80\t3800\t196.8\t66.2\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t2\twords\tLo\t0.00\t0.15\t150\t210.2\t66.5\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t2\twords\tpeor\t0.15\t0.55\t400\t220.8\t68.9\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t2\twords\tque\t0.55\t0.70\t150\t218.5\t67.2\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t2\twords\thacen\t0.70\t1.10\t400\t225.4\t69.4\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t2\twords\tlos\t1.10\t1.22\t120\t217.8\t67.1\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t2\twords\tmalos\t1.22\t1.68\t460\t213.2\t66.8\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t2\twords\tes\t1.68\t1.80\t120\t206.4\t64.9\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t2\twords\tobligarnos\t1.80\t2.45\t650\t205.7\t67.2\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t2\twords\ta\t2.45\t2.55\t100\t198.3\t64.5\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t2\twords\tdudar\t2.55\t2.95\t400\t190.8\t63.8\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t2\twords\tde\t2.95\t3.05\t100\t182.4\t62.4\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t2\twords\tlos\t3.05\t3.17\t120\t175.1\t61.8\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t2\twords\tbuenos\t3.17\t3.80\t630\t162.6\t60.2\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "ejemplo3\t3\tphones\to\t0.06\t0.13\t70\t210.2\t66.5\t208.0\t210.0\t212.0\t210.0\t-1.0\t1.0\t-1.0",
  "ejemplo3\t3\tphones\te\t0.20\t0.30\t100\t215.4\t67.8\t213.0\t215.0\t217.0\t215.0\t-0.9\t0.9\t-0.9",
  "ejemplo3\t3\tphones\to\t0.38\t0.48\t100\t225.8\t69.2\t195.0\t225.0\t228.0\t216.0\t15.4\t1.3\t-5.3",
  "ejemplo3\t3\tphones\te\t0.58\t0.67\t90\t218.3\t67.2\t215.0\t218.0\t220.0\t217.0\t-1.4\t0.9\t-1.4",
  "ejemplo3\t3\tphones\ta\t0.74\t0.86\t120\t228.5\t69.8\t225.0\t228.0\t230.0\t227.0\t-1.3\t0.9\t-1.3",
  "ejemplo3\t3\tphones\te\t0.92\t1.02\t100\t222.1\t68.5\t219.0\t222.0\t224.0\t221.0\t-1.4\t0.9\t-1.4",
  "ejemplo3\t3\tphones\to\t1.14\t1.20\t60\t217.5\t67.0\t215.0\t218.0\t219.0\t216.0\t-1.4\t0.5\t-1.4",
  "ejemplo3\t3\tphones\ta\t1.28\t1.40\t120\t214.8\t66.9\t212.0\t215.0\t216.0\t214.0\t-1.4\t0.5\t-0.9",
  "ejemplo3\t3\tphones\to\t1.50\t1.62\t120\t208.5\t66.0\t206.0\t209.0\t210.0\t207.0\t-1.5\t0.5\t-1.4",
  "ejemplo3\t3\tphones\te\t1.71\t1.78\t70\t204.3\t64.9\t202.0\t204.0\t206.0\t203.0\t-1.0\t1.0\t-1.5",
  "ejemplo3\t3\tphones\to\t1.84\t1.94\t100\t199.2\t65.8\t197.0\t199.0\t201.0\t198.0\t-1.0\t1.0\t-1.5",
  "ejemplo3\t3\tphones\ti\t1.98\t2.08\t100\t205.8\t66.2\t203.0\t206.0\t207.0\t204.0\t-1.5\t0.5\t-1.5",
  "ejemplo3\t3\tphones\ta\t2.18\t2.30\t120\t212.4\t67.1\t177.0\t212.0\t216.0\t204.0\t19.8\t1.9\t-5.6",
  "ejemplo3\t3\tphones\to\t2.36\t2.43\t70\t205.1\t65.9\t202.0\t205.0\t207.0\t204.0\t-1.5\t1.0\t-1.5",
  "ejemplo3\t3\tphones\tu\t2.60\t2.70\t100\t193.7\t63.8\t191.0\t194.0\t195.0\t192.0\t-1.6\t0.5\t-1.5",
  "ejemplo3\t3\tphones\ta\t2.74\t2.85\t110\t183.8\t62.9\t181.0\t184.0\t185.0\t182.0\t-1.7\t0.5\t-1.6",
  "ejemplo3\t3\tphones\tu\t3.22\t3.32\t100\t168.5\t61.5\t166.0\t169.0\t170.0\t167.0\t-1.8\t0.6\t-1.8",
  "ejemplo3\t3\tphones\te\t3.38\t3.52\t140\t156.8\t60.4\t154.0\t157.0\t158.0\t155.0\t-1.9\t0.6\t-1.9",
  "ejemplo3\t3\tphones\to\t3.58\t3.75\t170\t143.2\t59.2\t141.0\t143.0\t145.0\t141.0\t-1.4\t1.4\t-2.8",
  # ── cantero2019: «sigo en contacto con ellos» (Cantero Serena 2019) ─────────
  # F0 derivado de C.Est.×1.12 (Hz[1]=112); tiempos reales (Fonseca 2013 corpus)
  # Inflexión circumfleja en 'e' de «ellos»: q1(trough)=94 Hz → q2(peak)=119 Hz
  "cantero2019\t1\tutterances\tsigo en contacto con ellos\t0.000\t1.450\t1450\t118.6\t75.5\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "cantero2019\t2\twords\tsigo\t0.000\t0.205\t205\t112.0\t81.6\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "cantero2019\t2\twords\ten\t0.205\t0.363\t158\t136.5\t77.7\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "cantero2019\t2\twords\tcontacto\t0.363\t0.779\t416\t125.7\t75.1\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "cantero2019\t2\twords\tcon\t0.779\t0.941\t162\t106.0\t73.3\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "cantero2019\t2\twords\tellos\t0.941\t1.311\t370\t99.5\t71.8\tNA\tNA\tNA\tNA\tNA\tNA\tNA",
  "cantero2019\t3\tphones\ti\t0.112\t0.200\t88\t112.0\t81.6\t110.0\t112.0\t113.0\t111.0\t1.8\t0.9\t-1.8",
  "cantero2019\t3\tphones\to\t0.205\t0.362\t157\t127.0\t77.7\t125.0\t127.0\t128.0\t126.0\t1.6\t0.8\t-1.6",
  "cantero2019\t3\tphones\te\t0.205\t0.362\t119\t146.0\t77.7\t144.0\t146.0\t147.0\t145.0\t1.4\t0.7\t-1.4",
  "cantero2019\t3\tphones\to\t0.365\t0.484\t154\t140.0\t75.0\t138.0\t140.0\t141.0\t139.0\t1.4\t0.7\t-1.4",
  "cantero2019\t3\tphones\ta\t0.486\t0.640\t135\t124.0\t77.6\t122.0\t124.0\t125.0\t123.0\t1.6\t0.8\t-1.6",
  "cantero2019\t3\tphones\to\t0.643\t0.778\t159\t113.0\t72.6\t111.0\t113.0\t114.0\t112.0\t1.8\t0.9\t-1.8",
  "cantero2019\t3\tphones\to\t0.781\t0.940\t182\t106.0\t73.3\t104.0\t106.0\t107.0\t105.0\t1.9\t0.9\t-1.9",
  "cantero2019\t3\tphones\te\t0.943\t1.125\t182\t106.0\t74.6\t94.0\t119.0\t109.0\t100.0\t26.6\t-8.4\t-8.3",
  "cantero2019\t3\tphones\to\t1.128\t1.310\t137\t93.0\t69.0\t93.0\t93.0\t92.0\t91.0\t0.0\t-1.1\t-1.1"
), collapse = "\n")

# ── Funciones auxiliares ─────────────────────────────────────────────────────

is_vowel <- function(x) trimws(tolower(x)) %in% tolower(VOWELS)

open_praat <- function(script) {
  praat_candidates <- c(
    "/Applications/Praat.app/Contents/MacOS/Praat",
    "/usr/local/bin/praat",
    "/usr/bin/praat"
  )
  praat_bin <- Filter(file.exists, praat_candidates)
  if (length(praat_bin) > 0) {
    system2(praat_bin[1], args = c("--open", shQuote(script)), wait = FALSE)
  } else {
    system(paste("open -a Praat", shQuote(script)), wait = FALSE)
  }
}

to_relative <- function(vals) {
  ref_idx <- which(!is.na(vals) & vals != 0)[1]
  if (is.na(ref_idx)) return(vals)
  round((vals / vals[ref_idx]) * 100, 2)
}

get_tiers <- function(df, file_sel) {
  tier_order <- c(TIER_UTT, TIER_WORD, TIER_PHONE)
  tiers <- df %>%
    filter(file == file_sel) %>%
    pull(tier_name) %>%
    unique() %>%
    Filter(function(t) !grepl("emoci", t, ignore.case = TRUE), .)
  rank_tier <- function(t) {
    idx <- match(tolower(t), tolower(tier_order))
    if (is.na(idx)) length(tier_order) + 1L else idx
  }
  tiers[order(sapply(tiers, rank_tier))]
}

best_tier <- function(tiers, candidates) {
  tiers_lc      <- tolower(tiers)
  candidates_lc <- tolower(candidates)
  # Exact match first (respeta el orden de prioridad de candidates)
  m <- match(candidates_lc, tiers_lc)
  m <- m[!is.na(m)]
  if (length(m) > 0) return(tiers[m[1]])
  # Partial match: el nombre del tier contiene el candidato como subcadena
  for (cand in candidates_lc) {
    hits <- which(grepl(cand, tiers_lc, fixed = TRUE))
    if (length(hits) > 0) return(tiers[hits[1]])
  }
  tiers[1]
}

prepare_aph <- function(df, file_sel, utt_tier, word_tier, phone_tier, utt_tstart) {
  utt_tstart <- as.numeric(utt_tstart)

  utt <- df %>%
    filter(file == file_sel, tier_name == utt_tier,
           abs(time_start - utt_tstart) < 0.001) %>%
    slice(1)
  if (nrow(utt) == 0) return(NULL)

  t0 <- utt$time_start
  t1 <- utt$time_end

  words <- df %>%
    filter(file == file_sel, tier_name == word_tier,
           time_start >= t0 - 0.001, time_end <= t1 + 0.001,
           nchar(trimws(label)) > 0)

  phones <- df %>%
    filter(file == file_sel, tier_name == phone_tier,
           time_start >= t0 - 0.001, time_end <= t1 + 0.001,
           is_vowel(label)) %>%
    arrange(time_start)

  if (nrow(phones) == 0) return(phones)

  phones$word <- sapply(seq_len(nrow(phones)), function(i) {
    ts <- phones$time_start[i]
    te <- phones$time_end[i]
    m  <- words %>% filter(time_start <= ts + 0.001, time_end >= te - 0.001)
    if (nrow(m) > 0) m$label[1] else "—"
  })

  phones %>%
    mutate(
      idx     = row_number(),
      x_label = paste0(idx, ". ", label, " [", word, "]"),
      ioi     = c(time_start[1] - t0, diff(time_start))
    )
}

# Lee un CSV detectando automáticamente la codificación (UTF-8 o UTF-16)
safe_read_csv <- function(path) {
  result <- tryCatch(
    read_csv(path, show_col_types = FALSE),
    error = function(e) {
      if (!grepl("nul", e$message, ignore.case = TRUE)) stop(e)
      NULL
    }
  )
  if (!is.null(result)) return(result)

  bom <- readBin(path, "raw", n = 2)
  enc <- if (length(bom) == 2 && bom[1] == as.raw(0xFE) && bom[2] == as.raw(0xFF)) {
    "UTF-16BE"
  } else {
    "UTF-16LE"
  }
  read_csv(path, locale = locale(encoding = enc), show_col_types = FALSE)
}

# Construye el data frame de la tabla APH (compartido por app y exportación HTML)
build_aph_tbl <- function(d, compact = FALSE) {
  fmt <- function(x, digits)
    ifelse(is.na(x), "—", formatC(round(x, digits), format = "f", digits = digits))

  tbl <- data.frame(
    Vocal           = d$x_label,
    `F0 (Hz)`       = fmt(d$f0_mean_hz, 1),
    `F0 (%)`        = fmt(to_relative(d$f0_mean_hz), 1),
    `Int. (dB)`     = fmt(d$int_mean_db, 1),
    `Int. (%)`      = fmt(to_relative(d$int_mean_db), 1),
    `Dur. (s)`      = fmt(d$ioi, 3),
    `Dur. (%)`      = fmt(to_relative(d$ioi), 1),
    check.names = FALSE
  )

  has_q <- all(c("f0_q1_hz","f0_q2_hz","f0_q3_hz","f0_q4_hz") %in% names(d))
  if (has_q) {
    ref <- d$f0_mean_hz[which(!is.na(d$f0_mean_hz) & d$f0_mean_hz > 0)[1]]
    rel_q <- function(x) ifelse(is.na(x) | x <= 0, NA_real_, round(x / ref * 100, 1))
    tbl[["Q1 (Hz)"]] <- fmt(d$f0_q1_hz, 1)
    tbl[["Q2 (Hz)"]] <- fmt(d$f0_q2_hz, 1)
    tbl[["Q3 (Hz)"]] <- fmt(d$f0_q3_hz, 1)
    tbl[["Q4 (Hz)"]] <- fmt(d$f0_q4_hz, 1)
    tbl[["Q1 (%)"]]  <- fmt(rel_q(d$f0_q1_hz), 1)
    tbl[["Q2 (%)"]]  <- fmt(rel_q(d$f0_q2_hz), 1)
    tbl[["Q3 (%)"]]  <- fmt(rel_q(d$f0_q3_hz), 1)
    tbl[["Q4 (%)"]]  <- fmt(rel_q(d$f0_q4_hz), 1)
  }
  tbl
}

# Genera una tabla HTML compacta para exportación combinada
make_tbl_html <- function(d = NULL, transpose = FALSE, tbl = NULL) {
  base <- if (!is.null(tbl)) tbl else build_aph_tbl(d, compact = TRUE)

  tbl <- if (transpose) {
    m <- t(as.matrix(base[, -1]))
    colnames(m) <- base$Vocal
    cbind(Variable = rownames(m), as.data.frame(m, check.names = FALSE))
  } else {
    base
  }

  th <- 'style="padding:2px 6px;border:1px solid #ccc;background:#f0f0f0;font-size:9px;white-space:nowrap;font-family:Arial,sans-serif;"'
  td <- 'style="padding:2px 5px;border:1px solid #e5e5e5;text-align:center;font-size:9px;font-family:Arial,sans-serif;"'

  hdr  <- paste0('<th ', th, '>', names(tbl), '</th>', collapse = "")
  rows <- paste0(apply(tbl, 1, function(r)
    paste0('<tr>', paste0('<td ', td, '>', r, '</td>', collapse = ""), '</tr>')),
    collapse = "")

  paste0('<table style="border-collapse:collapse;width:100%;">',
         '<thead><tr>', hdr, '</tr></thead>',
         '<tbody>', rows, '</tbody></table>')
}

# ── make_aph_plot: función standalone para exportación y reactividad ─────────

make_aph_plot <- function(d, file_label, utt_text, vars, rel, show_val, peak_pct, show_quartiles) {
  f0_vals  <- if (rel) to_relative(d$f0_mean_hz)  else round(d$f0_mean_hz, 1)
  int_vals <- if (rel) to_relative(d$int_mean_db) else round(d$int_mean_db, 1)
  dur_vals <- if (rel) to_relative(d$ioi)         else round(d$ioi, 3)

  x_labs_base <- d$x_label
  y_left  <- if (rel) "Valor relativo (V₁ = 100)" else "F0 (Hz) / Intensidad (dB)"
  units_f <- if (rel) "%" else " Hz"

  hover_f0  <- paste0(d$label, " [", d$word, "]<br>F0: ",  f0_vals,  units_f)
  hover_int <- paste0(d$label, " [", d$word, "]<br>Int: ", int_vals, if (rel) "%" else " dB")
  hover_dur <- paste0(d$label, " [", d$word, "]<br>Dur: ", dur_vals, if (rel) "%" else " s")

  has_q <- all(c("f0_q1_hz","f0_q2_hz","f0_q3_hz","f0_q4_hz",
                 "q1_to_q2_pct","q2_to_q3_pct","q3_to_q4_pct") %in% names(d))
  infl_idx <- integer(0)
  if (has_q && "f0" %in% vars && isTRUE(show_quartiles)) {
    infl_mask <- (!is.na(d$q1_to_q2_pct) & abs(d$q1_to_q2_pct) > peak_pct) |
                 (!is.na(d$q2_to_q3_pct) & abs(d$q2_to_q3_pct) > peak_pct) |
                 (!is.na(d$q3_to_q4_pct) & abs(d$q3_to_q4_pct) > peak_pct)
    infl_idx <- which(infl_mask)
  }

  ref_f0  <- d$f0_mean_hz[which(!is.na(d$f0_mean_hz) & d$f0_mean_hz > 0)[1]]
  scale_q <- function(hz) {
    v <- ifelse(is.na(hz) | hz <= 0, NA_real_, hz)
    if (rel) round(v / ref_f0 * 100, 2) else round(v, 1)
  }

  all_levels <- character(0); x_f0_pos <- character(0)
  x_int_pos  <- character(0); x_dur_pos <- character(0)
  y_f0_main  <- numeric(0)

  for (i in seq_len(nrow(d))) {
    base <- x_labs_base[i]
    if (i %in% infl_idx) {
      sub <- paste0(base, c(" ·Q1"," ·Q2"," ·Q3"," ·Q4"))
      all_levels <- c(all_levels, sub)
      x_f0_pos   <- c(x_f0_pos,  sub[2])
      x_int_pos  <- c(x_int_pos, sub[2])
      x_dur_pos  <- c(x_dur_pos, sub[1])
      q2_val     <- scale_q(d$f0_q2_hz[i])
      y_f0_main  <- c(y_f0_main, if (!is.na(q2_val)) q2_val else f0_vals[i])
    } else {
      all_levels <- c(all_levels, base)
      x_f0_pos   <- c(x_f0_pos,  base)
      x_int_pos  <- c(x_int_pos, base)
      x_dur_pos  <- c(x_dur_pos, base)
      y_f0_main  <- c(y_f0_main, f0_vals[i])
    }
  }

  as_xfac <- function(v) factor(v, levels = all_levels)
  fig <- plot_ly()

  if ("dur" %in% vars) {
    fig <- add_bars(fig,
      x = as_xfac(x_dur_pos), y = dur_vals,
      name  = if (rel) "Duración (%)" else "Duración (s)",
      yaxis = if (!rel) "y2" else "y",
      marker = list(color = "rgba(150,150,150,0.45)",
                    line  = list(color = "grey60", width = 1)),
      text         = if (show_val) as.character(dur_vals) else "",
      textposition = if (show_val) "outside" else "none",
      textfont     = list(size = 8, color = "grey40"),
      hovertemplate = paste0(hover_dur, "<extra></extra>")
    )
  }

  if ("f0" %in% vars) {
    fig <- add_trace(fig,
      x = as_xfac(x_f0_pos), y = y_f0_main,
      type = "scatter",
      mode = if (show_val) "lines+markers+text" else "lines+markers",
      name   = if (rel) "F0 media (%)" else "F0 media (Hz)",
      line   = list(color = "royalblue", width = 2.5),
      marker = list(color = "royalblue", size = 8, symbol = "circle"),
      text         = if (show_val) as.character(y_f0_main) else NULL,
      textposition = "top center",
      textfont     = list(size = 8, color = "royalblue"),
      hovertemplate = paste0(hover_f0, "<extra></extra>")
    )

    f0_hz   <- d$f0_mean_hz
    ascenso <- rep(NA_real_, nrow(d))
    for (i in seq(2, nrow(d))) {
      p <- f0_hz[i - 1]; curr <- f0_hz[i]
      if (!is.na(p) && !is.na(curr) && p > 0 && curr > 0)
        ascenso[i] <- (curr - p) / p * 100
    }
    above <- which(!is.na(ascenso) & ascenso > peak_pct)

    if (length(above) > 0) {
      first_i <- above[1]; last_i <- above[length(above)]
      fig <- add_trace(fig,
        x = as_xfac(x_f0_pos[first_i]), y = y_f0_main[first_i],
        type = "scatter", mode = "markers",
        name = paste0("★ Primer pico (>", peak_pct, "%)"),
        marker = list(symbol = "star", size = 18, color = "red",
                      line = list(color = "darkred", width = 1)),
        hovertemplate = paste0(
          "★ ", d$x_label[first_i], "<br>Ascenso: ",
          sprintf("%+.1f%%", ascenso[first_i]),
          "<br>F0: ", y_f0_main[first_i], units_f, "<extra></extra>"),
        showlegend = TRUE
      )
      if (last_i != first_i) {
        fig <- add_trace(fig,
          x = as_xfac(x_f0_pos[last_i]), y = y_f0_main[last_i],
          type = "scatter", mode = "markers",
          name = paste0("○ Último pico (>", peak_pct, "%)"),
          marker = list(symbol = "circle-open", size = 18, color = "red",
                        line = list(color = "red", width = 2.5)),
          hovertemplate = paste0(
            "○ ", d$x_label[last_i], "<br>Ascenso: ",
            sprintf("%+.1f%%", ascenso[last_i]),
            "<br>F0: ", y_f0_main[last_i], units_f, "<extra></extra>"),
          showlegend = TRUE
        )
      }
    }

    if (length(infl_idx) > 0) {
      q_x <- character(0); q_y <- numeric(0)
      q_hov <- character(0); q_txt <- character(0)
      for (i in infl_idx) {
        base <- x_labs_base[i]
        sub  <- paste0(base, c(" ·Q1"," ·Q2"," ·Q3"," ·Q4"))
        qys  <- c(scale_q(d$f0_q1_hz[i]), scale_q(d$f0_q2_hz[i]),
                  scale_q(d$f0_q3_hz[i]), scale_q(d$f0_q4_hz[i]))
        q_x   <- c(q_x,   sub, NA_character_)
        q_y   <- c(q_y,   qys, NA_real_)
        q_hov <- c(q_hov,
          paste0(base, "<br>", c("Q1","Q2","Q3","Q4"), ": ",
                 ifelse(is.na(qys), "—", paste0(qys, units_f)),
                 "<extra></extra>"),
          "<extra></extra>")
        q_txt <- c(q_txt,
          ifelse(is.na(qys), "", paste0(c("Q1:","Q2:","Q3:","Q4:"), qys)),
          "")
      }
      fig <- add_trace(fig,
        x = factor(q_x, levels = all_levels), y = q_y,
        type = "scatter",
        mode = if (show_val) "lines+markers+text" else "lines+markers",
        name = paste0("Q1–Q4 inflexión (>", peak_pct, "%)"),
        marker = list(symbol = "circle", size = 12, color = "purple",
                      line   = list(color = "white", width = 1.5)),
        line          = list(color = "purple", width = 2.5, dash = "dot"),
        text          = if (show_val) q_txt else NULL,
        textposition  = "top center",
        textfont      = list(size = 8, color = "purple"),
        hovertemplate = q_hov,
        showlegend    = TRUE
      )
    }
  }

  if ("int" %in% vars) {
    fig <- add_trace(fig,
      x = as_xfac(x_int_pos), y = int_vals,
      type = "scatter",
      mode = if (show_val) "lines+markers+text" else "lines+markers",
      name   = if (rel) "Intensidad (%)" else "Intensidad media (dB)",
      line   = list(color = "#DAA520", width = 2.5, dash = "dash"),
      marker = list(color = "#DAA520", size = 8, symbol = "diamond"),
      text         = if (show_val) as.character(int_vals) else NULL,
      textposition = "bottom center",
      textfont     = list(size = 8, color = "#b8860b"),
      hovertemplate = paste0(hover_int, "<extra></extra>")
    )
  }

  fname_safe <- gsub("[^A-Za-z0-9]", "_", file_label)

  layout_base <- list(
    height = 540,
    title  = list(
      text = paste0("<b>APH</b>  —  ", file_label,
                    "<br><i style='font-size:11px'>", utt_text, "</i>"),
      font = list(size = 13)
    ),
    xaxis  = list(title = "", tickangle = -35, showgrid = FALSE,
                  tickfont = list(size = 10)),
    yaxis  = list(title = y_left, zeroline = FALSE, showgrid = TRUE,
                  gridcolor = "rgba(200,200,200,0.4)", titlefont = list(size = 11)),
    legend = list(orientation = "h", xanchor = "center", x = 0.5,
                  yanchor = "top", y = -0.22, font = list(size = 10)),
    hovermode     = "x unified",
    barmode       = "overlay",
    plot_bgcolor  = "white",
    paper_bgcolor = "white",
    margin        = list(t = 75, b = 140, l = 70, r = 60)
  )

  if (!rel && "dur" %in% vars) {
    layout_base$yaxis2 <- list(
      title = "Duración inter-onset (s)", overlaying = "y", side = "right",
      showgrid = FALSE, zeroline = FALSE, titlefont = list(size = 11)
    )
  }

  layout(fig, .list = layout_base) %>%
    config(toImageButtonOptions = list(
      format = "png", filename = paste0("APH_", fname_safe),
      width = 900, height = 540, scale = 3
    ))
}

# ── UI ───────────────────────────────────────────────────────────────────────

ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      body { font-size: 14px; }
      .section-title {
        color: #2c3e50; font-weight: 600;
        border-bottom: 1px solid #dee2e6;
        padding-bottom: 4px; margin-top: 10px; margin-bottom: 8px;
      }
      .btn-block { width: 100%; margin-bottom: 5px; }
      .note-small { font-size: 11px; color: #6c757d; margin-top: -4px; margin-bottom: 6px; }
      .export-row { display:flex; align-items:center; gap:12px; flex-wrap:wrap; margin-bottom:4px; }
      .export-row .radio { margin:0; }
      .export-row .radio label { font-size:12px; }
      .tbl-row { display:flex; align-items:center; gap:16px; flex-wrap:wrap; margin-bottom:6px; }
      .nav-utt { display:flex; align-items:center; gap:5px; margin-bottom:8px; }
      body.sidebar-hidden .shiny-panel-conditional { display:none !important; }
      body.sidebar-hidden .col-sm-9 { width:100% !important; flex:0 0 100% !important; max-width:100% !important; }
    ")),
    tags$script(HTML("
      $(document).on('click', '#toggle_sidebar', function() {
        $('body').toggleClass('sidebar-hidden');
        var hidden = $('body').hasClass('sidebar-hidden');
        $(this).text(hidden ? '☰ Mostrar barra lateral' : '✕ Ocultar barra lateral');
        $(window).trigger('resize');
      });
    "))
  ),

  titlePanel("Análisis Prosódico del Habla"),

  sidebarLayout(
    conditionalPanel("input.tabs == 'graph'",
      sidebarPanel(width = 3,

        hr(),
        p(class = "section-title", "Opciones del gráfico APH"),

        uiOutput("ui_file"),
        uiOutput("ui_utt_tier"),
        uiOutput("ui_word_tier"),
        uiOutput("ui_phone_tier"),
        uiOutput("ui_utt"),

        checkboxGroupInput("vars", "Variables:",
          choices  = c("F0 media" = "f0", "Intensidad media" = "int", "Duración" = "dur"),
          selected = c("f0", "int", "dur")
        ),
        radioButtons("scale", "Escala:",
          choices  = c("Valores absolutos" = "abs", "Valores relativos (V₁ = 100%)" = "rel"),
          selected = "rel"
        ),

        checkboxInput("show_values", "Mostrar valores en el gráfico", value = FALSE),

        hr(),
        p(class = "section-title", "Marcadores de pico tonal (F0)"),
        numericInput("peak_pct", "Umbral de ascenso (%):", value = 15, min = 1, max = 500, step = 1),
        checkboxInput("show_quartiles", "Mostrar cuartiles Q1–Q4 (CSV v6)", value = FALSE),
        p(class = "note-small",
          "★ rojo = 1ª vocal con ascenso > umbral sobre la anterior",
          tags$br(),
          "○ rojo = última vocal con ese ascenso",
          tags$br(),
          "● morado ×4 = Q1 Q2 Q3 Q4 de la vocal con inflexión interna"),

        hr(),
        p(class = "section-title", "Columnas de la tabla"),
        checkboxGroupInput("tbl_cols_show", NULL,
          choices  = c("F0 (Hz y %)"         = "f0",
                       "Intensidad (dB y %)" = "int",
                       "Duración IOI"        = "dur",
                       "Q1–Q4 (Hz)"          = "q_hz",
                       "Q1–Q4 (%)"           = "q_pct"),
          selected = c("f0", "int", "dur")
        )
      )
    ),

    mainPanel(width = 9,
      tabsetPanel(id = "tabs",

        tabPanel("Pegar CSV", value = "paste_csv",
          br(),
          div(
            p(class = "section-title", "Cargar CSV de resultados"),
            fileInput("csv_upload", NULL, accept = ".csv"),
              div(style = "display:flex; gap:8px; flex-wrap:wrap; align-items:center;",
            actionButton("btn_load_csv_text", "Cargar datos pegados",
                         class = "btn btn-primary btn-sm"),
            actionButton("btn_example", "Pegar datos de ejemplo",
                         class = "btn btn-outline-secondary btn-sm")
          ),
          hr(),
            p(class = "note-small",
              "O pega aquí el contenido de un archivo CSV (incluida la fila de cabecera).")
          ),

          textAreaInput("csv_text", NULL, rows = 18, width = "100%",
                        placeholder = "Pega el CSV aquí…"),

        

          br(),
          div(class = "note-small",
            tags$strong("Datos de ejemplo:"),
            " cuatro frases: «Cuando el Villarreal…» (ejemplo), «Es el vecino el que elige…» (ejemplo2), «Lo peor que hacen los malos…» (ejemplo3) y «sigo en contacto con ellos» (cantero2019 — datos reales de Cantero Serena 2019).",
            tags$br(),
            "Tiers requeridos: ", tags$code("utterances"), ", ",
            tags$code("words"), ", ", tags$code("phones"),
            " (etiquetas IPA de vocales: a, e, i, o, u y variantes).",
            tags$br(),
            "Script PRAAT que genera este CSV: ",
            tags$a(href = "XXX", target = "_blank",
                   "Extracción prosódica v6 (Extraccion_datos_v6.praat)")
          ),

          br(),
          uiOutput("paste_csv_status")
        ),

        tabPanel("Data Frame", value = "df",
          br(),
          DT::dataTableOutput("tbl")
        ),

        tabPanel("Gráfico APH", value = "graph",
          br(),
          div(style = "margin-bottom:6px;",
            actionButton("toggle_sidebar", "✕ Ocultar",
                         class = "btn btn-outline-secondary btn-sm",
                         style = "font-size:11px; padding:2px 10px;",
                         title = "Mostrar/ocultar el panel lateral")
          ),
          div(class = "nav-utt",
            actionButton("nav_first", "⏮", class = "btn btn-outline-secondary btn-sm",
                         title = "Primera utterance"),
            actionButton("nav_prev",  "◀",  class = "btn btn-outline-secondary btn-sm",
                         title = "Utterance anterior"),
            actionButton("nav_next",  "▶",  class = "btn btn-outline-secondary btn-sm",
                         title = "Utterance siguiente"),
            actionButton("nav_last",  "⏭", class = "btn btn-outline-secondary btn-sm",
                         title = "Última utterance")
          ),
          plotlyOutput("aph_plot", height = "560px"),
          br(),

          # ── Botones de exportación ─────────────────────────────────────
          div(class = "export-row",
            downloadButton("dl_html", "Exportar HTML",
                           class = "btn btn-success btn-sm"),
            tags$button("Exportar PNG",
                        id    = "btn_export_png",
                        type  = "button",
                        class = "btn btn-outline-primary btn-sm",
                        onclick = paste0(
                          "var b=document.querySelector('#aph_plot .modebar-btn[data-title=\"Download plot as a png\"]');",
                          "if(b){b.click();}else{",
                          "Plotly.downloadImage(document.getElementById('aph_plot'),",
                          "{format:'png',filename:'APH',width:900,height:540,scale:3});}"
                        ))
          ),

          # ── Exportación en lote ────────────────────────────────────────
          div(class = "export-row", style = "margin-top:6px;",
            radioButtons("batch_scope", NULL,
              choices  = c("Utterances del archivo actual"              = "one_file",
                           "Todas las utterances (todos los archivos)"  = "all_files"),
              selected = "one_file", inline = TRUE
            )
          ),
          div(class = "export-row",
            numericInput("batch_max", "Máx. gráficos:",
                         value = 10, min = 1, max = 50, step = 1, width = "130px"),
            downloadButton("dl_batch_zip", "Exportar lote (ZIP)",
                           class = "btn btn-warning btn-sm")
          ),
          p(class = "note-small",
            "⚠ Requiere el paquete ", tags$code("webshot2"),
            " (PNG a 300 DPI con Chrome). ",
            "Dado el alto coste de computación, se recomienda no exportar más de 10–15 gráficos a la vez. ",
            "Nombre: ", tags$code("{archivo}_{utterance}.png"), "."
          ),

          hr(),
          div(class = "tbl-row",
            checkboxInput("tbl_transpose", "Transponer tabla", value = FALSE),
            downloadButton("dl_table", "Exportar tabla (.tsv)",
                           class = "btn btn-outline-secondary btn-sm")
          ),
          tableOutput("aph_table")
        )
      )
    )
  )
)

# ── Server ───────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  rv <- reactiveValues(df = NULL, tg_dir = NULL)

  # — Carga de CSV (archivo) ────────────────────────────────────────────────
  observeEvent(input$csv_upload, {
    tryCatch({
      rv$df <- safe_read_csv(input$csv_upload$datapath) %>%
        arrange(time_start)
      updateTextAreaInput(session, "csv_text", value = "")
      paste_status(NULL)
      showNotification(
        paste0("CSV cargado: ", nrow(rv$df), " filas, ", ncol(rv$df), " columnas."),
        type = "message"
      )
      updateTabsetPanel(session, "tabs", selected = "graph")
    }, error = function(e) showNotification(paste("Error:", e$message), type = "error"))
  })

  # — Carga de CSV (texto pegado) ───────────────────────────────────────────
  paste_status <- reactiveVal(NULL)

  observeEvent(input$btn_load_csv_text, {
    req(nchar(trimws(input$csv_text)) > 0)
    tryCatch({
      txt <- trimws(input$csv_text)
      first_line <- strsplit(txt, "\n", fixed = TRUE)[[1]][1]
      delim <- if (grepl("\t", first_line, fixed = TRUE)) "\t" else ","
      rv$df <- readr::read_delim(I(txt), delim = delim, show_col_types = FALSE) %>%
        arrange(time_start)
      msg <- paste0("CSV pegado cargado: ", nrow(rv$df), " filas, ", ncol(rv$df), " columnas.")
      paste_status(list(ok = TRUE, msg = msg))
      showNotification(msg, type = "message")
      updateTabsetPanel(session, "tabs", selected = "graph")
    }, error = function(e) {
      paste_status(list(ok = FALSE, msg = paste("Error al parsear el CSV:", e$message)))
      showNotification(paste("Error:", e$message), type = "error")
    })
  })

  # — Datos de ejemplo ──────────────────────────────────────────────────────
  observeEvent(input$btn_example, {
    tryCatch({
      rv$df <- readr::read_tsv(I(SAMPLE_CSV), show_col_types = FALSE) %>%
        arrange(time_start)
      updateTextAreaInput(session, "csv_text", value = SAMPLE_CSV)
      msg <- paste0("Datos de ejemplo cargados: ", nrow(rv$df), " filas.")
      paste_status(list(ok = TRUE, msg = msg))
      showNotification(msg, type = "message")
      updateTabsetPanel(session, "tabs", selected = "graph")
    }, error = function(e) {
      paste_status(list(ok = FALSE, msg = paste("Error al cargar ejemplo:", e$message)))
      showNotification(paste("Error:", e$message), type = "error")
    })
  })

  output$paste_csv_status <- renderUI({
    s <- paste_status()
    req(s)
    cls <- if (s$ok) "text-success" else "text-danger"
    tags$p(class = cls, s$msg)
  })

  # — Subida de TextGrids ───────────────────────────────────────────────────
  observeEvent(input$tg_upload, {
    dir <- file.path(tempdir(), "aph_textgrids")
    dir.create(dir, showWarnings = FALSE, recursive = TRUE)
    file.remove(list.files(dir, full.names = TRUE))
    file.copy(input$tg_upload$datapath,
              file.path(dir, input$tg_upload$name), overwrite = TRUE)
    rv$tg_dir <- dir
    showNotification(paste(nrow(input$tg_upload), "TextGrid(s) cargados."), type = "message")
  })

  output$tg_info <- renderUI({
    req(rv$tg_dir)
    n <- length(list.files(rv$tg_dir, pattern = "\\.TextGrid$", ignore.case = TRUE))
    tags$p(class = "note-small",
      tags$span(class = "text-success", paste0("✓ ", n, " TextGrid(s) en:")),
      tags$br(),
      tags$code(style = "font-size:10px; word-break:break-all;", rv$tg_dir)
    )
  })

  output$ui_btn_s2_tg <- renderUI({
    req(rv$tg_dir)
    actionButton("btn_s2_tg", "▶  Ejecutar Script 2 con TextGrids subidos",
                 class = "btn btn-info btn-sm btn-block")
  })

  # — Botones PRAAT ─────────────────────────────────────────────────────────
  observeEvent(input$btn_s1,   { open_praat(SCRIPT1); showNotification("Abriendo Script 1…", type = "message") })
  observeEvent(input$btn_s2,   { open_praat(SCRIPT2); showNotification("Abriendo Script 2 v6…", type = "message") })
  observeEvent(input$btn_both, {
    open_praat(SCRIPT1)
    showNotification("Script 1 abierto. Cuando finalice, pulsa 'Script 2'.", type = "warning", duration = 10)
  })
  observeEvent(input$btn_s2_tg, {
    open_praat(SCRIPT2)
    showNotification(paste0("Script 2 abierto. TextGrids en: ", rv$tg_dir), type = "message", duration = 15)
  })

  # — Selectores jerárquicos de tiers ───────────────────────────────────────
  tiers_disponibles <- reactive({
    req(rv$df, input$sel_file)
    get_tiers(rv$df, input$sel_file)
  })

  output$ui_file <- renderUI({
    req(rv$df)
    selectInput("sel_file", "Archivo:", choices = sort(unique(rv$df$file)), selectize = FALSE)
  })

  output$ui_utt_tier <- renderUI({
    t <- tiers_disponibles()
    selectInput("sel_utt_tier", "Tier utterances:",
                choices = t, selected = best_tier(t, TIER_UTT), selectize = FALSE)
  })

  output$ui_word_tier <- renderUI({
    t <- tiers_disponibles()
    selectInput("sel_word_tier", "Tier palabras:",
                choices = t, selected = best_tier(t, TIER_WORD), selectize = FALSE)
  })

  output$ui_phone_tier <- renderUI({
    t <- tiers_disponibles()
    selectInput("sel_phone_tier", "Tier fonemas:",
                choices = t, selected = best_tier(t, TIER_PHONE), selectize = FALSE)
  })

  # — Selector de utterance ─────────────────────────────────────────────────
  output$ui_utt <- renderUI({
    req(rv$df, input$sel_file, input$sel_utt_tier)
    utts <- rv$df %>%
      filter(file == input$sel_file, tier_name == input$sel_utt_tier,
             nchar(trimws(label)) > 0) %>%
      arrange(time_start)
    choices <- setNames(
      as.character(utts$time_start),
      paste0(seq_len(nrow(utts)), ": ", utts$label)
    )
    selectInput("sel_utt", "Utterance:", choices = choices, selectize = FALSE)
  })

  # — Datos APH ─────────────────────────────────────────────────────────────
  aph_d <- reactive({
    req(rv$df, input$sel_file, input$sel_utt_tier,
        input$sel_word_tier, input$sel_phone_tier, input$sel_utt)
    d <- prepare_aph(rv$df, input$sel_file,
                     input$sel_utt_tier, input$sel_word_tier, input$sel_phone_tier,
                     input$sel_utt)
    validate(
      need(!is.null(d) && nrow(d) > 0,
           "No se encontraron vocales en esta utterance con los tiers seleccionados.")
    )
    d
  })

  # — Pestaña Data Frame ────────────────────────────────────────────────────
  output$tbl <- DT::renderDataTable({
    req(rv$df)
    DT::datatable(rv$df, filter = "top",
                  options = list(pageLength = 20, scrollX = TRUE, autoWidth = FALSE))
  })

  # — Navegación entre utterances ───────────────────────────────────────────
  utt_keys <- reactive({
    req(rv$df, input$sel_file, input$sel_utt_tier)
    rv$df %>%
      filter(file == input$sel_file, tier_name == input$sel_utt_tier,
             nchar(trimws(label)) > 0) %>%
      arrange(time_start) %>%
      pull(time_start) %>%
      as.character()
  })

  observeEvent(input$nav_first, ignoreInit = TRUE, {
    k <- utt_keys()
    if (length(k)) updateSelectInput(session, "sel_utt", selected = k[1])
  })
  observeEvent(input$nav_last, ignoreInit = TRUE, {
    k <- utt_keys()
    if (length(k)) updateSelectInput(session, "sel_utt", selected = k[length(k)])
  })
  observeEvent(input$nav_prev, ignoreInit = TRUE, {
    k <- utt_keys(); cur <- match(input$sel_utt, k)
    if (!is.na(cur) && cur > 1L) updateSelectInput(session, "sel_utt", selected = k[cur - 1L])
  })
  observeEvent(input$nav_next, ignoreInit = TRUE, {
    k <- utt_keys(); cur <- match(input$sel_utt, k)
    if (!is.na(cur) && cur < length(k)) updateSelectInput(session, "sel_utt", selected = k[cur + 1L])
  })

  # — Gráfico APH ───────────────────────────────────────────────────────────
  build_plot <- reactive({
    d        <- aph_d()
    utt_text <- rv$df %>%
      filter(file == input$sel_file, tier_name == input$sel_utt_tier,
             abs(time_start - as.numeric(input$sel_utt)) < 0.001) %>%
      slice(1) %>% pull(label)
    peak_pct <- if (!is.null(input$peak_pct) && !is.na(input$peak_pct)) input$peak_pct else 15
    make_aph_plot(d, input$sel_file, utt_text,
                  input$vars, input$scale == "rel",
                  isTRUE(input$show_values), peak_pct, isTRUE(input$show_quartiles))
  })

  output$aph_plot <- renderPlotly({ build_plot() })

  # — Tabla resumen APH (columnas filtradas) ───────────────────────────────
  tbl_filtered <- reactive({
    tbl <- build_aph_tbl(aph_d())
    sel <- if (!is.null(input$tbl_cols_show)) input$tbl_cols_show else c("f0","int","dur")
    keep <- c("Vocal",
              if ("f0"    %in% sel) c("F0 (Hz)",   "F0 (%)")                          else NULL,
              if ("int"   %in% sel) c("Int. (dB)", "Int. (%)")                        else NULL,
              if ("dur"   %in% sel) c("Dur. (s)",  "Dur. (%)")                        else NULL,
              if ("q_hz"  %in% sel) c("Q1 (Hz)","Q2 (Hz)","Q3 (Hz)","Q4 (Hz)")       else NULL,
              if ("q_pct" %in% sel) c("Q1 (%)","Q2 (%)","Q3 (%)","Q4 (%)")           else NULL)
    tbl[, intersect(keep, names(tbl)), drop = FALSE]
  })

  tbl_data <- reactive({
    tbl <- tbl_filtered()
    if (isTRUE(input$tbl_transpose)) {
      t_mat <- t(as.matrix(tbl[, -1]))
      colnames(t_mat) <- tbl$Vocal
      cbind(Variable = rownames(t_mat), as.data.frame(t_mat, check.names = FALSE))
    } else {
      tbl
    }
  })

  output$aph_table <- renderTable({
    tbl_data()
  }, striped = TRUE, hover = TRUE, bordered = TRUE, spacing = "s")

  # — Exportar tabla (.tsv) ─────────────────────────────────────────────────
  output$dl_table <- downloadHandler(
    filename = function() {
      paste0("APH_tabla_", gsub("[^A-Za-z0-9]", "_", input$sel_file), "_", Sys.Date(), ".txt")
    },
    content = function(file) {
      write.table(tbl_data(), file, sep = "\t", row.names = FALSE,
                  quote = FALSE, fileEncoding = "UTF-8")
    }
  )

  # — Exportar gráfico + tabla (HTML) ──────────────────────────────────────
  output$dl_html <- downloadHandler(
    filename = function() {
      paste0("APH_", gsub("[^A-Za-z0-9]", "_", input$sel_file), "_", Sys.Date(), ".html")
    },
    content = function(file) {
      fig_exp <- build_plot() %>%
        plotly::layout(
          height = 540,
          margin = list(t = 75, b = 140, l = 70, r = 60),
          legend = list(orientation = "h", xanchor = "center", x = 0.5,
                        yanchor = "top", y = -0.22, font = list(size = 9))
        )

      tmp_widget <- tempfile(fileext = ".html")
      htmlwidgets::saveWidget(fig_exp, tmp_widget, selfcontained = TRUE,
                              title = paste0("APH — ", input$sel_file))

      fix_css <- paste0(
        '<style>',
        'html,body{height:auto!important;overflow:auto!important;background:white;}',
        '.html-widget{height:560px!important;min-height:0!important;}',
        '</style>'
      )

      tbl_block <- paste0(
        fix_css,
        '<div style="padding:0 18px 24px 18px;background:white;">',
        '<p style="font-size:10px;font-weight:600;color:#444;margin:10px 0 3px;',
        'font-family:Arial,sans-serif;">Tabla resumen APH</p>',
        make_tbl_html(transpose = isTRUE(input$tbl_transpose), tbl = tbl_filtered()),
        '</div>'
      )

      base_html  <- readr::read_file(tmp_widget)
      all_pos    <- gregexpr("</body>", base_html, ignore.case = TRUE)[[1]]
      pos        <- if (length(all_pos) > 0 && all_pos[1] != -1L) tail(all_pos, 1L) else -1L

      combined_html <- if (pos > 0) {
        paste0(
          substr(base_html, 1L, pos - 1L),
          tbl_block, "\n",
          substr(base_html, pos, nchar(base_html))
        )
      } else {
        paste0(base_html, "\n", tbl_block)
      }

      write_html <- function(html, path) {
        con <- file(path, open = "w", encoding = "UTF-8")
        on.exit(close(con))
        writeLines(html, con, useBytes = FALSE)
      }

      write_html(combined_html, file)
    }
  )

  # — Exportar lote de gráficos (ZIP con PNGs a 300 DPI) ──────────────────
  # Nota: webshot2 requiere Chrome y no funciona en Shinylive/WebAssembly.
  # Se referencia de forma indirecta para evitar su inclusión en la demo.
  output$dl_batch_zip <- downloadHandler(
    filename = function() paste0("APH_lote_", Sys.Date(), ".zip"),
    content = function(zip_path) {
      req(rv$df)
      ws2 <- "webshot2"
      if (!requireNamespace(ws2, quietly = TRUE)) {
        showNotification(
          "Se requiere el paquete webshot2: install.packages('webshot2')",
          type = "error", duration = 10
        )
        return(NULL)
      }
      webshot_fn <- getExportedValue(ws2, "webshot")

      peak_pct <- if (!is.null(input$peak_pct) && !is.na(input$peak_pct)) input$peak_pct else 15
      max_n    <- max(1L, min(as.integer(input$batch_max), 50L))

      files_to_use <- if (identical(input$batch_scope, "all_files")) {
        sort(unique(rv$df$file))
      } else {
        input$sel_file
      }

      utt_rows <- dplyr::bind_rows(lapply(files_to_use, function(f) {
        rv$df %>%
          filter(file == f, tier_name == input$sel_utt_tier,
                 nchar(trimws(label)) > 0) %>%
          arrange(time_start) %>%
          mutate(file_id = f)
      }))

      if (nrow(utt_rows) == 0) {
        showNotification("No se encontraron utterances.", type = "error")
        return(NULL)
      }
      utt_rows <- head(utt_rows, max_n)

      withProgress(message = "Generando PNGs…", value = 0, {
        tmp_dir   <- tempfile(); dir.create(tmp_dir)
        on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
        png_files <- character(0)

        for (k in seq_len(nrow(utt_rows))) {
          incProgress(1 / nrow(utt_rows),
                      detail = paste0(k, "/", nrow(utt_rows)))
          utt_row <- utt_rows[k, ]
          d <- tryCatch(
            prepare_aph(rv$df, utt_row$file_id,
                        input$sel_utt_tier, input$sel_word_tier, input$sel_phone_tier,
                        utt_row$time_start),
            error = function(e) NULL
          )
          if (is.null(d) || nrow(d) == 0) next

          fig <- make_aph_plot(d, utt_row$file_id, utt_row$label,
                               input$vars, input$scale == "rel",
                               FALSE, peak_pct, isTRUE(input$show_quartiles))

          safe_file <- gsub("[^A-Za-z0-9]", "_", utt_row$file_id)
          safe_utt  <- substr(
            gsub("[[:space:]]+", "_", gsub("[^A-Za-zÀ-ÿ0-9 ]", "", utt_row$label)),
            1L, 60L
          )
          out_path <- file.path(tmp_dir, paste0(safe_file, "_", safe_utt, ".png"))
          tmp_html <- tempfile(fileext = ".html")

          tryCatch({
            htmlwidgets::saveWidget(fig, tmp_html, selfcontained = TRUE)
            webshot_fn(tmp_html, file = out_path,
                       vwidth = 900, vheight = 560,
                       zoom = 3.125, delay = 1.5, quiet = TRUE)
            if (file.exists(out_path) && file.size(out_path) > 0)
              png_files <- c(png_files, out_path)
          }, error = function(e) NULL)
          unlink(tmp_html)
        }

        if (length(png_files) == 0) {
          showNotification("No se generaron imágenes. ¿Está instalado Chrome/webshot2?",
                           type = "error")
          return(NULL)
        }
        utils::zip(zip_path, files = png_files, flags = "-j")
      })
    }
  )
}

shinyApp(ui, server)
