#!/usr/bin/env bash
# install.sh — instalador corregido de ventura-xfce para Xubuntu 24.04+/26.04 (XFCE 4.18–4.20, X11)
#
# Qué arregla respecto al README original:
#   * extrae los temas/iconos DENTRO de ~/.themes y ~/.icons (el README los dejaba en $HOME)
#   * sustituye las rutas quemadas /home/ibm-7094 Y /home/lukas por tu $HOME
#   * corrige el nombre del tema (los XML pedían "WhiteSur-Dark-nord", que no existe en el repo)
#   * no usa sudo para tu ~/.config (el README dejaba la configuración en manos de root)
#   * no copia XML de hardware/atajos ajenos (displays, teclado, energía, sesión)
#   * rehace los .dockitem de plank: apunta a launchers reales y descarta apps no instaladas
#   * deja el fondo de pantalla al comando macos-theme, que lo aplica a TUS monitores
#   * activa el menú global (appmenu): el tema lo incluye en el panel pero nadie
#     encendía /Gtk/Modules ni ShellShowsMenubar, así que salía siempre vacío
#   * añade el monitor de recursos en conky (tarjeta translúcida estilo macOS)
#
# Uso:  ./scripts/install.sh [--no-deps] [--with-lightpad]

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAYLOAD="${XDG_DATA_HOME:-$HOME/.local/share}/ventura-xfce"
BINDIR="$HOME/.local/bin"
WITH_DEPS=1
WITH_LIGHTPAD=0
MISSING_APPS=()

msg()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m ! \033[0m%s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --no-deps)       WITH_DEPS=0 ;;
        --with-lightpad) WITH_LIGHTPAD=1 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) die "opción desconocida: $1" ;;
    esac; shift
done

# ------------------------------------------------------------ comprobaciones
[ "$(id -u)" -ne 0 ] || die "No ejecutes este script como root. Se te pedirá sudo solo para apt."
[ -f "$REPO/gtk/gtkthemes/WhiteSur-Dark.tar.xz" ] || die "Ejecútalo desde el repo ventura-xfce (falta gtk/gtkthemes)."
command -v xfconf-query >/dev/null || die "No encuentro xfconf-query: ¿estás en XFCE?"
if [ "${XDG_SESSION_TYPE:-x11}" = "wayland" ]; then
    warn "Estás en una sesión Wayland. plank, el tema de xfwm4 y el appmenu solo funcionan en X11."
fi

# ------------------------------------------------------------------ paquetes
if [ "$WITH_DEPS" -eq 1 ]; then
    msg "Instalando dependencias (se te pedirá la contraseña de sudo)"
    PKGS=(plank xfce4-appmenu-plugin appmenu-gtk3-module conky-all fonts-inter)
    [ "$WITH_LIGHTPAD" -eq 1 ] && PKGS+=(meson ninja-build valac libvala-0.56-dev libgee-0.8-dev \
        libgnome-menu-3-dev libglib2.0-dev libgtk-3-dev libwnck-3-dev gnome-menus python3)
    sudo apt-get update
    sudo apt-get install -y "${PKGS[@]}"
    ok "Dependencias instaladas"
else
    msg "Me salto la instalación de dependencias (--no-deps)"
fi

# -------------------------------------------------------- temas/iconos/cursor
msg "Instalando temas GTK en ~/.themes"
mkdir -p "$HOME/.themes" "$HOME/.icons" "$HOME/.wallpapers"
tar -xf "$REPO/gtk/gtkthemes/WhiteSur-Light.tar.xz" -C "$HOME/.themes"
tar -xf "$REPO/gtk/gtkthemes/WhiteSur-Dark.tar.xz"  -C "$HOME/.themes"

msg "Instalando iconos y cursores en ~/.icons"
tar -xf "$REPO/gtk/icons/01-WhiteSur.tar.xz"   -C "$HOME/.icons"
tar -xf "$REPO/gtk/icons/custom.tar.xz"        -C "$HOME/.icons"
tar -xf "$REPO/cursors/WhiteSur-cursors.tar.xz" -C "$HOME/.icons"
for t in WhiteSur WhiteSur-dark; do
    [ -d "$HOME/.icons/$t" ] && gtk-update-icon-cache -q -f "$HOME/.icons/$t" 2>/dev/null || true
done

msg "Copiando fondos de pantalla a ~/.wallpapers"
cp -f "$REPO/wallpapers/"* "$HOME/.wallpapers/"

