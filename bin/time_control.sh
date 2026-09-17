#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TIEMPO_HOY="$ETC_DIR/.tiempo.$(hoy)"

campo_actual() {
  local campo="$1"
  grep "^${campo}=" "$TIEMPO_HOY" 2>/dev/null | cut -d= -f2 || echo 0
}

sumar_segundos() {
  local campo="$1" seg="${2:-0}"
  (
    flock -x 9
    local actual nuevo
    actual=$(campo_actual "$campo")
    nuevo=$(( actual + seg ))
    if grep -q "^${campo}=" "$TIEMPO_HOY" 2>/dev/null; then
      sed -i "s/^${campo}=.*$/${campo}=${nuevo}/" "$TIEMPO_HOY"
    else
      echo "${campo}=${nuevo}" >> "$TIEMPO_HOY"
    fi
  ) 9>"$ETC_DIR/.lock.tiempo"
}

obtener_campo() {
  campo_actual "$1"
}

limpiar_dias_anteriores() {
  find "$ETC_DIR" -name ".tiempo.*" -type f ! -name ".tiempo.$(hoy)" -delete 2>/dev/null || true
}

case "${1:-}" in
  sumar)
    sumar_segundos "$2" "$3"
    ;;
  campo)
    obtener_campo "$2"
    ;;
  limpiar)
    limpiar_dias_anteriores
    ;;
  *)
    echo "uso: time_control.sh {sumar campo segundos|campo nombre|limpiar}"
    exit 1
    ;;
esac