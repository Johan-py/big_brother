#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TICK=30
INTERVALO_YOUTUBE=300
INTERVALO_SUDO=60

USUARIO=$(usuario_vigilado)
[[ -n "$USUARIO" ]] || { echo "No hay ciudadano registrado"; exit 1; }

asegurar_dirs
migrar_legado
validar_config

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

nivel_max() {
  if [[ "$(cfg_flag VAPORIZACION_HABILITADA 1)" == "1" ]]; then
    echo 4
  else
    echo 3
  fi
}

registrar_trigger() {
  local trigger="$1" nivel="$2"
  db "INSERT INTO triggers (trigger,nivel,ts) VALUES ('$(sql_esc "$trigger")','$(sql_esc "$nivel")',$(date +%s))
      ON CONFLICT(trigger) DO UPDATE SET nivel=excluded.nivel, ts=excluded.ts;" 2>/dev/null || true
}

ultimo_trigger() {
  dbq "SELECT IFNULL((SELECT ts FROM triggers WHERE trigger='$(sql_esc "$1")'),0);" 2>/dev/null || echo 0
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
  local nivel="$1" trigger="$2" motivo="$3" detalle="${4:-}" dur_n3="${5:-300}" max
  max=$(nivel_max)
  (( nivel > max )) && nivel=$max
  registrar_trigger "$trigger" "$nivel"
  nohup "$BIN_DIR/castigos.sh" "nivel$nivel" "$USUARIO" "$motivo" "$detalle" "$dur_n3" \
    >/dev/null 2>&1 &
  disown
}

evaluar_tiempo_sesion() {
  local exceso estado adv n1 n2 n3
  exceso=$("$BIN_DIR/time_control.sh" exceso 2>/dev/null || echo 0)
  estado=$("$BIN_DIR/time_control.sh" estado)

  [[ "$estado" == "DENTRO_DE_LIMITE" ]] && return 0

  adv=$(cfg_num TIEMPO_ADV_MIN 3)
  n1=$(cfg_num TIEMPO_N1_MIN 6)
  n2=$(cfg_num TIEMPO_N2_MIN 12)
  n3=$(cfg_num TIEMPO_N3_MIN 18)

  if (( exceso < adv )); then
    if puede_castigar tiempo_adv "$(cfg_num COOLDOWN_ADV_S 180)"; then
      registrar_trigger tiempo_adv adv
      advertir "Has excedido tu tiempo permitido (${exceso} min de exceso). RETIRA AHORA o enfrenta las consecuencias."
    fi
  elif (( exceso < n1 )); then
    puede_castigar tiempo "$(cfg_num COOLDOWN_N1_S 240)" && castigar 1 tiempo "exceso de ${exceso} min"
  elif (( exceso < n2 )); then
    puede_castigar tiempo "$(cfg_num COOLDOWN_N2_S 360)" && castigar 2 tiempo "exceso de ${exceso} min"
  elif (( exceso < n3 )); then
    puede_castigar tiempo "$(cfg_num COOLDOWN_N3_S 600)" && castigar 3 tiempo "exceso de ${exceso} min" "" "$(cfg_num TIEMPO_N3_DUR_S 1800)"
  else
    puede_castigar tiempo "$(cfg_num COOLDOWN_N4_S 3600)" && castigar 4 tiempo "exceso de ${exceso} min: el Partido se cansa de tu desviación"
  fi
}

evaluar_wine() {
  local seg minutos adv n2 n3 n4
  seg=$("$BIN_DIR/time_control.sh" campo WINE 2>/dev/null || echo 0)
  minutos=$(( seg / 60 ))

  adv=$(cfg_num WINE_ADV_MIN 1)
  n2=$(cfg_num WINE_N2_MIN 2)
  n3=$(cfg_num WINE_N3_MIN 5)
  n4=$(cfg_num WINE_N4_MIN 9)

  if pgrep -u "$USUARIO" -f 'wine|wine64|\.exe' >/dev/null 2>&1; then
    "$BIN_DIR/time_control.sh" sumar WINE "$TICK"
    minutos=$(( (seg + TICK) / 60 ))
    if (( minutos >= n4 )); then
      puede_castigar wine "$(cfg_num COOLDOWN_N4_S 3600)" && castigar 4 wine "software subversivo activo ${minutos} min"
    elif (( minutos >= n3 )); then
      puede_castigar wine "$(cfg_num COOLDOWN_N3_S 600)" && castigar 3 wine "software subversivo activo ${minutos} min" "" "$(cfg_num WINE_N3_DUR_S 1200)"
    elif (( minutos >= n2 )); then
      puede_castigar wine "$(cfg_num COOLDOWN_N2_S 360)" && castigar 2 wine "software subversivo activo ${minutos} min"
    elif puede_castigar wine_adv "$(cfg_num COOLDOWN_ADV_S 180)"; then
      registrar_trigger wine_adv adv
      advertir "Software subversivo detectado (wine). El Partido lo registra."
    fi
  fi
}