msg "Instalando el monitor de recursos (conky)"
mkdir -p "$HOME/.config/conky/ventura"
cp -f "$REPO/conky/ventura.conf" "$REPO/conky/gpu.conf" \
      "$REPO/conky/ventura.lua" "$HOME/.config/conky/ventura/"
install -m 755 "$REPO/conky/start.sh" "$HOME/.config/conky/ventura/start.sh"

msg "Instalando el tema de plank"
mkdir -p "$HOME/.local/share/plank/themes/WhiteSur"
cp -f "$HOME/.themes/WhiteSur-Dark/plank/dock.theme" "$HOME/.local/share/plank/themes/WhiteSur/dock.theme"

# ------------------------------------------------------------------- payload
msg "Preparando la configuración corregida en $PAYLOAD"
rm -rf "$PAYLOAD/launchers" "$PAYLOAD/panel" "$PAYLOAD/xfconf" "$PAYLOAD/plank"
mkdir -p "$PAYLOAD"/{launchers,panel,xfconf,plank/dock1/launchers}

fix_paths() { # sustituye las rutas de los autores por tu $HOME y neutraliza Exec inválidos
    sed -i -e "s|/home/ibm-7094|$HOME|g" -e "s|/home/lukas|$HOME|g" \
           -e 's|^Exec=0$|Exec=true|' -e 's|^Exec=null$|Exec=true|' "$@"
}

# launchers del dock
cp -f "$REPO/dock/launchers/"*.desktop "$PAYLOAD/launchers/"
fix_paths "$PAYLOAD/launchers/"*.desktop
chmod +x "$PAYLOAD/launchers/"*.desktop

# launchers del panel superior
cp -a "$REPO/config/xfce4/panel/." "$PAYLOAD/panel/"
find "$PAYLOAD/panel" -name '*.desktop' -print0 | xargs -0 -r sed -i \
    -e "s|/home/ibm-7094|$HOME|g" -e "s|/home/lukas|$HOME|g" \
    -e 's|^Exec=0$|Exec=true|' -e 's|^Exec=null$|Exec=true|'

# solo el XML del panel: el resto (displays, teclado, energía, sesión...) es
# configuración del equipo del autor y no debe tocarse.
cp -f "$REPO/config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" "$PAYLOAD/xfconf/"
sed -i -e "s|/home/ibm-7094|$HOME|g" -e "s|/home/lukas|$HOME|g" "$PAYLOAD/xfconf/xfce4-panel.xml"

cp -f "$REPO/config/xfce4/terminal/terminalrc" "$PAYLOAD/terminalrc"

# ------------------------------------------------------------ dock de plank
resolve_desktop() { # busca un .desktop instalado; devuelve su ruta o falla
    local name="$1" d alt=""
    case "$name" in
        org.gnome.Terminal.desktop) alt="xfce4-terminal.desktop" ;;
        org.gnome.Software.desktop) alt="snap-store_snap-store.desktop" ;;
        firefox.desktop)            alt="firefox_firefox.desktop" ;;
        mousepad.desktop)           alt="org.xfce.mousepad.desktop" ;;
        ristretto.desktop)          alt="org.xfce.ristretto.desktop" ;;
        vlc.desktop)                alt="org.xfce.Parole.desktop" ;;
    esac
    for candidate in "$name" "$alt"; do
        [ -n "$candidate" ] || continue
        for d in /usr/share/applications /usr/local/share/applications \
                 /var/lib/snapd/desktop/applications \
                 /var/lib/flatpak/exports/share/applications \
                 "$HOME/.local/share/flatpak/exports/share/applications" \
                 "$HOME/.local/share/applications"; do
            [ -f "$d/$candidate" ] && { printf '%s\n' "$d/$candidate"; return 0; }
        done
    done
    return 1
}

msg "Rehaciendo los accesos del dock"
# el orden del dock sigue el orden de creación de los ficheros
DOCK_ORDER="finder launcher safari mail messages maps photos music tv notes pages Calc Keynote Discord codium thunar org.gnome.Software org.gnome.Terminal firefox vlc trash"
list_items() { for n in $DOCK_ORDER; do [ -f "$REPO/dock/plank/dock1/launchers/$n.dockitem" ] && echo "$n"; done
               for f in "$REPO/dock/plank/dock1/launchers/"*.dockitem; do
                   n=$(basename "$f" .dockitem)
                   echo " $DOCK_ORDER " | grep -q " $n " || echo "$n"
               done; }

