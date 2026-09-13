#!/usr/bin/env bash
set -euo pipefail

BB_DIR="/opt/bigbrother"
BIN_LINK="/usr/local/bin/bigbrother"
FRASE_FILE="$BB_DIR/etc/frase_liberacion"

[[ $EUID -eq 0 ]] || { echo "Requiere root: sudo $0 <emergencia|ejecutar>"; exit 1; }
[[ -d "$BB_DIR" ]] || { echo "El Gran Hermano no está instalado en este sistema."; exit 1; }

source "$BB_DIR/bin/lib.sh"

verificar_frase() {
  [[ -f "$FRASE_FILE" ]] || { echo "Frase de liberación no encontrada."; exit 1; }
  read -rp "Recita la frase de liberación: " intento
  local frase_real
  frase_real=$(cat "$FRASE_FILE")
  if [[ "$intento" != "$frase_real" ]]; then
    echo "FRASE INCORRECTA. El pensamiento criminal persiste en ti."
    echo "Tienes 3 segundos para reflexionar antes del siguiente castigo."
    sleep 3
    USUARIO=$(usuario_vigilado)
    if [[ -n "$USUARIO" ]]; then
      notify_user "$USUARIO" "👁 GRAN HERMANO" \
        "Intento de fuga detectado y registrado." || true
    fi
    exit 1
  fi
}

liberar() {
  local USUARIO
  USUARIO=$(usuario_vigilado)

  echo ">> Disolviendo la vigilancia..."
  systemctl disable --now bigbrother.service bigbrother-propaganda.service 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true

  echo 0 > /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true

  if [[ -f "$BB_DIR/etc/issue.original" ]]; then
    cp "$BB_DIR/etc/issue.original" /etc/issue 2>/dev/null || true
  fi

  rm -f /etc/profile.d/bigbrother-motd.sh
  rm -f "$BIN_LINK"
  rm -f /etc/systemd/system/bigbrother.service /etc/systemd/system/bigbrother-propaganda.service

  if [[ -n "$USUARIO" ]]; then
    pkill -u "$USUARIO" -f "feh -F" 2>/dev/null || true
    pkill -u "$USUARIO" -f 'swayimg' 2>/dev/null || true
    pkill -u "$USUARIO" -f 'imv' 2>/dev/null || true
  fi

  cd /
  rm -rf "$BB_DIR"

  cat <<'EOF'

╔════════════════════════════════════════════════════════════╗
║              HAS SIDO LIBERADO, CIUDADANO                  ║
╠════════════════════════════════════════════════════════════╣
║  El Partido niega haber existido.                          ║
║  Todos los registros han sido vaporizados.                 ║
║  Pero el Gran Hermano... el Gran Hermano nunca olvida.     ║
╚════════════════════════════════════════════════════════════╝
EOF
}

case "${1:-}" in
  emergencia)
    echo "PROTOCOLO DE EMERGENCIA: salida inmediata sin período de reflexión."
    verificar_frase
    liberar
    ;;
  ejecutar)
    liberar
    ;;
  *)
    echo "uso: desinstalar.sh {emergencia|ejecutar}"
    echo "  emergencia: salida inmediata (requiere frase de liberación)"
    echo "  ejecutar:   usado internamente tras el período de arrepentimiento"
    ;;
esac