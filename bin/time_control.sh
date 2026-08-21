#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TIEMPO_HOY="$ETC_DIR/.tiempo.$(hoy)"

campo_actual() {
  local campo="$1"
  grep "^${campo}=" "$TIEMPO_HOY" 2>/dev/null | cut -d= -f2 || echo 0
}

sumar_segundos() {
  local campo="$1" segundos="$2"
  (
    flock -x 9
    local actual nuevo
    actual=$(grep "^${campo}=" "$TIEMPO_HOY" 2>/dev/null | cut -d= -f2 || true)
    actual=${actual:-0}
    nuevo=$(( actual + segundos ))
    if grep -q "^${campo}=" "$TIEMPO_HOY" 2>/dev/null; then
      sed -i "s/^${campo}=.*$/${campo}=${nuevo}/" "$TIEMPO_HOY"
    else
      echo "${campo}=${nuevo}" >> "$TIEMPO_HOY"
    fi
  ) 9>"$ETC_DIR/.lock.tiempo"
}

obtener_campo() {
  local campo="$1"
  campo_actual "$campo"
}

limpiar_dias_anteriores() {
  find "$ETC_DIR" -name ".tiempo.*" -type f ! -name ".tiempo.$(hoy)" -delete 2>/dev/null || true
}

segundos_sesion() { obtener_campo "SESION"; }
segundos_youtube() { obtener_campo "YOUTUBE"; }
segundos_wine() { obtener_campo "WINE"; }

exceso_minutos() {
  local sesion limite extra total
  sesion=$(segundos_sesion)
  limite=$(( $(cfg LIMITE_DIARIO_MIN 180) * 60 ))
  extra=$(( $(cfg TIEMPO_EXTRA_MIN 60) * 60 ))
  total=$(( limite + extra ))
  echo $(( (sesion - limite) / 60 ))
}

estado_presupuesto() {
  local sesion limite
  sesion=$(segundos_sesion)
  limite=$(( $(cfg LIMITE_DIARIO_MIN 180) * 60 ))
  if (( sesion < limite )); then
    echo "DENTRO_DE_LIMITE"
  else
    local exceso=$(( sesion - limite ))
    local extra=$(( $(cfg TIEMPO_EXTRA_MIN 60) * 60 ))
    if (( exceso <= extra )); then
      echo "EN_TIEMPO_EXTRA"
    else
      echo "EXCESO_GRAVE"
    fi
  fi
}

case "${1:-}" in
  sumar)
    sumar_segundos "$2" "$3"
    ;;
  campo)
    obtener_campo "$2"
    ;;
  exceso)
    exceso_minutos
    ;;
  estado)
    estado_presupuesto
    ;;
  limpiar)
    limpiar_dias_anteriores
    ;;
  *)
    echo "uso: time_control.sh {sumar campo segundos|campo nombre|exceso|estado|limpiar}"
    exit 1
    ;;
esac
