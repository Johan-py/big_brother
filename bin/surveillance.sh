#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TICK=30
INTERVALO_YOUTUBE=300
INTERVALO_SUDO=60
PESO_YOUTUBE_SEG=$(cfg PESO_YOUTUBE_SEG 60)

USUARIO=$(usuario_vigilado)
[[ -n "$USUARIO" ]] || { echo "No hay ciudadano registrado"; exit 1; }

asegurar_dirs

SUDO_DESDE_FILE="$RUN_DIR/.sudo.desde"
YOUTUBE_DESDE_FILE="$RUN_DIR/.youtube.desde"
FECHA_FILE="$RUN_DIR/.fecha.actual"

if [[ ! -f "$SUDO_DESDE_FILE" ]]; then
  date +%s > "$SUDO_DESDE_FILE"
fi
if [[ ! -f "$YOUTUBE_DESDE_FILE" ]]; then
  date +%s > "$YOUTUBE_DESDE_FILE"
fi
if [[ ! -f "$FECHA_FILE" ]]; then
  hoy > "$FECHA_FILE"
fi

registrar_trigger() {
  local trigger="$1" nivel="$2"
  (
    flock -x 9
    local tmp
    tmp=$(mktemp)
    grep -v "^${trigger}|" "$CASTIGOS_DB" 2>/dev/null > "$tmp" || true
    echo "${trigger}|${nivel}|$(date +%s)" >> "$tmp"
    mv "$tmp" "$CASTIGOS_DB"
  ) 9>"$ETC_DIR/.lock.castigos"
}

ultimo_trigger() {
  local trigger="$1"
  grep "^${trigger}|" "$CASTIGOS_DB" 2>/dev/null | tail -1 | cut -d'|' -f3 || echo 0
}

puede_castigar() {
  local trigger="$1" cooldown="$2"
  local ultimo ahora
  ultimo=$(ultimo_trigger "$trigger")
  ahora=$(date +%s)
  (( ahora - ultimo >= cooldown ))
}

advertir() {
  local mensaje="$1"
  notify_user "$USUARIO" "⚠ ADVERTENCIA DEL GRAN HERMANO" "$mensaje"
}

castigar() {
  local nivel="$1" trigger="$2" motivo="$3" detalle="${4:-}" dur_n3="${5:-300}"
  registrar_trigger "$trigger" "$nivel"
  nohup "$BIN_DIR/castigos.sh" "nivel$nivel" "$USUARIO" "$motivo" "$detalle" "$dur_n3" \
    >/dev/null 2>&1 &
  disown
}

evaluar_tiempo_sesion() {
  local exceso
  exceso=$("$BIN_DIR/time_control.sh" exceso 2>/dev/null || echo 0)
  local estado
  estado=$("$BIN_DIR/time_control.sh" estado)

  [[ "$estado" == "DENTRO_DE_LIMITE" ]] && return 0

  if (( exceso < 10 )); then
    if puede_castigar tiempo_adv 600; then
      registrar_trigger tiempo_adv adv
      advertir "Has excedido tu tiempo permitido (${exceso} min de exceso). RETIRA AHORA o enfrenta las consecuencias."
    fi
  elif (( exceso < 20 )); then
    puede_castigar tiempo 900 && castigar 1 tiempo "exceso de ${exceso} min"
  elif (( exceso < 35 )); then
    puede_castigar tiempo 900 && castigar 2 tiempo "exceso de ${exceso} min"
  elif (( exceso < 50 )); then
    puede_castigar tiempo 1800 && castigar 3 tiempo "exceso de ${exceso} min" "" 900
  else
    puede_castigar tiempo 3600 && castigar 4 tiempo "exceso de ${exceso} min: el Partido se cansa de tu desviación"
  fi
}

evaluar_wine() {
  local seg
  seg=$("$BIN_DIR/time_control.sh" campo WINE 2>/dev/null || echo 0)
  local minutos=$(( seg / 60 ))

  if pgrep -u "$USUARIO" -f 'wine|wine64|\.exe' >/dev/null 2>&1; then
    "$BIN_DIR/time_control.sh" sumar WINE "$TICK"
    minutos=$(( (seg + TICK) / 60 ))
    if (( minutos >= 30 )); then
      puede_castigar wine 3600 && castigar 4 wine "software subversivo activo ${minutos} min"
    elif (( minutos >= 15 )); then
      puede_castigar wine 1800 && castigar 3 wine "software subversivo activo ${minutos} min" "" 600
    elif (( minutos >= 5 )); then
      puede_castigar wine 900 && castigar 2 wine "software subversivo activo ${minutos} min"
    elif puede_castigar wine_adv 600; then
      registrar_trigger wine_adv adv
      advertir "Software subversivo detectado (wine). El Partido lo registra."
    fi
  fi
}

