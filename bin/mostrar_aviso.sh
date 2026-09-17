#!/usr/bin/env bash
# mostrar_aviso.sh - abre una terminal en la sesión del usuario y escribe el
# mensaje de Gilfoyle con efecto máquina de escribir.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

USUARIO=$(usuario_vigilado)

tipear() {
  local archivo="$1" duracion="${2:-60}"
  local linea i
  clear
  printf '\n%s\n\n' "$(printf '═%.0s' {1..50})"
  while IFS= read -r linea; do
    for (( i = 0; i < ${#linea}; i++ )); do
      printf '%s' "${linea:i:1}"
      sleep 0.02
    done
    echo
    sleep 0.15
  done < "$archivo"
  printf '\n%s\n\n' "$(printf '═%.0s' {1..50})"
  printf '— Gilfoyle\n\n'
  sleep "$duracion"
  exit 0
}

if [[ "${1:-}" == "tipear" ]]; then
  tipear "$2" "${3:-60}"
fi

mensaje="${1:-}"
archivo="$RUN_DIR/aviso_$(hoy)_$$.txt"
printf '%s\n' "$mensaje" > "$archivo" 2>/dev/null || {
  archivo=$(mktemp)
  printf '%s\n' "$mensaje" > "$archivo"
}
abrir_terminal_usuario "$USUARIO" "$0" tipear "$archivo" 60 || true