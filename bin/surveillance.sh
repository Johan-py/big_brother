#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TICK=30
INTERVALO_HORAS=$(cfg INTERVALO_HORAS 1)

USUARIO=$(usuario_vigilado)
[[ -n "$USUARIO" ]] || { echo "No hay ciudadano registrado"; exit 1; }

FECHA_FILE="$RUN_DIR/.fecha.actual"
marcador_hora() { echo "$RUN_DIR/.hora.$(hoy)"; }
mkdir -p "$RUN_DIR" 2>/dev/null || true
[[ -f "$FECHA_FILE" ]] || hoy > "$FECHA_FILE"

horas_uso() {
  local seg
  seg=$("$BIN_DIR/time_control.sh" campo SESION 2>/dev/null || echo 0)
  echo $(( seg / 3600 ))
}

lanzar_flujo() {
  local horas="$1" aviso
  aviso=$("$BIN_DIR/gilfoyle.py" notificacion "$horas" 2>/dev/null || true)
  [[ -n "$aviso" ]] || aviso="Llevas $horas hora(s) frente a la pantalla. El Gran Hermano sugiere que hagas algo productivo."
  notify_user "$USUARIO" "👁 GRAN HERMANO" "$aviso"
  log_evento "AVISO_HORA" "hora $horas de uso"

  ( sleep 10
    msg=$("$BIN_DIR/gilfoyle.py" terminal "$horas" 2>/dev/null || true)
    [[ -n "$msg" ]] || msg="$horas hora(s) y sigues aquí. Deja la pantalla y haz algo útil antes de que yo lo haga por ti."
    bash -c "$(printf '%q ' "$BIN_DIR/mostrar_aviso.sh" "$msg")"
  ) >/dev/null 2>&1 &
  disown

  ( sleep 300
    "$BIN_DIR/travesuras.sh"
  ) >/dev/null 2>&1 &
  disown
}

evaluar_hora() {
  (( INTERVALO_HORAS > 0 )) || return 0
  local horas mp ultima
  horas=$(horas_uso)
  (( horas >= INTERVALO_HORAS )) || return 0
  mp=$(marcador_hora)
  [[ -f "$mp" ]] || echo 0 > "$mp"
  ultima=$(cat "$mp")
  if (( horas > ultima )); then
    echo "$horas" > "$mp"
    lanzar_flujo "$horas"
  fi
}

vigilar() {
  if [[ "$(cat "$FECHA_FILE")" != "$(hoy)" ]]; then
    hoy > "$FECHA_FILE"
    "$BIN_DIR/time_control.sh" limpiar || true
    log_evento "RESET_DIARIO" "Nuevo día, contador de tiempo reiniciado"
  fi

  if ses=$(sesion_grafica "$USUARIO"); then
    "$BIN_DIR/time_control.sh" sumar SESION "$TICK" || true
  fi

  evaluar_hora || true
}

log_evento "ARRANQUE_VIGILANCIA" "Vigilancia de tiempo de uso iniciada sobre $USUARIO"

while true; do
  vigilar || true
  sleep "$TICK"
done