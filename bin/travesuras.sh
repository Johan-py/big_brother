#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

USUARIO=$(usuario_vigilado)
[[ -n "$USUARIO" ]] || exit 1

HOGAR=$(getent passwd "$USUARIO" | cut -d: -f6)
MUSICA_DIR=$(cfg MUSICA_DIR "$HOGAR/Music")

encontrar_musica() {
  [[ -d "$MUSICA_DIR" ]] || return 1
  local f
  f=$(find "$MUSICA_DIR" -type f \
      \( -iname '*.mp3' -o -iname '*.ogg' -o -iname '*.oga' -o -iname '*.wav' \
         -o -iname '*.flac' -o -iname '*.m4a' -o -iname '*.opus' \) \
      2>/dev/null | sort -R | head -1)
  [[ -n "$f" ]] && echo "$f" || return 1
}

detectar_jugador() {
  local j
  for j in mpv ffplay mpg123 ogg123 play paplay; do
    command -v "$j" >/dev/null 2>&1 && { echo "$j"; return 0; }
  done
  return 1
}

flags_jugador() {
  case "$1" in
    mpv)   echo "--no-video --really-quiet" ;;
    ffplay) echo "-nodisp -autoexit -loglevel quiet" ;;
    mpg123 | ogg123 | play) echo "-q" ;;
    paplay) echo "" ;;
  esac
}

travesura_apagar() {
  notify_user "$USUARIO" "⚡ APAGADO FORZOSO" \
    "Gilfoyle: suficiente. El sistema se apaga en 60 segundos. Guarda lo poco que valga la pena."
  log_evento "TRAVESURA" "apagar"
  shutdown -h +1 2>/dev/null || systemctl poweroff 2>/dev/null || true
}

travesura_musica() {
  local archivo jugador
  archivo=$(encontrar_musica) || return 1
  jugador=$(detectar_jugador) || return 1
  notify_user "$USUARIO" "🎵 MÚSICA ALEATORIA" \
    "Gilfoyle te elige la banda sonora de tu procrastinación."
  # shellcheck disable=SC2086
  run_as_user "$USUARIO" "$jugador" $(flags_jugador "$jugador") "$archivo" >/dev/null 2>&1 &
  local pid=$!
  log_evento "TRAVESURA" "musica:$archivo"
  sleep 45
  kill "$pid" 2>/dev/null || true
  pkill -u "$USUARIO" -f "$(basename "$jugador")" 2>/dev/null || true
}

travesura_hackeo() {
  log_evento "TRAVESURA" "hackeo falso"
  abrir_terminal_usuario "$USUARIO" --fullscreen "$BIN_DIR/fake_hack.sh" \
    || notify_user "$USUARIO" "👁 GRAN HERMANO" "Hackeando tus prioridades..."
}

jugar() {
  local r
  r=$(( RANDOM % 3 ))
  case "$r" in
    0) travesura_apagar ;;
    1) travesura_musica || notify_user "$USUARIO" "🎵 MÚSICA" "No hay música en $MUSICA_DIR. Escapas esta vez." ;;
    2) travesura_hackeo ;;
  esac
}

jugar