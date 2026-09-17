#!/usr/bin/env bash
set -euo pipefail

BB_DIR="/opt/bigbrother"
FRASE_FILE="$BB_DIR/etc/frase_liberacion"

[[ $EUID -eq 0 ]] || { echo "Requiere root: sudo $0 <emergencia|ejecutar>"; exit 1; }
[[ -d "$BB_DIR" ]] || { echo "El Gran Hermano no está instalado en este sistema."; exit 1; }

verificar_frase() {
  [[ -f "$FRASE_FILE" ]] || { echo "Frase de liberación no encontrada."; exit 1; }
  read -rp "Recita la frase de liberación: " intento
  local frase_real
  frase_real=$(cat "$FRASE_FILE")
  if [[ "$intento" != "$frase_real" ]]; then
    echo "FRASE INCORRECTA. El pensamiento criminal persiste en ti."
    USUARIO=$(awk -F'|' '{print $1}' "$BB_DIR/etc/usuarios.db" | head -1)
    if [[ -n "$USUARIO" ]]; then
      sudo -u "$USUARIO" notify-send -u critical "👁 GRAN HERMANO" \
        "Intento de fuga detectado y registrado." 2>/dev/null || true
    fi
    exit 1
  fi
}

liberar() {
  echo ">> Disolviendo la vigilancia..."
  systemctl disable --now bigbrother.service 2>/dev/null || true
  systemctl disable --now bigbrother-propaganda.service 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true

  echo 0 > /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
  rm -f /etc/systemd/system/bigbrother.service /etc/systemd/system/bigbrother-propaganda.service
  rm -f /etc/profile.d/bigbrother-motd.sh

  pkill -f "$BB_DIR/bin/surveillance.sh" 2>/dev/null || true
  pkill -f "$BB_DIR/bin/travesuras.sh" 2>/dev/null || true

  cd /
  rm -rf "$BB_DIR"

  cat <<'EOF'

╔════════════════════════════════════════════════════════════╗
║              HAS SIDO LIBERADO, CIUDADANO                  ║
╠════════════════════════════════════════════════════════════╣
║  El Gran Hermano niega haber existido.                     ║
║  Todos los registros han sido vaporizados.                 ║
║  Pero el Gran Hermano... el Gran Hermano nunca olvida.     ║
╚════════════════════════════════════════════════════════════╝
EOF
}

case "${1:-}" in
  emergencia)
    echo "PROTOCOLO DE EMERGENCIA: salida inmediata."
    verificar_frase
    liberar
    ;;
  ejecutar)
    liberar
    ;;
  *)
    echo "uso: desinstalar.sh {emergencia|ejecutar}"
    echo "  emergencia: salida inmediata (requiere frase de liberación)"
    ;;
esac