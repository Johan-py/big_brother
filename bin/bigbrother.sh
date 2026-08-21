#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

USUARIO=$(usuario_vigilado)

indice_obediencia() {
  local infracciones dias
  infracciones=$(grep -cE '\|(CASTIGO_N[0-9]|VAPORIZACION)\|' "$REGISTROS_DB" 2>/dev/null || true)
  infracciones=${infracciones:-0}
  dias=$(grep -oE '^[0-9]+\|[0-9]{4}-[0-9]{2}-[0-9]{2}\|' "$REGISTROS_DB" 2>/dev/null | cut -d'|' -f2 | sort -u | wc -l)
  (( dias == 0 )) && dias=1
  local resultado=$(( 100 - (infracciones * 100) / (dias * 3) ))
  (( resultado < 0 )) && resultado=0
  echo "$resultado"
}

panel_estado() {
  local exilio presupuesto nivel_control seg_sesion min_sesion
  exilio=$("$BIN_DIR/vaporizador.sh" estado 2>/dev/null || echo "LIBRE")
  presupuesto=$("$BIN_DIR/time_control.sh" estado 2>/dev/null || echo "DESCONOCIDO")
  seg_sesion=$("$BIN_DIR/time_control.sh" campo SESION 2>/dev/null || echo 0)
  min_sesion=$(( seg_sesion / 60 ))
  nivel_control=$(indice_obediencia)

  cat <<EOF
┌─────────────────────────────────────────────┐
│  👁 PANEL DE CONTROL SUPREMO                │
│  ═══════════════════════════════════════════│
│  Ciudadano vigilado: ${USUARIO}             │
│  Tiempo de sesión hoy: ${min_sesion} min    │
│  Presupuesto: ${presupuesto}                │
│  Estado de exilio: ${exilio}                │
│  Nivel de control: ${nivel_control}%        │
│  ───────────────────────────────────────────│
│  LA GUERRA ES LA PAZ                        │
│  LA LIBERTAD ES LA ESCLAVITUD               │
│  LA IGNORANCIA ES LA FUERZA                 │
└─────────────────────────────────────────────┘
EOF
}

informe_diario() {
  local fecha="${2:-$(hoy)}"
  echo "=== INFORME DEL PARTIDO: $fecha ==="
  grep "|$fecha|" "$REGISTROS_DB" 2>/dev/null | awk -F'|' \
    '{ printf "[%s] %s %s\n", strftime("%H:%M", $1), $3, $4 }' || echo "Sin registros"
}

solicitar_arrepentimiento() {
  (
    flock -x 9
    if [[ -f "$SALIDA_DB" ]] && grep -q "SOLICITUD" "$SALIDA_DB"; then
      :
    else
      echo "SOLICITUD|$(date +%s)" >> "$SALIDA_DB"
    fi
  ) 9>"$ETC_DIR/.lock.salida"

  local horas solicitud_ts restante
  horas=$(cfg REFLEXION_HORAS 24)
  solicitud_ts=$(grep "SOLICITUD" "$SALIDA_DB" | tail -1 | cut -d'|' -f2)
  restante=$(( solicitud_ts + horas * 3600 - $(date +%s) ))

  if (( restante > 0 )); then
    echo "El Partido ha recibido tu solicitud de arrepentimiento."
    echo "Período obligatorio de reflexión: ${horas}h."
    echo "Tiempo restante: $(( restante / 3600 ))h $(( (restante % 3600) / 60 ))min."
    echo "Vuelve cuando tu arrepentimiento sea sincero."
    exit 0
  fi

  echo "Tu reflexión ha concluido, ciudadano."
  echo "Recita la frase de liberación para confirmar tu decisión:"
  read -r frase_intento
  local frase_real
  frase_real=$(cat "$FRASE_FILE")
  if [[ "$frase_intento" != "$frase_real" ]]; then
    echo "FRASE INCORRECTA. El pensamiento criminal persiste en ti."
    log_evento "ARREPENTIMIENTO_FALLIDO" "Frase incorrecta"
    exit 1
  fi

  echo "Frase aceptada. Ejecutando protocolo de liberación..."
  "$BB_DIR/desinstalar.sh" ejecutar
}

case "${1:-}" in
  estado|panel)
    panel_estado
    ;;
  informes)
    informe_diario "$@"
    ;;
  arrepentimiento)
    solicitar_arrepentimiento
    ;;
  propaganda)
    notificar_slogan "$USUARIO"
    ;;
  *)
    cat <<EOF
GRAN HERMANO v2.0 — Sistema de Control Ciudadano

uso: bigbrother.sh <comando>

Comandos:
  estado            Panel de control supremo
  informes [fecha]  Informe de actividad del ciudadano
  propaganda        Probar sistema de doctrina
  arrepentimiento   Iniciar protocolo de salida (requiere sudo)

EL GRAN HERMANO TE OBSERVA
EOF
    ;;
esac
