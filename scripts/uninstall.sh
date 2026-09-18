#!/usr/bin/env bash
# uninstall.sh — quita por completo ventura-xfce y deja el sistema como estaba.
#
# Uso:  ./scripts/uninstall.sh [-y] [--purge]
#         -y        no preguntar
#         --purge   además desinstala los paquetes apt (plank, xfce4-appmenu-plugin)
#
# Siempre restaura antes tu configuración anterior (equivale a 'macos-theme remove').

set -uo pipefail

PAYLOAD="${XDG_DATA_HOME:-$HOME/.local/share}/ventura-xfce"
BINDIR="$HOME/.local/bin"
ASSUME_YES=0
PURGE=0

msg()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m ! \033[0m%s\n' "$*" >&2; }

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --purge)  PURGE=1 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) warn "opción desconocida: $1"; exit 1 ;;
    esac; shift
done

confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    read -r -p "$1 [s/N] " r
    case "$r" in s|S|y|Y) return 0 ;; *) return 1 ;; esac
}

echo "Se va a eliminar:"
echo "  - la configuración aplicada (panel, dock, tema, fondo) → se restaura la tuya anterior"
echo "  - ~/.themes/WhiteSur-Light y ~/.themes/WhiteSur-Dark"
echo "  - ~/.icons/WhiteSur, ~/.icons/WhiteSur-dark, ~/.icons/custom, ~/.icons/WhiteSur-cursors"
echo "  - ~/.wallpapers/ventura-*.jpg|jpeg"
echo "  - ~/.local/share/plank/themes/WhiteSur"
echo "  - ~/.config/conky/ventura (monitor de recursos)"
echo "  - $PAYLOAD  y  $BINDIR/macos-theme"
[ "$PURGE" -eq 1 ] && echo "  - paquetes apt: plank, xfce4-appmenu-plugin"
[ "$PURGE" -eq 1 ] && echo "    (conky NO se desinstala: puede estar usándolo otro monitor tuyo)"
echo
confirm "¿Continuar?" || { echo "Cancelado."; exit 0; }

# 1. restaurar la configuración anterior
if [ -x "$BINDIR/macos-theme" ] && [ -d "$PAYLOAD/backup" ]; then
    msg "Restaurando tu configuración anterior"
    "$BINDIR/macos-theme" remove || warn "la restauración devolvió errores; revisa $PAYLOAD/backup"
else
    warn "Sin copia de seguridad: me salto la restauración"
fi

# 2. lightpad
if [ -d "$PAYLOAD/src/lightpad/build" ]; then
    if confirm "¿Desinstalar también lightpad (Launchpad)? Requiere sudo"; then
        msg "Desinstalando lightpad"
        sudo ninja -C "$PAYLOAD/src/lightpad/build" uninstall || warn "no se pudo desinstalar lightpad"
    fi
fi

# 3. copia de seguridad: ofrecer conservarla antes de borrar el payload
if [ -d "$PAYLOAD/backup" ]; then
    KEEP="$HOME/ventura-xfce-backup-$(date +%Y%m%d%H%M%S)"
    if confirm "¿Guardar una copia de la configuración respaldada en $KEEP?"; then
        cp -a "$PAYLOAD/backup" "$KEEP" && ok "copia guardada en $KEEP"
    fi
fi

# 4. ficheros instalados (nombres explícitos, nada de comodines peligrosos)
msg "Borrando temas, iconos y cursores"
for d in "$HOME/.themes/WhiteSur-Light" "$HOME/.themes/WhiteSur-Dark" \
         "$HOME/.icons/WhiteSur" "$HOME/.icons/WhiteSur-dark" \
         "$HOME/.icons/custom" "$HOME/.icons/WhiteSur-cursors" \
         "$HOME/.local/share/plank/themes/WhiteSur"; do
    [ -d "$d" ] && rm -rf "$d" && echo "   borrado $d"
done
rm -f "$HOME/.wallpapers/ventura-dark.jpg" "$HOME/.wallpapers/ventura-light.jpeg"
rmdir "$HOME/.wallpapers" 2>/dev/null || true
rm -f "$HOME/.config/autostart/plank.desktop" "$HOME/.config/autostart/conky-ventura.desktop"
rm -rf "$HOME/.config/conky/ventura"
rmdir "$HOME/.config/conky" 2>/dev/null || true

msg "Borrando el payload y el comando"
rm -rf "$PAYLOAD"
rm -f "$BINDIR/macos-theme"

# 5. paquetes
if [ "$PURGE" -eq 1 ]; then
    msg "Desinstalando paquetes apt"
    sudo apt-get remove -y plank xfce4-appmenu-plugin || warn "apt devolvió errores"
fi

echo
ok "ventura-xfce desinstalado."
echo "   Si el panel o el escritorio quedan raros, cierra sesión y vuelve a entrar."