visitas_youtube() {
  local desde="$1" hasta="$2" total=0
  local perfil db tmp count

  for perfil in /home/"$USUARIO"/.mozilla/firefox/*.default*; do
    [[ -d "$perfil" ]] || continue
    db="$perfil/places.sqlite"
    [[ -f "$db" ]] || continue
    tmp=$(mktemp)
    cp "$db" "$tmp" 2>/dev/null || { rm -f "$tmp"; continue; }
    count=$(sqlite3 "$tmp" \
      "SELECT COUNT(*) FROM moz_places WHERE last_visit_date >= $((desde * 1000000)) AND last_visit_date < $((hasta * 1000000)) AND (url LIKE '%youtube.com%' OR url LIKE '%youtu.be%');" 2>/dev/null || echo 0)
    total=$(( total + count ))
    rm -f "$tmp"
  done

  for perfil in /home/"$USUARIO"/.config/chromium /home/"$USUARIO"/.config/google-chrome; do
    db="$perfil/Default/History"
    [[ -f "$db" ]] || continue
    tmp=$(mktemp)
    cp "$db" "$tmp" 2>/dev/null || { rm -f "$tmp"; continue; }
    local desde_webkit=$(( (desde + 11644473600) * 1000000 ))
    local hasta_webkit=$(( (hasta + 11644473600) * 1000000 ))
    count=$(sqlite3 "$tmp" \
      "SELECT COUNT(*) FROM urls WHERE last_visit_time >= $desde_webkit AND last_visit_time < $hasta_webkit AND (url LIKE '%youtube.com%' OR url LIKE '%youtu.be%');" 2>/dev/null || echo 0)
    total=$(( total + count ))
    rm -f "$tmp"
  done

  echo "$total"
}

evaluar_youtube() {
  local desde hasta visitas
  desde=$(cat "$YOUTUBE_DESDE_FILE")
  hasta=$(date +%s)
  (( hasta - desde >= INTERVALO_YOUTUBE )) || return 0

  echo "$hasta" > "$YOUTUBE_DESDE_FILE"
  visitas=$(visitas_youtube "$desde" "$hasta")
  (( visitas > 0 )) || return 0

  "$BIN_DIR/time_control.sh" sumar YOUTUBE $(( visitas * PESO_YOUTUBE_SEG ))

  local seg minutos
  seg=$("$BIN_DIR/time_control.sh" campo YOUTUBE)
  minutos=$(( seg / 60 ))
  local limite_nivel
  limite_nivel=$(cfg YOUTUBE_LIMITE_MIN 30)

  if (( minutos > 60 )); then
    puede_castigar youtube 3600 && castigar 3 youtube "propaganda enemiga acumulada: ${minutos} min" "" 600
  elif (( minutos > 40 )); then
    puede_castigar youtube 1800 && castigar 2 youtube "propaganda enemiga acumulada: ${minutos} min"
  elif (( minutos > 30 )); then
    puede_castigar youtube 900 && castigar 1 youtube "propaganda enemiga acumulada: ${minutos} min"
  elif (( minutos >= 20 )) && puede_castigar youtube_adv 1200; then
    registrar_trigger youtube_adv adv
    advertir "Consumo de propaganda enemiga: ${minutos} min. El límite del Partido se aproxima."
  fi
}

clasificar_sudo() {
  local cmd="$1"
  if echo "$cmd" | grep -qE 'passwd|shadow|usermod|userdel|useradd'; then
    echo 4
  elif echo "$cmd" | grep -qE '(^|[;&| ])(su|bash|sh|zsh)([ ;&]|$)|sudo -i'; then
    echo 2
  elif echo "$cmd" | grep -qE 'systemctl (disable|stop|mask).*bigbrother'; then
    echo 3
  elif echo "$cmd" | grep -qE 'systemctl'; then
    echo 3
  elif echo "$cmd" | grep -qE '(-l|--list)$'; then
    echo 1
  else
    echo 0
  fi
}

evaluar_sudo() {
  local desde hasta
  desde=$(cat "$SUDO_DESDE_FILE")
  hasta=$(date +%s)
  (( hasta - desde >= INTERVALO_SUDO )) || return 0
  echo "$hasta" > "$SUDO_DESDE_FILE"

  local linea cmd nivel
  while IFS= read -r linea; do
    cmd=$(echo "$linea" | grep -oE 'COMMAND=.*$' | cut -d= -f2-)
    [[ -n "$cmd" ]] || continue
    log_evento "SUDO" "$cmd"
    nivel=$(clasificar_sudo "$cmd")
    case "$nivel" in
      1)
        puede_castigar sudo_adv 300 && {
          registrar_trigger sudo_adv adv
          advertir "Has sondeado los límites del Partido (sudo -l). Sospechoso."
        }
        ;;
      2) castigar 2 sudo "intento de rebelión: su/shell elevada" "sudo: $cmd" ;;
      3) castigar 3 sudo "manipulación del sistema detectada" "sudo: $cmd" "" 300 ;;
      4) castigar 4 sudo "herejía suprema: manipulación de identidades" "sudo: $cmd" ;;
    esac
  done < <(journalctl -q _COMM=sudo --since "@$desde" --no-pager 2>/dev/null | grep 'COMMAND=' || true)
}

vigilar() {
  if "$BIN_DIR/vaporizador.sh" verificar >/dev/null 2>&1; then
    sleep "$TICK"
    return 0
  fi

  if [[ "$(cat "$FECHA_FILE")" != "$(hoy)" ]]; then
    hoy > "$FECHA_FILE"
    "$BIN_DIR/time_control.sh" limpiar
    log_evento "RESET_DIARIO" "Nuevo día de vigilancia para $USUARIO"
  fi

  if ses=$(sesion_grafica "$USUARIO"); then
    "$BIN_DIR/time_control.sh" sumar SESION "$TICK"
  fi

  evaluar_tiempo_sesion || true
  evaluar_wine || true
  evaluar_youtube || true
  evaluar_sudo || true
}

log_evento "ARRANQUE_VIGILANCIA" "Vigilancia iniciada sobre $USUARIO"
notify_user "$USUARIO" "👁 GRAN HERMANO TE OBSERVA" \
  "La vigilancia ha comenzado, ciudadano $USUARIO. Tu obediencia es registrada." || true

while true; do
  vigilar || true
  sleep "$TICK"
done
