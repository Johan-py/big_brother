#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_DIR="/opt/bigbrother"

[[ $EUID -eq 0 ]] || { echo "El instalador requiere root: sudo ./instalar.sh"; exit 1; }

cat <<'EOF'
╔════════════════════════════════════════════════════════════╗
║           GRAN HERMANO v2.0 — CONSENTIMIENTO INFORMADO     ║
╚════════════════════════════════════════════════════════════╝

ANTES DE CONTINUAR, LEE ESTO COMPLETO. Es un contrato contigo mismo.

QUÉ HARÁ ESTE SISTEMA:
  1. VIGILANCIA de la cuenta que elijas, y SOLO de esa cuenta:
     - Tiempo total de sesión gráfica diaria.
     - Uso de wine/software de Windows (clasificado como subversivo).
     - Visitas a YouTube registradas en el historial del navegador.
     - Todos los comandos ejecutados con sudo (vía journal del sistema).
  2. CASTIGOS AUTOMÁTICOS según tu configuración:
     - Advertencias y notificaciones propagandísticas.
     - Overlays a pantalla completa con imágenes del Partido (3s-15min).
     - Bloqueo temporal de teclado/ratón (solo X11, máx. 15 min).
     - Bloqueo de sesión.
     - VAPORIZACIÓN: apagado programado del equipo durante 6-72 horas
       (duración aleatoria ponderada), con despertar automático por RTC.
  3. PROPAGANDA constante mediante notificaciones.

LÍMITES ÉTICOS DEL SISTEMA (garantizados por diseño):
  - Solo vigila la cuenta que consienta. Otras cuentas NO son tocadas.
  - NO modifica BIOS/UEFI ni GRUB. El hardware siempre es tuyo.
  - NO se reinstala a escondidas ni se defiende contra ti.
  - La salida SIEMPRE está disponible (ver abajo).

PROTOCOLO DE SALIDA (siempre disponible):
  Oficial:    sudo /opt/bigbrother/bin/bigbrother.sh arrepentimiento
              → período de reflexión obligatorio + frase de liberación
              → desinstalación limpia y completa.
  Emergencia: sudo /opt/bigbrother/desinstalar.sh emergencia
              → frase de liberación + desinstalación INMEDIATA.
              Existe para que este software NUNCA pueda atraparte,
              incluso si falla.
  Tu frase de liberación se genera al final de esta instalación.
  Guárdala. También puedes consultarla con:
              sudo cat /opt/bigbrother/etc/frase_liberacion

HONESTIDAD TÉCNICA:
  Esto es software de compromiso voluntario (estilo "locked mode"),
  no firmware. Un administrador determinado podría neutralizarlo.
  La experiencia asume buena fe: el miedo es psicológico, no criptográfico.

EOF

read -rp "Ciudadano a vigilar [$SUDO_USER]: " USUARIO_OBJETIVO
USUARIO_OBJETIVO=${USUARIO_OBJETIVO:-$SUDO_USER}
if ! id "$USUARIO_OBJETIVO" &>/dev/null; then
  echo "Ese ciudadano no existe en el sistema."
  exit 1
fi

echo
read -rp "Escribe 'ACEPTO LA VIGILANCIA' para continuar: " consentimiento
[[ "$consentimiento" == "ACEPTO LA VIGILANCIA" ]] || {
  echo "El Partido rechaza ciudadanos indecisos. Instalación cancelada."
  exit 1
}

FRASE=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)

echo ">> Estableciendo cuartel general en $BB_DIR"
mkdir -p "$BB_DIR"/{bin,etc,logs/{vigilancia,castigos,vaporizaciones},assets/propaganda}
cp "$REPO_DIR"/bin/*.sh "$BB_DIR/bin/"
chmod 750 "$BB_DIR/bin/"*.sh

touch "$BB_DIR/etc"/{registros.db,tiempo.db,castigos.db,exilio.db,salida.db}
echo "$USUARIO_OBJETIVO|1|$(date +%s)|consentimiento_expreso" > "$BB_DIR/etc/usuarios.db"

cat > "$BB_DIR/etc/config.conf" <<EOF
USUARIO_VIGILADO=$USUARIO_OBJETIVO
LIMITE_DIARIO_MIN=180
TIEMPO_EXTRA_MIN=60
YOUTUBE_LIMITE_MIN=30
PESO_YOUTUBE_SEG=60
REFLEXION_HORAS=24
PROPAGANDA_INTERVALO_MIN=7
VAPORIZACION_HABILITADA=1
EOF
chmod 640 "$BB_DIR/etc/config.conf"
echo "$FRASE" > "$BB_DIR/etc/frase_liberacion"
chmod 600 "$BB_DIR/etc/frase_liberacion"
chown -R root:root "$BB_DIR"

echo ">> Generando efigies del Partido"
if command -v convert >/dev/null 2>&1; then
  convert -size 1920x1080 xc:black -fill red -gravity center \
    -pointsize 120 -annotate 0 "👁 GRAN HERMANO" \
    -pointsize 60 -annotate +0+200 "TE OBSERVA" \
    -stroke white -strokewidth 8 -fill black \
    -draw "ellipse 960,420 180,90 0,360 -ellipse 960,420 60,45 0,360" \
    "$BB_DIR/assets/gran_hermano.png" 2>/dev/null || true
  convert -size 1920x1080 xc:'#1a1a2e' -fill white -gravity center \
    -pointsize 100 -annotate 0 "O'BRIEN" \
    -pointsize 50 -annotate +0+150 "LA RESISTENCIA ES INÚTIL" \
    "$BB_DIR/assets/obrien.png" 2>/dev/null || true
fi
if [[ ! -s "$BB_DIR/assets/gran_hermano.png" ]]; then
  echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" \
    | base64 -d > "$BB_DIR/assets/gran_hermano.png"
  cp "$BB_DIR/assets/gran_hermano.png" "$BB_DIR/assets/obrien.png"
fi

echo ">> Instalando servicios del Partido"
cp "$REPO_DIR/systemd/bigbrother.service" /etc/systemd/system/
cp "$REPO_DIR/systemd/bigbrother-propaganda.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now bigbrother.service bigbrother-propaganda.service

cat > /etc/profile.d/bigbrother-motd.sh <<'EOF'
[[ $- == *i* ]] && echo "👁 GRAN HERMANO TE OBSERVA — Sistema de Control Totalitario activo"
EOF

echo "$(date +%s)|$(date +%Y-%m-%d)|CONSENTIMIENTO|usuario=$USUARIO_OBJETIVO instalacion=v2.0" \
  >> "$BB_DIR/etc/registros.db"

cat <<EOF

╔════════════════════════════════════════════════════════════╗
║                 INSTALACIÓN COMPLETADA                     ║
╚════════════════════════════════════════════════════════════╝

FRASE DE LIBERACIÓN (guárdala AHORA, solo se muestra una vez):

    $FRASE

Comandos disponibles:
  bigbrother estado            → panel de control
  bigbrother informes          → informe de actividad
  bigbrother arrepentimiento   → protocolo oficial de salida
  sudo /opt/bigbrother/desinstalar.sh emergencia → salida inmediata

👁 EL GRAN HERMANO TE OBSERVA
EOF
