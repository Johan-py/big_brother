#!/usr/bin/env bash
set -euo pipefail

BB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$BB_DIR/bin"
ETC_DIR="$BB_DIR/etc"
LOGS_DIR="$BB_DIR/logs"
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
FRASE_FILE="$ETC_DIR/frase_liberacion"

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

_terminals=(
  kitty konsole xfce4-terminal gnome-terminal alacritty wezterm xterm urxvt x-terminal-emulator
)

detectar_terminal() {
  local t
  for t in "${_terminals[@]}"; do
    if command -v "$t" >/dev/null 2>&1; then
      echo "$t"
      return 0
    fi
  done
  return 1
}

abrir_terminal_usuario() {
  local usuario="$1"
  shift
  local fullscreen=0
  if [[ "${1:-}" == "--fullscreen" ]]; then
    fullscreen=1
    shift
  fi
  local term
  term=$(detectar_terminal) || return 1
  case "$term" in
    kitty)
      run_as_user "$usuario" kitty -e "$@" ;;
    konsole)
      if (( fullscreen )); then
        run_as_user "$usuario" konsole --noclose --fullscreen -e "$@" 
      else
        run_as_user "$usuario" konsole --noclose -e "$@"
      fi ;;
    xfce4-terminal)
      if (( fullscreen )); then
        run_as_user "$usuario" xfce4-terminal --hold --fullscreen -x "$@"
      else
        run_as_user "$usuario" xfce4-terminal --hold -x "$@"
      fi ;;
    gnome-terminal)
      run_as_user "$usuario" gnome-terminal -- "$@" ;;
    alacritty)
      run_as_user "$usuario" alacritty -e "$@" ;;
    wezterm)
      run_as_user "$usuario" wezterm start -- "$@" ;;
    xterm)
      if (( fullscreen )); then
        run_as_user "$usuario" xterm -fullscreen -e "$@"
      else
        run_as_user "$usuario" xterm -e "$@"
      fi ;;
    urxvt)
      run_as_user "$usuario" urxvt -e "$@" ;;
    x-terminal-emulator)
      run_as_user "$usuario" x-terminal-emulator -e "$@" ;;
    *)
      return 1 ;;
  esac
}