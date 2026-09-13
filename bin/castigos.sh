#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

USUARIO="${2:-$(usuario_vigilado)}"
MOTIVO="${3:-infraccion}"
DETALLE="${4:-}"

OVERLAY_PIDFILE="$RUN_DIR/overlay.pid"
BLOQUEO_GUARD="$RUN_DIR/bloqueo.guard"

tipo_sesion() {
  local ses
  if ses=$(sesion_grafica "$USUARIO"); then
    loginctl show-session "$ses" -p Type --value 2>/dev/null || echo "desconocido"
  else
    echo "ninguna"
  fi
}

cerrar_overlay_activo() {
  pkill -u "$USUARIO" -f 'feh -F' 2>/dev/null || true
  pkill -u "$USUARIO" -f 'swayimg' 2>/dev/null || true
  pkill -u "$USUARIO" -f 'imv' 2>/dev/null || true
  rm -f "$OVERLAY_PIDFILE"
}

mostrar_overlay() {
  local imagen="$1" duracion="$2"
  local tipo
  tipo=$(tipo_sesion)
  case "$tipo" in
    x11)
      (
        run_as_user "$USUARIO" feh -F -Z -Y "$imagen" &
        sleep "$duracion"
        cerrar_overlay_activo
      ) &
      ;;
    wayland)
      if command -v swayimg >/dev/null 2>&1; then
        ( run_as_user "$USUARIO" swayimg -f -N "$imagen" & sleep "$duracion"; cerrar_overlay_activo ) &
      elif command -v imv >/dev/null 2>&1; then
        ( run_as_user "$USUARIO" imv "$imagen" & sleep "$duracion"; cerrar_overlay_activo ) &
      else
        :
      fi
      ;;
  esac
}

bloquear_entrada() {
  local duracion="$1"
  if [[ "$(tipo_sesion)" != "x11" ]]; then
    return 0
  fi
  (
    local ids teclado_puntero
    ids=$(run_as_user "$USUARIO" xinput --list --short 2>/dev/null | grep -Ei 'keyboard|mouse|pointer' | grep -v 'XTEST\|Virtual core' | grep -oE 'id=[0-9]+' | cut -d= -f2 || true)
    for id in $ids; do
      run_as_user "$USUARIO" xinput disable "$id" 2>/dev/null || true
    done
    echo "$ids" > "$BLOQUEO_GUARD"
    sleep "$duracion"
    for id in $(cat "$BLOQUEO_GUARD" 2>/dev/null); do
      run_as_user "$USUARIO" xinput enable "$id" 2>/dev/null || true
    done
    rm -f "$BLOQUEO_GUARD"
  ) &
  disown
}

desbloquear_entrada() {
  if [[ -f "$BLOQUEO_GUARD" ]]; then
    for id in $(cat "$BLOQUEO_GUARD"); do
      run_as_user "$USUARIO" xinput enable "$id" 2>/dev/null || true
    done
    rm -f "$BLOQUEO_GUARD"
  fi
}

cerrar_overlays() {
  cerrar_overlay_activo
  desbloquear_entrada
}

castigo_nivel1() {
  local dur=$(( 5 + RANDOM % 4 ))
  notify_user "$USUARIO" "⚠ ADVERTENCIA DEL GRAN HERMANO" \
    "El Gran Hermano ha notado tu transgresión: $MOTIVO. Corrige tu conducta."
  mostrar_overlay "$ASSETS_DIR/gran_hermano.png" "$dur"
  log_castigo 1 "$MOTIVO" "$DETALLE (overlay ${dur}s)"
}

castigo_nivel2() {
  local dur=$(( 8 + RANDOM % 4 ))
  notify_user "$USUARIO" "👁 LA VISITA DE O'BRIEN" \
    "Tu pensamiento criminal ha sido registrado. Motivo: $MOTIVO."
  mostrar_overlay "$ASSETS_DIR/obrien.png" "$dur"
  log_castigo 2 "$MOTIVO" "$DETALLE (overlay ${dur}s)"
  (
    sleep 60
    notificar_slogan "$USUARIO"
    sleep 90
    notify_user "$USUARIO" "👁 O'BRIEN" "Seguiremos observando. Siempre."
  ) &
  disown
}

castigo_nivel3() {
  local duracion="${5:-900}"
  notify_user "$USUARIO" "👁 LA OMNIPRESENCIA" \
    "La resistencia es inútil. Ríndete. Sesión suspendida por ${duracion}s."
  log_castigo 3 "$MOTIVO" "$DETALLE (omnipresencia ${duracion}s)"
  bloquear_entrada "$duracion"
  ses=$(sesion_grafica "$USUARIO" || true)
  [[ -n "${ses:-}" ]] && loginctl lock-session "$ses" 2>/dev/null || true
  local fin=$(( $(date +%s) + duracion ))
  while (( $(date +%s) < fin )); do
    mostrar_overlay "$ASSETS_DIR/gran_hermano.png" 15
    sleep 14
  done
  cerrar_overlays
  [[ -n "${ses:-}" ]] && loginctl unlock-session "$ses" 2>/dev/null || true
}

castigo_nivel4() {
  log_castigo 4 "$MOTIVO" "$DETALLE (vaporización)"
  notify_user "$USUARIO" "☠ VAPORIZACIÓN" \
    "Has sido vaporizado. No hay apelación. El sistema se apagará."
  sleep 10
  exec "$BIN_DIR/vaporizador.sh" ejecutar "$MOTIVO" "$DETALLE"
}

case "${1:-}" in
  nivel1) castigo_nivel1 ;;
  nivel2) castigo_nivel2 ;;
  nivel3) castigo_nivel3 ;;
  nivel4) castigo_nivel4 ;;
  detener) cerrar_overlays ;;
  *)
    echo "uso: castigos.sh {nivel1|nivel2|nivel3|nivel4|detener} [usuario] [motivo] [detalle] [duracion_n3]"
    exit 1
    ;;
esac