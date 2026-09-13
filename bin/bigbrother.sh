#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

asegurar_dirs
migrar_legado

USUARIO=$(usuario_vigilado)
if [[ -z "$USUARIO" ]]; then
  cat <<'EOF'
👁 EL GRAN HERMANO NO VIGILA A NADIE TODAVÍA.

  El Partido no está instalado o no hay ciudadano registrado.
  - Instalación:  sudo ./instalar.sh   (desde el directorio del proyecto)
  - Verifica que /opt/bigbrother/etc/config.conf tenga USUARIO_VIGILADO.
EOF
  exit 1
fi

indice_obediencia() {
  local limite hace30 infracciones dias resultado
  hace30=$(date -d "-30 days" +%F)
  limite=$(( $(date +%s) - 30*86400 ))
  infracciones=$(dbq "SELECT COUNT(*) FROM registros WHERE ts >= $limite AND (evento LIKE 'CASTIGO_N%' OR evento='VAPORIZACION');" 2>/dev/null || echo 0)
  dias=$(dbq "SELECT COUNT(DISTINCT dia) FROM tiempo WHERE dia >= '$(sql_esc "$hace30")';" 2>/dev/null || echo 0)
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
  local fecha="${2:-$(hoy)}" total
  echo "=== INFORME DEL PARTIDO: $fecha ==="
  total=$(dbq "SELECT COUNT(*) FROM registros WHERE fecha='$(sql_esc "$fecha")';" 2>/dev/null || echo 0)
  (( total > 0 )) || { echo "Sin registros"; return; }
  dbq "SELECT ts,evento,detalle FROM registros WHERE fecha='$(sql_esc "$fecha")' ORDER BY ts;" 2>/dev/null \
    | while IFS='|' read -r ts evento detalle; do
        printf "[%s] %s %s\n" "$(date -d "@$ts" '+%H:%M')" "$evento" "$detalle"
      done
}

solicitar_arrepentimiento() {
  local ahora
  ahora=$(date +%s)
  db "INSERT INTO salida (tipo,ts) SELECT 'SOLICITUD',$ahora WHERE NOT EXISTS (SELECT 1 FROM salida WHERE tipo='SOLICITUD');" 2>/dev/null || true

  local horas solicitud_ts restante
  horas=$(cfg_num REFLEXION_HORAS 24)
  solicitud_ts=$(dbq "SELECT MAX(ts) FROM salida WHERE tipo='SOLICITUD';" 2>/dev/null || echo 0)
  restante=$(( solicitud_ts + horas * 3600 - ahora ))

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
GRAN HERMANO v3.0 — Sistema de Control Ciudadano

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