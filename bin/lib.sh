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
DB="$ETC_DIR/estado.db"
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

cfg_num() {
  local clave="$1" valor_def="$2" valor
  valor=$(cfg "$clave" "$valor_def")
  if [[ "$valor" =~ ^[0-9]+$ ]] && (( valor > 0 )); then
    echo "$valor"
  else
    echo "$valor_def"
  fi
}

cfg_flag() {
  local clave="$1" valor_def="$2" valor
  valor=$(cfg "$clave" "$valor_def")
  if [[ "$valor" == "0" || "$valor" == "1" ]]; then
    echo "$valor"
  else
    echo "$valor_def"
  fi
}

sql_esc() {
  printf '%s' "$1" | sed "s/'/''/g"
}

db() {
  sqlite3 -cmd ".bail on" -cmd ".timeout 5000" "$DB" "$1"
}

dbq() {
  sqlite3 -cmd ".bail on" -cmd ".timeout 5000" -separator '|' "$DB" "$1"
}

db_init() {
  mkdir -p "$ETC_DIR"
  sqlite3 -cmd ".bail on" "$DB" <<'SQL'
CREATE TABLE IF NOT EXISTS usuarios (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  usuario TEXT UNIQUE NOT NULL,
  nivel INTEGER NOT NULL DEFAULT 1,
  alta INTEGER NOT NULL,
  consentimiento TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS registros (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL,
  fecha TEXT NOT NULL,
  evento TEXT NOT NULL,
  detalle TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS tiempo (
  pk TEXT PRIMARY KEY,
  dia TEXT NOT NULL,
  segundos INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS triggers (
  trigger TEXT PRIMARY KEY,
  nivel TEXT NOT NULL,
  ts INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS exilio (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  inicio INTEGER NOT NULL,
  fin INTEGER NOT NULL,
  motivo TEXT NOT NULL,
  duracion TEXT NOT NULL DEFAULT '',
  etiqueta TEXT NOT NULL DEFAULT '',
  mult TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS salida (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tipo TEXT NOT NULL,
  ts INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_registros_fecha ON registros(fecha);
CREATE INDEX IF NOT EXISTS idx_exilio_fin ON exilio(fin);
CREATE INDEX IF NOT EXISTS idx_tiempo_dia ON tiempo(dia);
SQL
  chmod 640 "$DB" 2>/dev/null || true
}

asegurar_dirs() {
  mkdir -p "$RUN_DIR" "$LOGS_DIR/vigilancia" "$LOGS_DIR/castigos" "$LOGS_DIR/vaporizaciones" "$ASSETS_DIR/propaganda"
  touch "$FRASE_FILE" 2>/dev/null
  chmod 600 "$FRASE_FILE" 2>/dev/null || true
  db_init
}

migrar_legado() {
  [[ -f "$DB" ]] || return 0
  local total
  total=$(db "SELECT COUNT(*) FROM registros;")
  (( total > 0 )) && return 0

  local legacy_db="$ETC_DIR/registros.db"
  if [[ -f "$legacy_db" ]]; then
    while IFS='|' read -r ts fecha evento detalle; do
      db "INSERT INTO registros (ts,fecha,evento,detalle) VALUES ($ts,'$(sql_esc "$fecha")','$(sql_esc "$evento")','$(sql_esc "${detalle:-}")');"
    done < "$legacy_db"
  fi

  local f
  for f in "$ETC_DIR"/.tiempo.*; do
    [[ -f "$f" ]] || continue
    local dia campo seg
    dia="${f##*.}"
    while IFS= read -r linea; do
      campo="${linea%%=*}"
      seg="${linea#*=}"
      [[ "$campo" =~ ^[A-Z]+$ ]] || continue
      [[ "$seg" =~ ^[0-9]+$ ]] || continue
      db "INSERT OR REPLACE INTO tiempo (pk,dia,segundos) VALUES ('${campo}:${dia}','$(sql_esc "$dia")',$seg);"
    done < "$f"
  done

  if [[ -f "$ETC_DIR/castigos.db" ]]; then
    while IFS='|' read -r trig nivel ts; do
      db "INSERT OR REPLACE INTO triggers (trigger,nivel,ts) VALUES ('$(sql_esc "$trig")','$(sql_esc "$nivel")',$ts);"
    done < "$ETC_DIR/castigos.db"
  fi

  if [[ -f "$ETC_DIR/exilio.db" ]]; then
    while IFS='|' read -r ini fin motivo dur etiq mult; do
      db "INSERT INTO exilio (inicio,fin,motivo,duracion,etiqueta,mult) VALUES ($ini,$fin,'$(sql_esc "$motivo")','$(sql_esc "$dur")','$(sql_esc "$etiq")','$(sql_esc "$mult")');"
    done < "$ETC_DIR/exilio.db"
  fi

  if [[ -f "$ETC_DIR/salida.db" ]]; then
    while IFS='|' read -r tipo ts; do
      db "INSERT INTO salida (tipo,ts) VALUES ('$(sql_esc "$tipo")',$ts);"
    done < "$ETC_DIR/salida.db"
  fi

  if [[ -f "$ETC_DIR/usuarios.db" ]]; then
    while IFS='|' read -r usr nivel alta consent; do
      [[ -n "$usr" ]] || continue
      db "INSERT OR IGNORE INTO usuarios (usuario,nivel,alta,consentimiento) VALUES ('$(sql_esc "$usr")',$nivel,$alta,'$(sql_esc "$consent")');"
    done < "$ETC_DIR/usuarios.db"
  fi
}

usuario_vigilado() {
  local u
  u=$(cfg USUARIO_VIGILADO "")
  [[ -n "$u" ]] || u=$(dbq "SELECT usuario FROM usuarios ORDER BY id LIMIT 1;" 2>/dev/null | head -1)
  echo "$u"
}

hoy() {
  date +%Y-%m-%d
}

validar_config() {
  local claves=(LIMITE_DIARIO_MIN TIEMPO_EXTRA_MIN PESO_YOUTUBE_SEG REFLEXION_HORAS \
    PROPAGANDA_INTERVALO_MIN EXILIO_MULT EXILIO_MAX_H \
    TIEMPO_ADV_MIN TIEMPO_N1_MIN TIEMPO_N2_MIN TIEMPO_N3_MIN \
    WINE_ADV_MIN WINE_N2_MIN WINE_N3_MIN WINE_N4_MIN \
    YOUTUBE_ADV_MIN YOUTUBE_N1_MIN YOUTUBE_N2_MIN YOUTUBE_N3_MIN \
    COOLDOWN_ADV_S COOLDOWN_N1_S COOLDOWN_N2_S COOLDOWN_N3_S COOLDOWN_N4_S \
    TIEMPO_N3_DUR_S WINE_N3_DUR_S YOUTUBE_N3_DUR_S SUDO_N3_DUR_S)
  local clave defs valor
  declare -A defs=(
    [LIMITE_DIARIO_MIN]=180 [TIEMPO_EXTRA_MIN]=60 [PESO_YOUTUBE_SEG]=90
    [REFLEXION_HORAS]=24 [PROPAGANDA_INTERVALO_MIN]=5
    [EXILIO_MULT]=150 [EXILIO_MAX_H]=96
    [TIEMPO_ADV_MIN]=3 [TIEMPO_N1_MIN]=6 [TIEMPO_N2_MIN]=12 [TIEMPO_N3_MIN]=18
    [WINE_ADV_MIN]=1 [WINE_N2_MIN]=2 [WINE_N3_MIN]=5 [WINE_N4_MIN]=9
    [YOUTUBE_ADV_MIN]=6 [YOUTUBE_N1_MIN]=10 [YOUTUBE_N2_MIN]=14 [YOUTUBE_N3_MIN]=20
    [COOLDOWN_ADV_S]=180 [COOLDOWN_N1_S]=240 [COOLDOWN_N2_S]=360 [COOLDOWN_N3_S]=600 [COOLDOWN_N4_S]=3600
    [TIEMPO_N3_DUR_S]=1800 [WINE_N3_DUR_S]=1200 [YOUTUBE_N3_DUR_S]=1200 [SUDO_N3_DUR_S]=900
  )
  for clave in "${claves[@]}"; do
    valor=$(cfg "$clave" "${defs[$clave]}")
    if [[ ! "$valor" =~ ^[0-9]+$ ]] || (( valor <= 0 )); then
      log_evento "CORRECCION_CONFIG" "$clave inválida ('${valor}'), restaurado ${defs[$clave]}"
      touch "$ETC_DIR/config.conf"
      if grep -q "^${clave}=" "$CONFIG" 2>/dev/null; then
        sed -i "s|^${clave}=.*|${clave}=${defs[$clave]}|" "$CONFIG"
      else
        echo "${clave}=${defs[$clave]}" >> "$CONFIG"
      fi
    fi
  done
  valor=$(cfg VAPORIZACION_HABILITADA 1)
  if [[ "$valor" != "0" && "$valor" != "1" ]]; then
    log_evento "CORRECCION_CONFIG" "VAPORIZACION_HABILITADA inválida ('${valor}'), restaurado 1"
    sed -i "s|^VAPORIZACION_HABILITADA=.*|VAPORIZACION_HABILITADA=1|" "$CONFIG" 2>/dev/null || echo "VAPORIZACION_HABILITADA=1" >> "$CONFIG"
  fi
}

log_evento() {
  local evento="$1" detalle="${2:-}"
  local ts fecha
  ts=$(date +%s)
  fecha=$(hoy)
  db "INSERT INTO registros (ts,fecha,evento,detalle) VALUES ($ts,'$(sql_esc "$fecha")','$(sql_esc "$evento")','$(sql_esc "$detalle")');"
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

env_de_pid() {
  local pid="$1" clave="$2"
  tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep "^${clave}=" | head -1 | cut -d= -f2-
}

lider_sesion() {
  local usuario="$1" ses_id lider
  ses_id=$(sesion_grafica "$usuario") || return 1
  lider=$(loginctl show-session "$ses_id" -p Leader --value 2>/dev/null || true)
  [[ -n "$lider" && "$lider" =~ ^[0-9]+$ ]] && echo "$lider" && return 0
  return 1
}

user_env() {
  local usuario="$1" clave="$2" pid val
  if pid=$(lider_sesion "$usuario"); then
    val=$(env_de_pid "$pid" "$clave")
    [[ -n "$val" ]] && { echo "$val"; return 0; }
  fi
  for pid in $(pgrep -u "$usuario" 2>/dev/null); do
    val=$(env_de_pid "$pid" "$clave")
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
  local display xauth wayland xdg_runtime
  if display=$(user_env "$usuario" DISPLAY) && [[ -n "$display" ]]; then
    xauth=$(user_env "$usuario" XAUTHORITY || echo "/home/$usuario/.Xauthority")
    env DISPLAY="$display" XAUTHORITY="$xauth" runuser -u "$usuario" -- "$@" 2>/dev/null \
      || env DISPLAY="$display" XAUTHORITY="$xauth" sudo -u "$usuario" -- "$@" 2>/dev/null
  elif wayland=$(user_env "$usuario" WAYLAND_DISPLAY) && [[ -n "$wayland" ]]; then
    xdg_runtime=$(user_env "$usuario" XDG_RUNTIME_DIR || echo "/run/user/$(id -u "$usuario")")
    env WAYLAND_DISPLAY="$wayland" XDG_RUNTIME_DIR="$xdg_runtime" runuser -u "$usuario" -- "$@" 2>/dev/null \
      || env WAYLAND_DISPLAY="$wayland" XDG_RUNTIME_DIR="$xdg_runtime" sudo -u "$usuario" -- "$@" 2>/dev/null
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
  local ahora fin total
  ahora=$(date +%s)
  total=$(db "SELECT COUNT(*) FROM exilio;" 2>/dev/null || echo 0)
  (( total > 0 )) || return 1
  fin=$(dbq "SELECT fin FROM exilio ORDER BY id DESC LIMIT 1;" 2>/dev/null)
  [[ -n "$fin" && "$fin" =~ ^[0-9]+$ ]] || return 1
  (( ahora < fin )) && return 0
  return 1
}

exilio_fin() {
  dbq "SELECT fin FROM exilio ORDER BY id DESC LIMIT 1;" 2>/dev/null
}