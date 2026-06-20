# Test de los helpers de portabilidad. Ejecutar desde Oralstats/:
#   Rscript tests/test_portability.R
source("R/portability.R")

# oralstats_python() devuelve NA o la ruta a un intérprete existente
py <- oralstats_python()
stopifnot(length(py) == 1L)
stopifnot(is.na(py) || file.exists(py))

cat("OK: oralstats_python\n")