while read -r item; do
    [ -n "$item" ] || continue
    src="$REPO/dock/plank/dock1/launchers/$item.dockitem"
    uri=$(grep -m1 '^Launcher=' "$src" | cut -d= -f2-)
    case "$uri" in
        docklet://*)
            newuri="$uri" ;;
        file:///usr/share/applications/*)
            base="${uri##*/}"
            if target=$(resolve_desktop "$base"); then newuri="file://$target"
            else MISSING_APPS+=("$base (icono '$item' omitido)"); continue; fi ;;
        *Desktop/.spoofed_icons/*)
            base="${uri##*/}"
            if [ -f "$PAYLOAD/launchers/$base" ]; then newuri="file://$PAYLOAD/launchers/$base"
            else MISSING_APPS+=("$base (no está en dock/launchers; omitido)"); continue; fi ;;
        file:///home/*)
            newuri="file://$HOME" ; item="home" ;;   # el icono de la carpeta personal
        *) newuri="$uri" ;;
    esac
    printf '[PlankDockItemPreferences]\nLauncher=%s\n' "$newuri" > "$PAYLOAD/plank/dock1/launchers/$item.dockitem"
done < <(list_items)

cat > "$PAYLOAD/plank/dock1/settings" <<'EOF'
[PlankDockPreferences]
CurrentWorkspaceOnly=false
IconSize=48
HideMode=0
UnhideDelay=0
HideDelay=0
Monitor=
Offset=0
Position=3
Alignment=3
ItemsAlignment=3
LockItems=false
PressureReveal=false
PinnedOnly=false
AutoPinning=true
ShowDockItem=false
ZoomEnabled=true
ZoomPercent=150
Theme=WhiteSur
EOF

# avisa de los ejecutables que los launchers usan y no tienes instalados
for f in "$PAYLOAD/launchers/"*.desktop; do
    exec_line=$(grep -m1 '^Exec=' "$f" | cut -d= -f2- | awk '{print $1}')
    case "$exec_line" in
        true|""|http*) continue ;;
        flatpak) grep -q 'io.bassi.Amberol' "$f" && \
            flatpak info io.bassi.Amberol >/dev/null 2>&1 || MISSING_APPS+=("flatpak io.bassi.Amberol ($(basename "$f"))"); continue ;;
    esac
    command -v "$exec_line" >/dev/null 2>&1 || MISSING_APPS+=("$exec_line ($(basename "$f"))")
done

# ---------------------------------------------------------------- lightpad
if [ "$WITH_LIGHTPAD" -eq 1 ]; then
    msg "Compilando lightpad (Launchpad)"
    rm -rf "$PAYLOAD/src/lightpad"
    mkdir -p "$PAYLOAD/src"
    cp -a "$REPO/lightpad" "$PAYLOAD/src/lightpad"
    # meson.source_root() está obsoleto desde meson 0.56 y desaparece en meson 2.0
    sed -i 's/meson\.source_root()/meson.project_source_root()/' "$PAYLOAD/src/lightpad/meson.build"
    (
        cd "$PAYLOAD/src/lightpad"
        meson setup build --prefix=/usr --wipe 2>/dev/null || meson setup build --prefix=/usr
        ninja -C build
        sudo ninja -C build install
    ) && ok "lightpad instalado (desinstalar: sudo ninja -C $PAYLOAD/src/lightpad/build uninstall)" \
      || warn "lightpad no compiló. El resto del tema funciona; el icono Launchpad no abrirá nada."
else
    msg "Me salto lightpad (usa --with-lightpad si quieres el Launchpad)"
fi

# ------------------------------------------------------------------ comando
msg "Instalando el comando macos-theme en $BINDIR"
mkdir -p "$BINDIR"
install -m 755 "$REPO/scripts/macos-theme" "$BINDIR/macos-theme"
printf 'applied=0\ninstalled=%s\n' "$(date -Is)" > "$PAYLOAD/state"

echo
ok "Instalación terminada."
echo
echo "   macos-theme apply          activa el look macOS (oscuro)"
echo "   macos-theme apply --light  variante clara"
echo "   macos-theme remove         restaura tu configuración anterior"
echo "   macos-theme status         estado actual"
echo
if [ ${#MISSING_APPS[@]} -gt 0 ]; then
    warn "Estos programas los usa el tema pero no los tienes instalados:"
    printf '     - %s\n' "${MISSING_APPS[@]}"
    echo "     (los iconos afectados se han omitido o no harán nada al pulsarlos)"
fi
case ":$PATH:" in *":$BINDIR:"*) ;; *) warn "$BINDIR no está en tu PATH; añádelo o usa $BINDIR/macos-theme" ;; esac
