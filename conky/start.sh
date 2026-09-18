#!/bin/sh
# Lanza el monitor de recursos de ventura-xfce.
# Lo usan tanto "macos-theme apply" como el autoarranque de la sesión.
#   start.sh         → espera unos segundos (arranque de sesión)
#   start.sh --now   → arranca inmediatamente
set -u

DIR="$HOME/.config/conky/ventura"
STATE="${XDG_DATA_HOME:-$HOME/.local/share}/ventura-xfce/state"

[ -f "$DIR/ventura.conf" ] || { echo "falta $DIR/ventura.conf" >&2; exit 1; }
command -v conky >/dev/null 2>&1 || { echo "conky no está instalado" >&2; exit 1; }

# la variante (claro/oscuro) la marca el propio tema
VARIANT=dark
if grep -q '^variant=light' "$STATE" 2>/dev/null; then VARIANT=light; fi

# Inter es la libre más parecida a SF Pro; si no está, Noto Sans
FONT='Noto Sans'
if fc-list : family 2>/dev/null | tr ',' '\n' | grep -qx 'Inter'; then FONT='Inter'; fi

[ "${1:-}" = "--now" ] || sleep 4      # deja que arranquen compositor y panel

# nunca dos instancias de los mismos widgets
pkill -f 'conky -c .*conky/ventura/' 2>/dev/null

export VENTURA_VARIANT="$VARIANT" VENTURA_FONT="$FONT"

# ficha de gráficos (si hay alguna GPU que mostrar)
if [ -f "$DIR/gpu.conf" ]; then
    conky -c "$DIR/gpu.conf" >/dev/null 2>&1 &
fi

exec conky -c "$DIR/ventura.conf"
