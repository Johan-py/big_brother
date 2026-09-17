#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_DIR="/opt/bigbrother"

[[ $EUID -eq 0 ]] || { echo "El instalador requiere root: sudo ./instalar.sh"; exit 1; }

cat <<'EOF'
╔════════════════════════════════════════════════════════════╗
║           GRAN HERMANO — CONSENTIMIENTO INFORMADO           ║
╚════════════════════════════════════════════════════════════╝

QUÉ HARÁ ESTE SISTEMA:
  1. Mide el tiempo de uso de tu sesión gráfica.
  2. Cada hora de uso:
     a) Envía una notificación escrita por IA (voz de Gilfoyle).
     b) A los 10 s abre una terminal donde la IA te advierte
        que deberías estar haciendo algo más productivo.
     c) A los 5 min ejecuta UNA travesura aleatoria:
        1) Apagar el computador.
        2) Reproducir una música aleatoria.
        3) Ejecutar un "hackeo" simulado a lo película.
  3. Si no hay clave de IA, los mensajes usan un catálogo local.

LÍMITES ÉTICOS:
  - Solo vigila la cuenta que consienta.
  - NO toca BIOS/UEFI/GRUB ni resiste su desinstalación.
  - Salida siempre disponible (ver abajo).

PROTOCOLO DE SALIDA (siempre disponible):
  Emergencia:  sudo /opt/bigbrother/desinstalar.sh emergencia
               → requiere tu frase de liberación (se genera
               al final de esta instalación; guárdala).
               También puedes leerla con:
               sudo cat /opt/bigbrother/etc/frase_liberacion

EOF

read -rp "Ciudadano a vigilar [$SUDO_USER]: " USUARIO_OBJETIVO
USUARIO_OBJETIVO=${USUARIO_OBJETIVO:-$SUDO_USER}
if ! id "$USUARIO_OBJETIVO" &>/dev/null; then
  echo "Ese ciudadano no existe en el sistema."
  exit 1
fi

echo
read -rp "Escribe 'ACEPTO' para continuar: " consentimiento
[[ "$consentimiento" == "ACEPTO" ]] || {
  echo "El Gran Hermano rechaza ciudadanos indecisos. Instalación cancelada."
  exit 1
}

FRASE=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20 || true)

echo ">> Estableciendo cuartel general en $BB_DIR"
rm -rf "$BB_DIR"
mkdir -p "$BB_DIR"/{bin,etc}
cp "$REPO_DIR"/bin/*.sh "$BB_DIR/bin/"
chmod 755 "$BB_DIR"/bin/*.sh
cp "$REPO_DIR"/bin/gilfoyle.py "$BB_DIR/bin/"
chmod 750 "$BB_DIR/bin/gilfoyle.py"

touch "$BB_DIR/etc"/{registros.db,tiempo.db}
echo "$USUARIO_OBJETIVO|$(date +%s)|consentimiento_expreso" > "$BB_DIR/etc/usuarios.db"

echo ">> Configurando clave de IA"
KEY=""
if [[ -f "$REPO_DIR/non_ia_tool/.env" ]]; then
  KEY=$(grep '^OPENROUTER_API_KEY=' "$REPO_DIR/non_ia_tool/.env" | tail -1 | cut -d= -f2- | tr -d '\r"' || true)
fi
if [[ -z "$KEY" ]]; then
  read -rp "OPENROUTER_API_KEY (opcional, para mensajes de IA): " KEY
fi
if [[ -n "$KEY" ]]; then
  echo "OPENROUTER_API_KEY=$KEY" > "$BB_DIR/etc/.env"
  chmod 600 "$BB_DIR/etc/.env"
  echo "   Clave guardada en $BB_DIR/etc/.env"
else
  echo "   Sin clave: se usarán mensajes locales (Gilfoyle offline)."
fi

cat > "$BB_DIR/etc/config.conf" <<EOF
USUARIO_VIGILADO=$USUARIO_OBJETIVO
INTERVALO_HORAS=1
MUSICA_DIR=/home/$USUARIO_OBJETIVO/Music
MODELO=deepseek/deepseek-chat
EOF
chmod 640 "$BB_DIR/etc/config.conf"
echo "$FRASE" > "$BB_DIR/etc/frase_liberacion"
chmod 600 "$BB_DIR/etc/frase_liberacion"
chown -R root:root "$BB_DIR"

echo ">> Instalando el servicio del Gran Hermano"
cp "$REPO_DIR/systemd/bigbrother.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now bigbrother.service

echo "$(date +%s)|$(date +%Y-%m-%d)|CONSENTIMIENTO|usuario=$USUARIO_OBJETIVO instalacion=minimal" \
  >> "$BB_DIR/etc/registros.db"

cat <<EOF

╔════════════════════════════════════════════════════════════╗
║                 INSTALACIÓN COMPLETADA                     ║
╚════════════════════════════════════════════════════════════╝

FRASE DE LIBERACIÓN (guárdala AHORA, solo se muestra una vez):

    $FRASE

Para salir cuando quieras:
  sudo /opt/bigbrother/desinstalar.sh emergencia

👁 EL GRAN HERMANO TE OBSERVA
EOF