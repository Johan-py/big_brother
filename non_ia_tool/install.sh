#!/usr/bin/env sh
# install.sh - Instala/configura la herramienta xdds (analiza.py) de forma
# automática en bash y zsh.
#
# Uso:
#   ./install.sh                     # instala y configura todo
#   KEY=sk-or-... ./install.sh       # pasa la clave por variable
#   ./install.sh --uninstall         # revierte la instalación

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
BIN_NAME="xdds"
TARGET="$SCRIPT_DIR/$BIN_NAME"

c_green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_yellow(){ printf '\033[1;33m%s\033[0m\n' "$*"; }
c_red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }

ensure_executable() {
    chmod +x "$TARGET" "$SCRIPT_DIR/analiza.py" 2>/dev/null || true
}

setup_env() {
    if [ -z "${KEY:-}" ] && [ -f "$ENV_FILE" ] && grep -q 'OPENROUTER_API_KEY=.' "$ENV_FILE" 2>/dev/null; then
        c_green "Clave ya configurada en $ENV_FILE"
        return
    fi
    key="${KEY:-}"
    if [ -z "$key" ]; then
        printf 'Introduce tu OPENROUTER_API_KEY (o deja vacío para no guardar): '
        read -r key
    fi
    if [ -n "$key" ]; then
        echo "OPENROUTER_API_KEY=$key" > "$ENV_FILE"
        chmod 600 "$ENV_FILE"
        c_green "Clave guardada en $ENV_FILE"
    else
        c_yellow "No se guardó clave; la pedirá interactiveamente al usar xdds."
    fi
}

install_symlink() {
    # Intenta instalar globalmente (sudo). Si falla, usa ~/.local/bin
    if ln -sf "$TARGET" /usr/local/bin/"$BIN_NAME" 2>/dev/null; then
        BIN_PATH="/usr/local/bin/$BIN_NAME"
        c_green "Instalado globalmente: /usr/local/bin/$BIN_NAME"
        return
    fi
    c_yellow "Sin permisos para /usr/local/bin, usando ~/.local/bin"
    mkdir -p "$HOME/.local/bin"
    ln -sf "$TARGET" "$HOME/.local/bin/$BIN_NAME"
    BIN_PATH="$HOME/.local/bin/$BIN_NAME"
    c_green "Instalado en: $BIN_PATH"
}

ensure_path() {
    local line='export PATH="$HOME/.local/bin:$PATH"'
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        if ! grep -qsF '# xdds (herramientas_ctf)' "$rc" 2>/dev/null; then
            printf '\n# xdds (herramientas_ctf)\n%s\n' "$line" >> "$rc"
            c_green "PATH añadido a $rc"
        else
            c_yellow "PATH ya en $rc"
        fi
    done
}

uninstall() {
    rm -f /usr/local/bin/"$BIN_NAME" 2>/dev/null
    rm -f "$HOME/.local/bin/$BIN_NAME" 2>/dev/null
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        [ -f "$rc" ] || continue
        tmp="$(mktemp)"
        grep -v '^# xdds (herramientas_ctf)$' "$rc" \
            | grep -v '^export PATH="$HOME/.local/bin:$PATH"$' > "$tmp"
        mv "$tmp" "$rc"
        c_green "Limpio en $rc"
    done
    c_yellow "Hecho. Elimina/maneja manualmente $ENV_FILE si quieres borrar tu clave."
}

case "${1:-}" in
    --uninstall|-u)
        uninstall
        exit 0 ;;
    --help|-h)
        sed -n '1,9p' "$0" | sed 's/^# *//'
        exit 0 ;;
esac

ensure_executable
setup_env
install_symlink
ensure_path

c_green ""
c_green "=== Instalación completa ==="
c_green "Abre una terminal nueva (o ejecuta: source ~/.zshrc; source ~/.bashrc)"
c_green "y úsalo así:  $BIN_NAME archivo1.txt [archivo2.c ...]"
