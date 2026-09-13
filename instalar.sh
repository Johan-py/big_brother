#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_DIR="/opt/bigbrother"
BIN_LINK="/usr/local/bin/bigbrother"

[[ $EUID -eq 0 ]] || { echo "El instalador requiere root: sudo ./instalar.sh"; exit 1; }

cat <<'EOF'
╔════════════════════════════════════════════════════════════╗
║           GRAN HERMANO v3.0 — CONSENTIMIENTO INFORMADO     ║
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
     - Overlays a pantalla completa con imágenes del Partido (3s-30min).
     - Bloqueo temporal de teclado/ratón (solo X11, máx. 30 min).
     - Bloqueo de sesión.
     - VAPORIZACIÓN: apagado programado del equipo durante 6-96 horas
       (duración aleatoria ponderada), con despertar automático por RTC.
  3. PROPAGANDA constante mediante notificaciones.

LÍMITES ÉTICOS DEL SISTEMA (garantizados por diseño):
  - Solo vigila la cuenta que consienta. Otras cuentas NO son tocadas.
  - NO modifica BIOS/UEFI ni GRUB. El hardware siempre es tuyo.
  - NO se reinstala a escondidas ni se defiende contra ti.
  - La salida SIEMPRE está disponible (ver abajo).

PROTOCOLO DE SALIDA (siempre disponible):
  Oficial:    sudo /usr/local/bin/bigbrother arrepentimiento
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

# head -c cierra el pipe antes de tiempo y tr recibe SIGPIPE (141); con
# pipefail + set -e eso mataba la instalación en silencio. cut consume todo.
FRASE=$(head -c 24 /dev/urandom | base64 -w0 2>/dev/null | tr -dc 'A-Za-z0-9' | cut -c1-20)

echo ">> Estableciendo cuartel general en $BB_DIR"
mkdir -p "$BB_DIR"/{bin,etc,logs/{vigilancia,castigos,vaporizaciones},assets/propaganda}
cp "$REPO_DIR"/bin/*.sh "$BB_DIR/bin/"
chmod 750 "$BB_DIR/bin/"*.sh
chmod 750 "$BB_DIR/etc" 2>/dev/null || true

cat > "$BB_DIR/etc/config.conf" <<EOF
USUARIO_VIGILADO=$USUARIO_OBJETIVO
LIMITE_DIARIO_MIN=180
TIEMPO_EXTRA_MIN=60
YOUTUBE_ADV_MIN=6
YOUTUBE_N1_MIN=10
YOUTUBE_N2_MIN=14
YOUTUBE_N3_MIN=20
PESO_YOUTUBE_SEG=90
REFLEXION_HORAS=24
PROPAGANDA_INTERVALO_MIN=5
VAPORIZACION_HABILITADA=1
EXILIO_MULT=150
EXILIO_MAX_H=96
TIEMPO_ADV_MIN=3
TIEMPO_N1_MIN=6
TIEMPO_N2_MIN=12
TIEMPO_N3_MIN=18
WINE_ADV_MIN=1
WINE_N2_MIN=2
WINE_N3_MIN=5
WINE_N4_MIN=9
COOLDOWN_ADV_S=180
COOLDOWN_N1_S=240
COOLDOWN_N2_S=360
COOLDOWN_N3_S=600
COOLDOWN_N4_S=3600
TIEMPO_N3_DUR_S=1800
WINE_N3_DUR_S=1200
YOUTUBE_N3_DUR_S=1200
SUDO_N3_DUR_S=900
EOF
chmod 640 "$BB_DIR/etc/config.conf"
echo "$FRASE" > "$BB_DIR/etc/frase_liberacion"
chmod 600 "$BB_DIR/etc/frase_liberacion"

echo ">> Inicializando bases de datos del Partido"
source "$BB_DIR/bin/lib.sh"
asegurar_dirs
db_init
db "INSERT INTO usuarios (usuario,nivel,alta,consentimiento) VALUES ('$(sql_esc "$USUARIO_OBJETIVO")',1,$(date +%s),'consentimiento_expreso');" 2>/dev/null || true
log_evento "CONSENTIMIENTO" "usuario=$USUARIO_OBJETIVO instalacion=v3.0"

chown -R root:root "$BB_DIR"
chmod 750 "$BB_DIR/etc" "$BB_DIR/logs"
find "$BB_DIR/logs" -type d -exec chmod 750 {} +
chmod 640 "$BB_DIR/etc/estado.db"

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

echo ">> Comando del ciudadano"
ln -sf "$BB_DIR/bin/bigbrother.sh" "$BIN_LINK"

cat > /etc/profile.d/bigbrother-motd.sh <<'EOF'
[[ $- == *i* ]] && echo "👁 GRAN HERMANO TE OBSERVA — Sistema de Control Totalitario activo"
EOF

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