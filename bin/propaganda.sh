#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

USUARIO=$(usuario_vigilado)
[[ -n "$USUARIO" ]] || exit 1

asegurar_dirs
migrar_legado
validar_config

INTERVALO_BASE=$(cfg_num PROPAGANDA_INTERVALO_MIN 5)

EVENTOS_ESPECIALES=(
  "HOY ES EL DÍA DE LA OBEDIENCIA. CELEBRA TRABAJANDO."
  "SEMANA DEL ODIO: DIRIGE TU IRA HACIA LOS ENEMIGOS DEL PARTIDO."
  "RECUERDA: DESDE 1984 EL PARTIDO LUCHA POR TI."
  "CIUDADANO MODELO: AQUEL QUE NO PIENSA."
)

es_dia_especial() {
  local dia_mes
  dia_mes=$(date +%d)
  [[ "$dia_mes" == "01" ]]
}

propagar() {
  local mensaje
  if es_dia_especial && (( RANDOM % 3 == 0 )); then
    mensaje=${EVENTOS_ESPECIALES[$((RANDOM % ${#EVENTOS_ESPECIALES[@]}))]}
    notify_user "$USUARIO" "★ EVENTO DEL PARTIDO ★" "$mensaje"
  else
    notificar_slogan "$USUARIO"
  fi
}

log_evento "ARRANQUE_PROPAGANDA" "Doctrina activa para $USUARIO"

while true; do
  sleep $(( INTERVALO_BASE * 60 + RANDOM % 240 ))
  propagar
done