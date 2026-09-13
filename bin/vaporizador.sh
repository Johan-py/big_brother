#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

MOTIVO="${2:-infraccion_grave}"
DETALLE="${3:-}"

USUARIO=$(usuario_vigilado)
asegurar_dirs

duracion_base() {
  local r=$(( RANDOM % 100 ))
  local min max etiqueta
  if (( r < 30 )); then
    min=6;  max=12; etiqueta="LEVE"
  elif (( r < 55 )); then
    min=12; max=24; etiqueta="ESTANDAR"
  elif (( r < 75 )); then
    min=24; max=48; etiqueta="SEVERA"
  elif (( r < 90 )); then
    min=48; max=60; etiqueta="EXTREMA"
  else
    min=60; max=72; etiqueta="TOTAL"
  fi
  echo "$min $max $etiqueta"
}

calcular_modificadores() {
  local mult=100
  local hoy_epoch=$(date +%s)
  local limite_reincidencia=$(( hoy_epoch - 30*86400 ))
  local total
  total=$(db "SELECT COUNT(*) FROM exilio WHERE inicio >= $limite_reincidencia;" 2>/dev/null || echo 0)
  (( total > 0 )) && mult=$(( mult + 20 ))

  if [[ "$DETALLE" == *"sudo"* ]]; then
    mult=$(( mult + 30 ))
  fi

  if pgrep -u "$USUARIO" -f 'wine|wine64|\.exe' >/dev/null 2>&1; then
    mult=$(( mult + 15 ))
  fi

  echo "$mult"
}

aplicar_exilio() {
  read -r min max etiqueta <<< "$(duracion_base)"
  local horas=$(( min + RANDOM % (max - min + 1) ))
  local mult mult_base maxima
  mult=$(calcular_modificadores)
  mult_base=$(cfg_num EXILIO_MULT 150)
  maxima=$(cfg_num EXILIO_MAX_H 96)
  horas=$(( (horas * mult_base * mult / 100 + 50) / 100 ))
  (( horas < 6 )) && horas=6
  (( horas > maxima )) && horas=$maxima

  local inicio fin dur_seg
  inicio=$(date +%s)
  dur_seg=$(( horas * 3600 ))
  fin=$(( inicio + dur_seg ))

  db "INSERT INTO exilio (inicio,fin,motivo,duracion,etiqueta,mult) VALUES ($inicio,$fin,'$(sql_esc "$MOTIVO")','${horas}h','$(sql_esc "$etiqueta")','base=${mult_base}%+mod=${mult}%');" 2>/dev/null || true

  {
    echo "=== VAPORIZACIÓN $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "CIUDADANO: $USUARIO"
    echo "MOTIVO: $MOTIVO ($DETALLE)"
    echo "DURACIÓN: ${horas}h ($etiqueta, base ${mult_base}% + modificadores ${mult}%)"
    echo "RETORNO: $(date -d "@$fin" '+%Y-%m-%d %H:%M:%S')"
    echo
  } >> "$LOGS_DIR/vaporizaciones/registro.log"

  log_evento "VAPORIZACION" "${horas}h motivo=$MOTIVO"

  if command -v rtcwake >/dev/null 2>&1; then
    rtcwake -m no -t "$fin" 2>/dev/null || true
  fi

  notify_user "$USUARIO" "☠ HAS SIDO VAPORIZADO" \
    "Duración del exilio: ${horas} horas. No hay apelación. El Gran Hermano decide cuándo regresas."

  local ahora minutos_restantes
  ahora=$(date +%s)
  minutos_restantes=$(( (fin - ahora) / 60 + 1 ))
  (( minutos_restantes < 1 )) && minutos_restantes=1
  shutdown -h +"$minutos_restantes" 2>/dev/null || systemctl poweroff 2>/dev/null || true
}

verificar_retorno() {
  local total ultima_fin
  total=$(db "SELECT COUNT(*) FROM exilio;" 2>/dev/null || echo 0)
  (( total > 0 )) || return 1
  ultima_fin=$(exilio_fin || true)
  [[ -n "$ultima_fin" ]] || return 1
  if (( $(date +%s) >= ultima_fin )); then
    if [[ -f "$RUN_DIR/.en_exilio" ]]; then
      rm -f "$RUN_DIR/.en_exilio"
      log_evento "FIN_EXILIO" "El ciudadano $USUARIO regresa del exilio"
      if [[ -f "$ETC_DIR/issue.original" ]]; then
        cp "$ETC_DIR/issue.original" /etc/issue 2>/dev/null || true
      fi
      notify_user "$USUARIO" "👁 EL GRAN HERMANO ES MISERICORDIOSO" \
        "Tu exilio ha terminado. No desperdicies esta segunda oportunidad."
    fi
    return 1
  fi
  return 0
}

imponer_ley_marcial() {
  mkdir -p "$RUN_DIR" 2>/dev/null || true
  touch "$RUN_DIR/.en_exilio" 2>/dev/null || true
  local fin mensaje
  fin=$(exilio_fin)
  mensaje="☠ CIUDADANO EN EXILIO ☠
El Gran Hermano ha vaporizado tu presencia.
Retorno: $(date -d "@$fin" '+%Y-%m-%d %H:%M:%S')
La resistencia es inútil."

  if [[ ! -f "$ETC_DIR/issue.original" ]]; then
    cp /etc/issue "$ETC_DIR/issue.original" 2>/dev/null || true
  fi
  { echo "$mensaje" > /etc/issue; } 2>/dev/null || true

  local ses
  if ses=$(sesion_grafica "$USUARIO"); then
    loginctl terminate-session "$ses" 2>/dev/null || true
  fi
}

case "${1:-}" in
  ejecutar)
    aplicar_exilio
    ;;
  verificar)
    if exilio_activo; then
      imponer_ley_marcial || true
      exit 0
    else
      verificar_retorno || true
      exit 1
    fi
    ;;
  estado)
    if exilio_activo; then
      fin=$(exilio_fin)
      echo "EN_EXILIO hasta $(date -d "@$fin" '+%Y-%m-%d %H:%M:%S')"
    else
      echo "LIBRE"
    fi
    ;;
  *)
    echo "uso: vaporizador.sh {ejecutar|verificar|estado} [motivo] [detalle]"
    exit 1
    ;;
esac