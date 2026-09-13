#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

DIAS_LIMITE=400

campo_actual() {
  local campo="$1" dia="${2:-$(hoy)}"
  dbq "SELECT IFNULL((SELECT segundos FROM tiempo WHERE pk='${campo}:${dia}'),0);" 2>/dev/null || echo 0
}

sumar_segundos() {
  local campo="$1" segundos="$2" dia
  dia=$(hoy)
  db "INSERT INTO tiempo (pk,dia,segundos) VALUES ('${campo}:${dia}','$(sql_esc "$dia")',$segundos)
      ON CONFLICT(pk) DO UPDATE SET segundos = segundos + excluded.segundos;" 2>/dev/null || true
}

obtener_campo() {
  campo_actual "$1"
}

limpiar_dias_anteriores() {
  db "DELETE FROM tiempo WHERE dia != '$(hoy)';" 2>/dev/null || true
}

segundos_sesion() { obtener_campo "SESION"; }
segundos_youtube() { obtener_campo "YOUTUBE"; }
segundos_wine() { obtener_campo "WINE"; }

exceso_minutos() {
  local sesion limite total
  sesion=$(segundos_sesion)
  limite=$(( $(cfg_num LIMITE_DIARIO_MIN 180) * 60 ))
  extra=$(( $(cfg_num TIEMPO_EXTRA_MIN 60) * 60 ))
  total=$(( limite + extra ))
  echo $(( (sesion - limite) / 60 ))
}

estado_presupuesto() {
  local sesion limite
  sesion=$(segundos_sesion)
  limite=$(( $(cfg_num LIMITE_DIARIO_MIN 180) * 60 ))
  if (( sesion < limite )); then
    echo "DENTRO_DE_LIMITE"
  else
    local exceso=$(( sesion - limite ))
    local extra=$(( $(cfg_num TIEMPO_EXTRA_MIN 60) * 60 ))
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