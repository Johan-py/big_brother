#!/usr/bin/env bash
# fake_hack.sh - simula una terminal de "hackeo" de película.
# Corre dentro de la terminal del usuario, sin depender del resto del sistema.
set -u

C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_C=$'\e[36m'
C_W=$'\e[37m'; C_B=$'\e[1m'; C_N=$'\e[0m'

ip_aleatoria() { printf '%d.%d.%d.%d' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)); }
hex_aleatoria() { printf '%02X:%02X:%02X:%02X:%02X:%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)); }
n_aleatorio()   { echo $((RANDOM % 9000 + 1000)); }
pct()           { echo $((RANDOM % 100)); }

escribir() { printf '%b%s%b\n' "$1" "$2" "$C_N"; sleep "$3"; }

clear

escribir "$C_Y" "[*] Inicializando ataque...        " 0.8
escribir "$C_C" "    → IP local: $(ip_aleatoria):$(n_aleatorio)" 0.4
escribir "$C_C" "    → MAC: $(hex_aleatoria)" 0.4
escribir "$C_C" "    → Puerta de enlace: $(ip_aleatoria)" 0.4
escribir "$C_Y" "[*] Escaneando puertos de la víctima..." 0.6
escribir "$C_G" "    → puerto 22:  sshtunel abierto" 0.3
escribir "$C_G" "    → puerto 443: bloqueado           " 0.3
escribir "$C_G" "    → puerto 8080: redirección http  " 0.3
escribir "$C_G" "    → puerto 1337: LISTENING ★       " 0.3

for paso in "Inyectando payload en el demonio de red" \
            "Saltando la sandbox del kernel" \
            "Enumerando procesos de la CIA" \
            "Descifrando tráfico cifrado AES-256" \
            "Secuestrando conexión VPN" \
            "Accediendo al mainframe de vuelo" \
            "Desactivando anti-virus del sistema"; do
  escribir "$C_Y" "[*] $paso..." 0.5
  escribir "$C_G" "    → ${RANDOM} bytes recibidos de $(ip_aleatoria)" 0.2
  escribir "$C_G" "    → validando chksum 0x$(printf '%04X' $((RANDOM % 65536)))" 0.2
done

escribir "$C_Y" "[*] Subiendo carga útil final..." 0.6
for _ in {1..10}; do
  printf '\r%s[+] progreso: %s%s%%  ' "$C_G" "$C_B" "$(pct)"
  sleep 0.18
done
printf '\r%s[+] progreso: %s100%%   %s\n' "$C_G" "$C_B" "$C_N"
sleep 0.4

escribir "$C_G" "    → exploit completado. Cero rastros." 0.4
escribir "$C_Y" "[*] Exfiltrando datos inútiles de tu historial..." 1.0

escribir "$C_R" "${C_B}┌──────────────────────────────────────────────┐"
escribir "$C_R" "${C_B}│  ACCESO NO AUTORIZADO                          │"
escribir "$C_R" "${C_B}│  Esto fue solo un recordatorio, estúpido.      │"
escribir "$C_R" "${C_B}└──────────────────────────────────────────────┘"
escribir "$C_G" "    — fin de la simulación. Respira, aficionado." 0.5

sleep 20
exit 0