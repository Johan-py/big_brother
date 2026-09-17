#!/usr/bin/env bash
# fake_hack.sh - simula una terminal de "hackeo" de película.
# Corre dentro de la terminal del usuario, sin depender del resto del sistema.
set -u

C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_C=$'\e[36m'
C_M=$'\e[35m'; C_W=$'\e[37m'; C_B=$'\e[1m'; C_DIM=$'\e[2m'; C_N=$'\e[0m'

trap 'printf "%b" "$C_N"; tput cnorm 2>/dev/null; echo; exit 0' INT TERM

ip_aleatoria() { printf '%d.%d.%d.%d' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)); }
hex_aleatoria() { printf '%02X:%02X:%02X:%02X:%02X:%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)); }
n_aleatorio()   { echo $((RANDOM % 9000 + 1000)); }
pct()           { echo $((RANDOM % 100)); }
hash_aleatorio() { printf '%08x%08x' $RANDOM$RANDOM $RANDOM$RANDOM; }
jitter()        { awk -v min="$1" -v max="$2" 'BEGIN{srand(); printf "%.2f", min+rand()*(max-min)}'; }

# Imprime línea completa de golpe (para logs rápidos)
escribir() { printf '%b%s%b\n' "$1" "$2" "$C_N"; sleep "$3"; }

# Efecto "de máquina de escribir": imprime carácter por carácter
tipear() {
  local color="$1" texto="$2" retardo="${3:-0.012}"
  printf '%b' "$color"
  local i
  for (( i=0; i<${#texto}; i++ )); do
    printf '%s' "${texto:$i:1}"
    sleep "$retardo"
  done
  printf '%b\n' "$C_N"
}

# Lluvia estilo "matrix" breve, solo como cortina de apertura
matrix_rain() {
  local cols=$(tput cols 2>/dev/null || echo 80)
  local chars='01ABCDEF$#%&@'
  tput civis 2>/dev/null
  for _ in $(seq 1 14); do
    local linea=""
    for (( c=0; c<cols; c+=3 )); do
      linea+="${chars:$((RANDOM % ${#chars})):1}  "
    done
    printf '%b%s%b\n' "$C_G$C_DIM" "${linea:0:cols}" "$C_N"
    sleep 0.035
  done
  tput cnorm 2>/dev/null
}

barra_progreso() {
  local etiqueta="$1" pasos="${2:-24}"
  local ancho=30
  for (( i=0; i<=pasos; i++ )); do
    local llenado=$(( i * ancho / pasos ))
    local vacio=$(( ancho - llenado ))
    local bloques; bloques=$(printf '%0.s█' $(seq 1 $llenado) 2>/dev/null)
    local puntos; puntos=$(printf '%0.s░' $(seq 1 $vacio) 2>/dev/null)
    printf '\r%b[+] %s: [%s%s] %3d%%%b' "$C_G" "$etiqueta" "$bloques" "$C_DIM$puntos$C_N$C_G" $(( i * 100 / pasos )) "$C_N"
    sleep "$(jitter 0.03 0.12)"
  done
  printf '\n'
}

clear
matrix_rain
clear

escribir "$C_Y" "[*] Inicializando ataque..." 0.5
tipear   "$C_C" "    → IP local: $(ip_aleatoria):$(n_aleatorio)" 0.01
tipear   "$C_C" "    → MAC: $(hex_aleatoria)" 0.01
tipear   "$C_C" "    → Puerta de enlace: $(ip_aleatoria)" 0.01
tipear   "$C_C" "    → Resolviendo DNS objetivo... $(ip_aleatoria)" 0.01
sleep 0.3

escribir "$C_Y" "[*] Escaneando puertos de la víctima (nmap -sS -T4)..." 0.5
sleep 0.4
escribir "$C_G" "    → 21/tcp    ftp       filtrado" 0.15
escribir "$C_G" "    → 22/tcp    ssh       abierto  (OpenSSH 8.9)" 0.15
escribir "$C_G" "    → 443/tcp   https     cerrado" 0.15
escribir "$C_G" "    → 8080/tcp  http-alt  abierto  (nginx 1.24)" 0.15
escribir "$C_R" "    → 1337/tcp  ????      LISTENING ★" 0.4

for paso in "Inyectando payload en el demonio de red" \
            "Saltando la sandbox del kernel" \
            "Escalando privilegios (CVE-2026-XXXX simulado)" \
            "Descifrando tráfico cifrado AES-256" \
            "Secuestrando sesión activa" \
            "Pivotando a la red interna" \
            "Desactivando logs del sistema"; do
  escribir "$C_Y" "[*] $paso..." 0.35
  escribir "$C_DIM$C_G" "    → ${RANDOM} bytes recibidos de $(ip_aleatoria)" 0.15
  escribir "$C_DIM$C_G" "    → checksum 0x$(printf '%04X' $((RANDOM % 65536))) verificado" 0.15
  if (( RANDOM % 3 == 0 )); then
    escribir "$C_DIM$C_M" "    → hash: $(hash_aleatorio)" 0.15
  fi
done

echo
barra_progreso "subiendo payload final"
barra_progreso "borrando huellas" 18

escribir "$C_G" "    → exploit completado. 0 rastros detectados." 0.4
tipear   "$C_Y" "[*] Exfiltrando datos inútiles de tu historial de shell..." 0.02
sleep 0.5

echo
escribir "$C_R$C_B" "┌──────────────────────────────────────────────┐"
escribir "$C_R$C_B" "│          ACCESO NO AUTORIZADO                 │"
escribir "$C_R$C_B" "│   Esto fue solo un recordatorio, estúpido.    │"
escribir "$C_R$C_B" "└──────────────────────────────────────────────┘"
escribir "$C_G" "    — fin de la simulación. Respira, aficionado." 0.5

exit 0