visitas_youtube() {
  local desde="$1" hasta="$2" total=0
  local perfil db tmp count

  for perfil in /home/"$USUARIO"/.mozilla/firefox/*; do
    [[ -d "$perfil" ]] || continue
    db="$perfil/places.sqlite"
    [[ -f "$db" ]] || continue
    tmp=$(mktemp)
    cp "$db" "$tmp" 2>/dev/null || { rm -f "$tmp"; continue; }
    count=$(sqlite3 "$tmp" \
      "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits v JOIN moz_places p ON p.id=v.place_id WHERE v.visit_date >= $((desde * 1000000)) AND v.visit_date < $((hasta * 1000000)) AND (p.url LIKE '%youtube.com%' OR p.url LIKE '%youtu.be%');" 2>/dev/null || echo 0)
    total=$(( total + count ))
    rm -f "$tmp"
  done

  local navegador
  for navegador in chromium google-chrome microsoft-edge brave-browser vivaldi; do
    perfil="/home/$USUARIO/.config/$navegador"
    db="$perfil/Default/History"
    [[ -f "$db" ]] || continue
    tmp=$(mktemp)
    cp "$db" "$tmp" 2>/dev/null || { rm -f "$tmp"; continue; }
    local desde_webkit=$(( (desde + 11644473600) * 1000000 ))
    local hasta_webkit=$(( (hasta + 11644473600) * 1000000 ))
    count=$(sqlite3 "$tmp" \
      "SELECT COUNT(DISTINCT url) FROM urls WHERE last_visit_time >= $desde_webkit AND last_visit_time < $hasta_webkit AND (url LIKE '%youtube.com%' OR url LIKE '%youtu.be%');" 2>/dev/null || echo 0)
    total=$(( total + count ))
    rm -f "$tmp"
  done

  echo "$total"
}

evaluar_youtube() {
  local desde hasta visitas seg minutos adv n1 n2 n3
  desde=$(cat "$YOUTUBE_DESDE_FILE")
  hasta=$(date +%s)
  (( hasta - desde >= INTERVALO_YOUTUBE )) || return 0

  echo "$hasta" > "$YOUTUBE_DESDE_FILE"
  visitas=$(visitas_youtube "$desde" "$hasta")
  (( visitas > 0 )) || return 0

  "$BIN_DIR/time_control.sh" sumar YOUTUBE $(( visitas * $(cfg_num PESO_YOUTUBE_SEG 90) ))

  seg=$("$BIN_DIR/time_control.sh" campo YOUTUBE)
  minutos=$(( seg / 60 ))
  adv=$(cfg_num YOUTUBE_ADV_MIN 6)
  n1=$(cfg_num YOUTUBE_N1_MIN 10)
  n2=$(cfg_num YOUTUBE_N2_MIN 14)
  n3=$(cfg_num YOUTUBE_N3_MIN 20)

  if (( minutos > n3 )); then
    puede_castigar youtube "$(cfg_num COOLDOWN_N3_S 600)" && castigar 3 youtube "propaganda enemiga acumulada: ${minutos} min" "" "$(cfg_num YOUTUBE_N3_DUR_S 1200)"
  elif (( minutos > n2 )); then
    puede_castigar youtube "$(cfg_num COOLDOWN_N2_S 360)" && castigar 2 youtube "propaganda enemiga acumulada: ${minutos} min"
  elif (( minutos > n1 )); then
    puede_castigar youtube "$(cfg_num COOLDOWN_N1_S 240)" && castigar 1 youtube "propaganda enemiga acumulada: ${minutos} min"
  elif (( minutos >= adv )) && puede_castigar youtube_adv "$(cfg_num COOLDOWN_ADV_S 180)"; then
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
        puede_castigar sudo_adv "$(cfg_num COOLDOWN_ADV_S 180)" && {
          registrar_trigger sudo_adv adv
          advertir "Has sondeado los límites del Partido (sudo -l). Sospechoso."
        }
        ;;
      2) castigar 2 sudo "intento de rebelión: su/shell elevada" "sudo: $cmd" ;;
      3) castigar 3 sudo "manipulación del sistema detectada" "sudo: $cmd" "" "$(cfg_num SUDO_N3_DUR_S 900)" ;;
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

# El saludo se reintenta sin bloquear la vigilancia: apenas exista sesión.
(
  for _ in $(seq 1 60); do
    if sesion_grafica "$USUARIO" >/dev/null 2>&1; then
      notify_user "$USUARIO" "👁 GRAN HERMANO TE OBSERVA" \
        "La vigilancia ha comenzado, ciudadano $USUARIO. Tu obediencia es registrada." || true
      break
    fi
    sleep 5
  done
) &
disown

while true; do
  vigilar || true
  sleep "$TICK"
done