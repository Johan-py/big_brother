#!/usr/bin/env bash
set -euo pipefail

BB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$BB_DIR/bin"
ETC_DIR="$BB_DIR/etc"
LOGS_DIR="$BB_DIR/logs"
ASSETS_DIR="$BB_DIR/assets"
if mkdir -p /run/bigbrother 2>/dev/null; then
  RUN_DIR="/run/bigbrother"
else
  RUN_DIR="$BB_DIR/run"
fi
mkdir -p "$RUN_DIR" 2>/dev/null || true

CONFIG="$ETC_DIR/config.conf"
USUARIOS_DB="$ETC_DIR/usuarios.db"
REGISTROS_DB="$ETC_DIR/registros.db"
TIEMPO_DB="$ETC_DIR/tiempo.db"
CASTIGOS_DB="$ETC_DIR/castigos.db"
EXILIO_DB="$ETC_DIR/exilio.db"
SALIDA_DB="$ETC_DIR/salida.db"
FRASE_FILE="$ETC_DIR/frase_liberacion"

SLOGANS=(
  "LA GUERRA ES LA PAZ"
  "LA LIBERTAD ES LA ESCLAVITUD"
  "LA IGNORANCIA ES LA FUERZA"
  "EL GRAN HERMANO TE OBSERVA"
  "EL PENSAMIENTO CRIMINAL NO PASA DESAPERCIBIDO"
  "OBEDECE. EL PARTIDO PROTEGE."
  "TUS ACTOS SON REGISTRADOS. TUS SUEÑOS TAMBIÉN."
  "LA RESISTENCIA ES INÚTIL. RÍNDETE."
)

cfg() {
  local clave="$1" valor_def="${2:-}"
  local linea
  linea=$(grep -E "^${clave}=" "$CONFIG" 2>/dev/null | tail -1 | cut -d= -f2-)
  echo "${linea:-$valor_def}"
}

usuario_vigilado() {
  awk -F'|' 'NR>0 {print $1}' "$USUARIOS_DB" 2>/dev/null | head -1
}

hoy() {
  date +%Y-%m-%d
}

log_evento() {
  local evento="$1" detalle="${2:-}"
  local linea
  linea="$(date +%s)|$(hoy)|$evento|$detalle"
  (
    flock -x 9
    echo "$linea" >> "$REGISTROS_DB"
  ) 9>"$ETC_DIR/.lock.registros"
}

log_castigo() {
  local nivel="$1" motivo="$2" detalle="${3:-}"
  local dir
  dir="$LOGS_DIR/castigos"
  mkdir -p "$dir"
  {
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "NIVEL: $nivel"
    echo "MOTIVO: $motivo"
    echo "DETALLE: $detalle"
    echo
  } >> "$dir/registro.log"
  log_evento "CASTIGO_N$nivel" "$motivo: $detalle"
}

sesion_grafica() {
  local usuario="$1" ses_id tipo estado
  ses_id=$(loginctl list-sessions --no-legend 2>/dev/null \
    | awk -v u="$usuario" '$3==u {print $1}' \
    | while read -r s; do
        tipo=$(loginctl show-session "$s" -p Type --value 2>/dev/null || true)
        estado=$(loginctl show-session "$s" -p State --value 2>/dev/null || true)
        if [[ "$tipo" == "x11" || "$tipo" == "wayland" ]] && [[ "$estado" == "active" ]]; then
          echo "$s"
          break
        fi
      done | head -1)
  [[ -n "$ses_id" ]] && echo "$ses_id" || return 1
}

user_env() {
  local usuario="$1" clave="$2" pid
  for pid in $(pgrep -u "$usuario" 2>/dev/null | head -50); do
    local val
    val=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep "^${clave}=" | head -1 | cut -d= -f2-)
    if [[ -n "$val" ]]; then
      echo "$val"
      return 0
    fi
  done
  return 1
}

run_as_user() {
  local usuario="$1"
  shift
  local display xauth wayland
  if display=$(user_env "$usuario" DISPLAY) && [[ -n "$display" ]]; then
    xauth=$(user_env "$usuario" XAUTHORITY || echo "/home/$usuario/.Xauthority")
    env DISPLAY="$display" XAUTHORITY="$xauth" sudo -u "$usuario" -- "$@" 2>/dev/null
  elif wayland=$(user_env "$usuario" WAYLAND_DISPLAY) && [[ -n "$wayland" ]]; then
    local xdg_runtime
    xdg_runtime=$(user_env "$usuario" XDG_RUNTIME_DIR || echo "/run/user/$(id -u "$usuario")")
    env WAYLAND_DISPLAY="$wayland" XDG_RUNTIME_DIR="$xdg_runtime" sudo -u "$usuario" -- "$@" 2>/dev/null
  else
    return 1
  fi
}

notify_user() {
  local usuario="$1" titulo="$2" mensaje="$3" urgencia="${4:-critical}"
  run_as_user "$usuario" notify-send -u "$urgencia" -t 10000 "$titulo" "$mensaje" || true
}

notificar_slogan() {
  local usuario="$1"
  local slogan=${SLOGANS[$((RANDOM % ${#SLOGANS[@]}))]}
  notify_user "$usuario" "👁 GRAN HERMANO" "$slogan"
}

exilio_activo() {
  [[ -f "$EXILIO_DB" ]] || return 1
  local ahora fin
  ahora=$(date +%s)
  fin=$(tail -1 "$EXILIO_DB" 2>/dev/null | cut -d'|' -f2)
  [[ -n "$fin" && "$fin" =~ ^[0-9]+$ ]] || return 1
  (( ahora < fin )) && return 0
  return 1
}

exilio_fin() {
  tail -1 "$EXILIO_DB" 2>/dev/null | cut -d'|' -f2
}

asegurar_dirs() {
  mkdir -p "$RUN_DIR" "$LOGS_DIR/vigilancia" "$LOGS_DIR/castigos" "$LOGS_DIR/vaporizaciones" "$ASSETS_DIR/propaganda"
  touch "$REGISTROS_DB" "$TIEMPO_DB" "$CASTIGOS_DB" "$EXILIO_DB" "$SALIDA_DB"
}
