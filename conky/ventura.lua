--[[  ventura-xfce · monitor de recursos inspirado en macOS
      Todo el widget se dibuja con Cairo para tener control de píxel:
      tarjeta translúcida, anillos tipo Centro de Control, gráficas
      suavizadas al estilo Monitor de Actividad y pastilla de batería.

      Variables de entorno que acepta (las pone macos-theme):
        VENTURA_VARIANT = dark | light
        VENTURA_FONT    = familia tipográfica (por defecto Noto Sans)
--]]

require 'cairo'
local ok_xlib, cairo_xlib = pcall(require, 'cairo_xlib')
if not ok_xlib then
    cairo_xlib = setmetatable({}, { __index = function(_, k) return _G[k] end })
end

local VARIANT = (os.getenv('VENTURA_VARIANT') or 'dark'):lower()
local FONT    = os.getenv('VENTURA_FONT') or 'Noto Sans'
local PI      = math.pi

-- ───────────────────────────────────────────────────────────── paleta ──
local PALETTES = {
    dark = {
        card   = {0.11, 0.12, 0.14, 0.78},
        shadow = {0.00, 0.00, 0.00, 0.30},
        border = {1.00, 1.00, 1.00, 0.12},
        sheen  = {1.00, 1.00, 1.00, 0.06},
        sep    = {1.00, 1.00, 1.00, 0.08},
        track  = {1.00, 1.00, 1.00, 0.10},
        text   = {1.00, 1.00, 1.00, 0.94},
        dim    = {1.00, 1.00, 1.00, 0.46},
        graph  = {1.00, 1.00, 1.00, 0.08},
    },
    light = {
        card   = {0.99, 0.99, 1.00, 0.84},
        shadow = {0.20, 0.22, 0.28, 0.20},
        border = {0.00, 0.00, 0.00, 0.08},
        sheen  = {1.00, 1.00, 1.00, 0.35},
        sep    = {0.00, 0.00, 0.00, 0.08},
        track  = {0.00, 0.00, 0.00, 0.08},
        text   = {0.08, 0.09, 0.11, 0.96},
        dim    = {0.08, 0.09, 0.11, 0.45},
        graph  = {0.00, 0.00, 0.00, 0.05},
    },
}
local C = PALETTES[VARIANT] or PALETTES.dark

-- acentos del sistema (idénticos en claro y oscuro, como en macOS)
local A = {
    blue   = {0.04, 0.52, 1.00},
    purple = {0.69, 0.32, 0.87},
    teal   = {0.19, 0.68, 0.89},
    green  = {0.16, 0.78, 0.34},
    orange = {1.00, 0.62, 0.04},
    red    = {1.00, 0.27, 0.23},
    yellow = {1.00, 0.80, 0.00},
}

-- ──────────────────────────────────────────────────────────── geometría ──
local W, PAD = 330, 14           -- ancho de ventana y margen para la sombra
local X0, CW = PAD, W - PAD * 2  -- tarjeta
local L, R    = X0 + 18, X0 + CW - 18   -- margen interno de texto
local RADIUS  = 18

-- ───────────────────────────────────────────────────────── utilidades ──
local function q(s) return conky_parse(s) or '' end

local function num(s)
    local v = q(s):gsub('%%', ''):gsub(',', '.'):gsub('[^%d%.%-]', '')
    return tonumber(v) or 0
end

local function rgba(cr, c, a)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], a or c[4] or 1)
end

local function rounded(cr, x, y, w, h, r)
    r = math.min(r, w / 2, h / 2)
    cairo_new_path(cr)
    cairo_move_to(cr, x + r, y)
    cairo_line_to(cr, x + w - r, y)
    cairo_arc(cr, x + w - r, y + r, r, -PI / 2, 0)
    cairo_line_to(cr, x + w, y + h - r)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, PI / 2)
    cairo_line_to(cr, x + r, y + h)
    cairo_arc(cr, x + r, y + h - r, r, PI / 2, PI)
    cairo_line_to(cr, x, y + r)
    cairo_arc(cr, x + r, y + r, r, PI, 1.5 * PI)
    cairo_close_path(cr)
end

local function text(cr, s, x, y, size, bold, color, align)
    if s == nil or s == '' then return 0 end
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    local te = cairo_text_extents_t:create()
    tolua.takeownership(te)
    cairo_text_extents(cr, s, te)
    local tx = x
    if align == 'c' then tx = x - te.width / 2 - te.x_bearing
    elseif align == 'r' then tx = x - te.width - te.x_bearing end
    rgba(cr, color)
    cairo_move_to(cr, tx, y)
    cairo_show_text(cr, s)
    cairo_new_path(cr)
    local w = te.width
    te = nil
    return w
end

local function separator(cr, y)
    rgba(cr, C.sep)
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, L, y + 0.5)
    cairo_line_to(cr, R, y + 0.5)
    cairo_stroke(cr)
end

-- color según carga: el acento propio hasta el 85 %, luego ámbar y rojo
local function load_color(base, pct)
    if pct >= 92 then return A.red
    elseif pct >= 80 then return A.orange end
    return base
end

-- ───────────────────────────────────────────── anillo tipo macOS ──
local function ring(cr, cx, cy, r, lw, frac, color)
    frac = math.max(0, math.min(1, frac))
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    -- carril
    cairo_set_line_width(cr, lw)
    rgba(cr, C.track)
    cairo_arc(cr, cx, cy, r, 0, 2 * PI)
    cairo_stroke(cr)
    if frac <= 0.002 then return end
    local a0, a1 = -PI / 2, -PI / 2 + 2 * PI * frac
    -- resplandor
    cairo_set_line_width(cr, lw + 5)
    rgba(cr, color, 0.16)
    cairo_arc(cr, cx, cy, r, a0, a1)
    cairo_stroke(cr)
    -- valor
    cairo_set_line_width(cr, lw)
    rgba(cr, color, 1)
    cairo_arc(cr, cx, cy, r, a0, a1)
    cairo_stroke(cr)
end

local function gauge(cr, cx, cy, pct, base, label, big, small)
    local color = load_color(base, pct)
    ring(cr, cx, cy, 29, 8, pct / 100, color)
    text(cr, big, cx, cy + 4, 15.5, true, C.text, 'c')
    if small and small ~= '' then
        text(cr, small, cx, cy + 18, 8, false, C.dim, 'c')
    end
    text(cr, label, cx, cy + 48, 8.5, true, C.dim, 'c')
end

-- ────────────────────────────────── gráfica suavizada (historial) ──
local HIST = { cpu = {}, down = {}, up = {} }
local HIST_LEN = 46

local function push(t, v)
    table.insert(t, v)
    while #t > HIST_LEN do table.remove(t, 1) end
end

local function sparkline(cr, hist, x, y, w, h, color, peak)
    local n = #hist
    if n < 2 then return end
    local maxv = peak or 1
    for _, v in ipairs(hist) do if v > maxv then maxv = v end end
    local step = w / (HIST_LEN - 1)
    -- fondo de la gráfica
    rgba(cr, C.graph)
    rounded(cr, x, y, w, h, 4)
    cairo_fill(cr)
    -- relleno bajo la curva
    cairo_new_path(cr)
    local first = HIST_LEN - n
    cairo_move_to(cr, x + first * step, y + h)
    for i, v in ipairs(hist) do
        cairo_line_to(cr, x + (first + i - 1) * step, y + h - (v / maxv) * (h - 2) - 1)
    end
    cairo_line_to(cr, x + (HIST_LEN - 1) * step, y + h)
    cairo_close_path(cr)
    rgba(cr, color, 0.22)
    cairo_fill(cr)
    -- curva
    cairo_new_path(cr)
    for i, v in ipairs(hist) do
        local px, py = x + (first + i - 1) * step, y + h - (v / maxv) * (h - 2) - 1
        if i == 1 then cairo_move_to(cr, px, py) else cairo_line_to(cr, px, py) end
    end
    cairo_set_line_width(cr, 1.4)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    rgba(cr, color, 0.95)
    cairo_stroke(cr)
end

-- ──────────────────────────────────── barras por núcleo (mini) ──
local function core_bars(cr, x, y, w, h, cores)
    local n = #cores
    if n == 0 then return end
    local bw = math.min(7, (w - 2 * (n - 1)) / n)
    local gap = (w - bw * n) / math.max(1, n - 1)
    for i, v in ipairs(cores) do
        local bx = x + (i - 1) * (bw + gap)
        rgba(cr, C.track)
        rounded(cr, bx, y, bw, h, 2)
        cairo_fill(cr)
        local bh = math.max(2.5, h * math.min(v, 100) / 100)
        rgba(cr, load_color(A.blue, v))
        rounded(cr, bx, y + h - bh, bw, bh, 2)
        cairo_fill(cr)
    end
end

-- flechas de tráfico dibujadas a mano (la API de texto de Cairo no
-- hace fallback de fuentes y ↑↓ no siempre existe en la familia elegida)
local function arrow(cr, x, y, dir, color)
    cairo_new_path(cr)
    if dir == 'down' then
        cairo_move_to(cr, x, y + 3)
        cairo_line_to(cr, x + 6, y + 3)
        cairo_line_to(cr, x + 3, y + 7.5)
    else
        cairo_move_to(cr, x, y + 4.5)
        cairo_line_to(cr, x + 6, y + 4.5)
        cairo_line_to(cr, x + 3, y)
    end
    cairo_close_path(cr)
    rgba(cr, color)
    cairo_fill(cr)
end

-- ───────────────────────────────────────── pastilla de batería ──
local function battery_pill(cr, x, y, pct, charging)
    local w, h = 26, 12
    local color = A.green
    if not charging and pct <= 10 then color = A.red
    elseif not charging and pct <= 25 then color = A.yellow end
    -- carcasa
    rgba(cr, C.dim, 0.55)
    cairo_set_line_width(cr, 1)
    rounded(cr, x + 0.5, y + 0.5, w, h, 3.5)
    cairo_stroke(cr)
    -- borne
    rgba(cr, C.dim, 0.45)
    rounded(cr, x + w + 2, y + h / 2 - 2.5, 2, 5, 1)
    cairo_fill(cr)
    -- carga
    local fill = math.max(2, (w - 3) * math.min(pct, 100) / 100)
    rgba(cr, color)
    rounded(cr, x + 2, y + 2, fill, h - 3, 2.5)
    cairo_fill(cr)
    if charging then  -- rayo
        cairo_new_path(cr)
        local cx, cy = x + w / 2, y + h / 2
        cairo_move_to(cr, cx + 1.5, cy - 4.5)
        cairo_line_to(cr, cx - 2.5, cy + 0.5)
        cairo_line_to(cr, cx - 0.2, cy + 0.5)
        cairo_line_to(cr, cx - 1.5, cy + 4.5)
        cairo_line_to(cr, cx + 2.5, cy - 0.5)
        cairo_line_to(cr, cx + 0.2, cy - 0.5)
        cairo_close_path(cr)
        rgba(cr, {1, 1, 1, 0.95})
        cairo_fill(cr)
    end
end

-- ───────────────────────────────────── detección de hardware ──
local function first_line(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local l = f:read('*l')
    f:close()
    return l
end

local TEMP_DEV                      -- nombre hwmon para la temperatura de CPU
for i = 0, 15 do
    local name = first_line(('/sys/class/hwmon/hwmon%d/name'):format(i))
    if name == 'coretemp' or name == 'k10temp' or name == 'zenpower' then
        TEMP_DEV = name; break
    elseif name == 'acpitz' and not TEMP_DEV then
        TEMP_DEV = name
    end
end

local BAT                           -- primera batería encontrada
for _, n in ipairs({ 'BAT0', 'BAT1', 'BAT2', 'CMB0' }) do
    if first_line('/sys/class/power_supply/' .. n .. '/status') then BAT = n; break end
end

local NCORES = 0                    -- hilos de CPU, para las barras por núcleo
local cpuinfo = io.open('/proc/cpuinfo')
if cpuinfo then
    for line in cpuinfo:lines() do
        if line:match('^processor') then NCORES = NCORES + 1 end
    end
    cpuinfo:close()
end
if NCORES > 16 then NCORES = 16 end   -- no dibujamos más de 16 barras

local USER = os.getenv('USER') or os.getenv('LOGNAME') or ''


-- ───────────────────────────────── cápsula de progreso (barra) ──
local function capsule(cr, x, y, w, h, frac, color)
    frac = math.max(0, math.min(1, frac))
    rgba(cr, C.track)
    rounded(cr, x, y, w, h, h / 2)
    cairo_fill(cr)
    if frac > 0.001 then
        rgba(cr, color)
        rounded(cr, x, y, math.max(h, w * frac), h, h / 2)
        cairo_fill(cr)
    end
end

-- ──────────────────────────────────────── detección de GPUs ──
-- Recorre /sys/class/drm buscando tarjetas reales y las clasifica por
-- driver: i915/xe/amdgpu integradas, nvidia/amdgpu discreta según PCI.
local function read_link(path)
    local h = io.popen('readlink -f "' .. path .. '" 2>/dev/null')
    if not h then return nil end
    local v = h:read('*l'); h:close()
    return v
end

local function pretty_gpu_name(raw)
    if not raw then return nil end
    local inside = raw:match('%[([^%]]+)%]')     -- lspci mete el nombre comercial entre corchetes
    local name = inside or raw
    name = name:gsub('%s*Laptop GPU', ''):gsub('%s*Mobile', '')
    name = name:gsub('%s*Integrated Graphics Controller', ' Graphics')
    name = name:gsub('%s*%(rev %x+%)', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #name > 26 then name = name:sub(1, 25) .. '…' end
    return name
end

local function detect_gpus()
    local list, names = {}, {}
    -- nombres comerciales: un único fork al arrancar
    local h = io.popen("lspci -mm 2>/dev/null | grep -E '\"(VGA|3D|Display)' ")
    if h then
        for line in h:lines() do
            local slot = line:match('^(%S+)')
            local dev  = line:match('"[^"]*"%s*$') or line:match('"([^"]+)"%s*$')
            local parts = {}
            for f in line:gmatch('"([^"]*)"') do parts[#parts + 1] = f end
            -- parts: clase, fabricante, dispositivo, ...
            if slot and parts[3] then names['0000:' .. slot] = pretty_gpu_name(parts[3]) end
        end
        h:close()
    end
    for i = 0, 6 do
        local base = ('/sys/class/drm/card%d'):format(i)
        if first_line(base .. '/dev') then
            local drv = read_link(base .. '/device/driver')
            drv = drv and drv:match('([^/]+)$') or '?'
            local pci = read_link(base .. '/device')
            pci = pci and pci:match('([%x]+:[%x]+:[%x]+%.%d)$') or nil
            local vendor = first_line(base .. '/device/vendor') or ''
            local kind = 'discrete'
            if drv == 'i915' or drv == 'xe' then kind = 'integrated'
            elseif vendor == '0x1002' and pci and pci:match('^0000:00') then kind = 'integrated' end
            list[#list + 1] = {
                sysfs = base, driver = drv, pci = pci, kind = kind,
                name = (pci and names[pci]) or ('GPU ' .. i),
            }
        end
    end
    return list
end

local GPUS = detect_gpus()
local IGPU, DGPU
for _, g in ipairs(GPUS) do
    if g.kind == 'integrated' and not IGPU then IGPU = g
    elseif g.kind == 'discrete' and not DGPU then DGPU = g end
end

-- ─────────────────────── NVIDIA: se consulta solo si está despierta ──
-- Coste cero cuando duerme: el estado se lee de sysfs y del procfs del
-- driver (ninguno despierta la tarjeta). nvidia-smi SÍ la despierta, así
-- que solo se llama si ya está activa, y si detectamos que lleva un rato
-- sin carga dejamos de preguntar un tiempo para que el kernel la suspenda.
local NV = { t = 0, data = nil, awake = false, idle = 0, hold = 0, stale = false }
-- La propia consulta a nvidia-smi marca un 3-5 % de uso, así que "sin
-- trabajo" se decide por umbral, no por un cero exacto.
local NV_IDLE_PCT  = 5     -- % de uso por debajo del cual no hay carga real
local NV_IDLE_HITS = 3     -- lecturas seguidas así antes de callarnos
local NV_HOLD_S    = 120   -- silencio para que el kernel pueda suspenderla

local function nvidia_awake()
    if not DGPU or DGPU.driver ~= 'nvidia' or not DGPU.pci then return false, 'sin driver' end
    local st = first_line('/sys/bus/pci/devices/' .. DGPU.pci .. '/power/runtime_status') or 'unknown'
    if st ~= 'active' then return false, st end
    -- segundo aval del propio driver, también gratis
    local f = io.open('/proc/driver/nvidia/gpus/' .. DGPU.pci .. '/power', 'r')
    if f then
        local vram
        for line in f:lines() do
            vram = line:match('^Video Memory:%s+(%S+)')
            if vram then break end
        end
        f:close()
        if vram and vram ~= 'Active' then return false, 'vram ' .. vram:lower() end
    end
    return true, 'active'
end

local function nvidia_poll()
    local awake, st = nvidia_awake()
    NV.awake = awake
    NV.state = st
    if not awake then NV.data = nil; NV.idle = 0; return end
    local now = os.time()
    if now < NV.hold then NV.stale = true; return end   -- en pausa: no la molestamos
    if NV.data and (now - NV.t) < 5 then return end     -- como máximo una consulta cada 5 s
    NV.t = now
    local h = io.popen('nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,' ..
                       'temperature.gpu,clocks.gr --format=csv,noheader,nounits 2>/dev/null')
    if not h then return end
    local line = h:read('*l'); h:close()
    if not line then return end
    local f = {}
    for v in line:gmatch('([^,]+)') do f[#f + 1] = tonumber((v:gsub('%s', ''))) end
    if #f >= 5 then
        NV.data = { util = f[1], used = f[2], total = f[3], temp = f[4], clock = f[5] }
        NV.stale = false
        -- Nos fijamos solo en el uso, no en la VRAM: en Optimus quedan
        -- cientos de MiB reservados aunque no haya ninguna carga.
        if f[1] <= NV_IDLE_PCT then NV.idle = NV.idle + 1 else NV.idle = 0 end
        if NV.idle >= NV_IDLE_HITS then
            NV.idle = 0
            NV.hold = now + NV_HOLD_S
        end
    end
end

-- ─────────────────────────────────────────────────────────── dibujo ──
-- rejilla vertical: líneas base absolutas, así el diseño no depende
-- de cómo conky vaya apilando texto (todo se pinta a mano)
local Y = {
    head = 38,  sep1 = 52,  rings = 104, sep2 = 164,
    cpu  = 184, bars = 192, spark = 216, sep3 = 256,
    apps = 274, row1 = 292, sep4  = 350,
    net  = 368, speed = 388, nspark = 394, sep5 = 430,
    foot = 450,
}

function conky_ventura_draw()
    if conky_window == nil then return end
    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                         conky_window.visual, conky_window.width,
                                         conky_window.height)
    local cr = cairo_create(cs)
    local H = conky_window.height

    -- ░ tarjeta: sombra difusa + material translúcido + brillo superior
    for i = 6, 1, -1 do
        rgba(cr, C.shadow, (C.shadow[4] or 0.3) / (i * 3.1))
        rounded(cr, X0 - i, PAD - i + 2, CW + i * 2, H - PAD * 2 + i * 2, RADIUS + i)
        cairo_fill(cr)
    end
    rgba(cr, C.card)
    rounded(cr, X0, PAD, CW, H - PAD * 2, RADIUS)
    cairo_fill(cr)

    local grad = cairo_pattern_create_linear(X0, PAD, X0, PAD + 90)
    cairo_pattern_add_color_stop_rgba(grad, 0, C.sheen[1], C.sheen[2], C.sheen[3], C.sheen[4])
    cairo_pattern_add_color_stop_rgba(grad, 1, C.sheen[1], C.sheen[2], C.sheen[3], 0)
    rounded(cr, X0, PAD, CW, H - PAD * 2, RADIUS)
    cairo_set_source(cr, grad)
    cairo_fill(cr)
    cairo_pattern_destroy(grad)

    rgba(cr, C.border)
    cairo_set_line_width(cr, 1)
    rounded(cr, X0 + 0.5, PAD + 0.5, CW - 1, H - PAD * 2 - 1, RADIUS)
    cairo_stroke(cr)

    -- ░ cabecera: semáforo de ventana + equipo + tiempo encendido
    local lights = { A.red, A.yellow, A.green }
    for i, col in ipairs(lights) do
        rgba(cr, col)
        cairo_arc(cr, L + 4 + (i - 1) * 15, Y.head - 4, 4.6, 0, 2 * PI)
        cairo_fill(cr)
    end
    text(cr, USER .. '@' .. q('${nodename}'), L + 50, Y.head, 10.5, true, C.text, 'l')
    text(cr, q('${uptime_short}'), R, Y.head, 9, false, C.dim, 'r')
    separator(cr, Y.sep1)

    -- ░ tres anillos: CPU · memoria · disco
    local cpu   = num('${cpu cpu0}')
    local memp  = num('${memperc}')
    local diskp = num('${fs_used_perc /}')
    push(HIST.cpu, cpu)

    gauge(cr, L + 42, Y.rings, cpu, A.blue, 'CPU', ('%d%%'):format(cpu),
          (TEMP_DEV and ('%d°'):format(num('${hwmon ' .. TEMP_DEV .. ' temp 1}')) or nil))
    gauge(cr, X0 + CW / 2, Y.rings, memp, A.purple, 'MEMORIA', ('%d%%'):format(memp), q('${mem}'))
    gauge(cr, R - 42, Y.rings, diskp, A.teal, 'DISCO', ('%d%%'):format(diskp), q('${fs_used /}'))
    separator(cr, Y.sep2)

    -- ░ procesador: frecuencia, carga, un hilo por barra e historial
    text(cr, 'Procesador', L, Y.cpu, 9.5, true, C.text, 'l')
    text(cr, ('%s GHz  ·  carga %s'):format(q('${freq_g}'), q('${loadavg 1}')),
         R, Y.cpu, 9, false, C.dim, 'r')
    local cores = {}
    for i = 1, NCORES do cores[i] = num('${cpu cpu' .. i .. '}') end
    core_bars(cr, L, Y.bars, R - L, 17, cores)
    sparkline(cr, HIST.cpu, L, Y.spark, R - L, 32, A.blue, 20)
    separator(cr, Y.sep3)

    -- ░ top de procesos, al estilo Monitor de Actividad
    text(cr, 'Aplicaciones', L, Y.apps, 9.5, true, C.text, 'l')
    text(cr, '% CPU', R, Y.apps, 8.5, false, C.dim, 'r')
    for i = 1, 4 do
        local name = q('${top name ' .. i .. '}'):gsub('%s+$', '')
        local pct  = num('${top cpu ' .. i .. '}')
        local y = Y.row1 + (i - 1) * 15
        rgba(cr, A.blue, 0.10)      -- barrita proporcional al consumo
        rounded(cr, L - 4, y - 9, math.max(3, (R - L + 8) * math.min(pct, 100) / 100), 12, 3)
        cairo_fill(cr)
        text(cr, name, L, y, 9, false, C.text, 'l')
        text(cr, ('%.1f'):format(pct), R, y, 9, false, C.dim, 'r')
    end
    separator(cr, Y.sep4)

    -- ░ red: interfaz con puerta de salida, velocidades e historial
    local iface = q('${gw_iface}')
    if iface == '' or iface:find('No default') then iface = '' end
    text(cr, 'Red', L, Y.net, 9.5, true, C.text, 'l')
    if iface == '' then
        text(cr, 'sin conexión', R, Y.net, 9, false, C.dim, 'r')
    else
        text(cr, iface .. '  ·  ' .. q('${addr ' .. iface .. '}'), R, Y.net, 9, false, C.dim, 'r')
        local down = num('${downspeedf ' .. iface .. '}')
        local up   = num('${upspeedf ' .. iface .. '}')
        push(HIST.down, down)
        push(HIST.up, up)
        local half = (R - L - 12) / 2
        arrow(cr, L, Y.speed - 8, 'down', A.green)
        text(cr, q('${downspeed ' .. iface .. '}'), L + 11, Y.speed, 9, true, A.green, 'l')
        arrow(cr, R - 6, Y.speed - 8, 'up', A.blue)
        text(cr, q('${upspeed ' .. iface .. '}'), R - 11, Y.speed, 9, true, A.blue, 'r')
        sparkline(cr, HIST.down, L, Y.nspark, half, 26, A.green, 40)
        sparkline(cr, HIST.up, L + half + 12, Y.nspark, half, 26, A.blue, 40)
    end
    separator(cr, Y.sep5)

    -- ░ pie: batería y espacio libre
    if BAT then
        local pct = num('${battery_percent ' .. BAT .. '}')
        local st  = (first_line('/sys/class/power_supply/' .. BAT .. '/status') or ''):lower()
        local charging = st:find('charging') ~= nil and st:find('not charging') == nil
        battery_pill(cr, L, Y.foot - 9, pct, charging)
        local label = ('%d%%'):format(pct)
        local rest = q('${battery_time ' .. BAT .. '}')
        if charging then label = label .. '  cargando'
        elseif st:find('full') then label = label .. '  cargada'
        elseif rest ~= '' and not rest:find('unknown') then label = label .. '  ' .. rest end
        text(cr, label, L + 36, Y.foot, 9, false, C.dim, 'l')
    else
        text(cr, 'Corriente alterna', L, Y.foot, 9, false, C.dim, 'l')
    end
    text(cr, q('${fs_free /}') .. ' libres', R, Y.foot, 9, false, C.dim, 'r')

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end


-- ═══════════════════════════════════ segunda tarjeta: gráficos ══
-- Se dibuja en su propia ventana (conky/gpu.conf), flotando justo
-- debajo de la tarjeta principal.
local GY = { head = 34, sep1 = 48, a = 88, sep2 = 124, b = 172 }

local function gpu_block(cr, g, cy, ring_frac, ring_color, line2_left, line2_right, bar_frac, bar_label)
    local tx = L + 52
    -- anillo
    ring(cr, L + 22, cy, 19, 6, ring_frac, ring_color)
    text(cr, ('%d%%'):format(math.floor(ring_frac * 100 + 0.5)), L + 22, cy + 4, 9.5, true, C.text, 'c')
    -- nombre + driver
    rgba(cr, ring_color)
    cairo_arc(cr, tx + 3, cy - 20, 3.2, 0, 2 * PI)
    cairo_fill(cr)
    text(cr, g and g.name or 'sin GPU', tx + 12, cy - 17, 9.5, true, C.text, 'l')
    text(cr, g and g.driver or '', R, cy - 17, 8.5, false, C.dim, 'r')
    -- segunda línea
    text(cr, line2_left, tx, cy - 1, 9, false, C.text, 'l')
    text(cr, line2_right, R, cy - 1, 8.5, false, C.dim, 'r')
    -- barra + etiqueta
    if bar_label then text(cr, bar_label, tx, cy + 15, 8.5, false, C.dim, 'l') end
    capsule(cr, tx, cy + 21, R - tx, 6, bar_frac, ring_color)
end

function conky_ventura_gpu_draw()
    if conky_window == nil then return end
    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                         conky_window.visual, conky_window.width,
                                         conky_window.height)
    local cr = cairo_create(cs)
    local H = conky_window.height

    -- ░ misma tarjeta translúcida que el monitor principal
    for i = 6, 1, -1 do
        rgba(cr, C.shadow, (C.shadow[4] or 0.3) / (i * 3.1))
        rounded(cr, X0 - i, PAD - i + 2, CW + i * 2, H - PAD * 2 + i * 2, RADIUS + i)
        cairo_fill(cr)
    end
    rgba(cr, C.card)
    rounded(cr, X0, PAD, CW, H - PAD * 2, RADIUS)
    cairo_fill(cr)
    local grad = cairo_pattern_create_linear(X0, PAD, X0, PAD + 70)
    cairo_pattern_add_color_stop_rgba(grad, 0, C.sheen[1], C.sheen[2], C.sheen[3], C.sheen[4])
    cairo_pattern_add_color_stop_rgba(grad, 1, C.sheen[1], C.sheen[2], C.sheen[3], 0)
    rounded(cr, X0, PAD, CW, H - PAD * 2, RADIUS)
    cairo_set_source(cr, grad)
    cairo_fill(cr)
    cairo_pattern_destroy(grad)
    rgba(cr, C.border)
    cairo_set_line_width(cr, 1)
    rounded(cr, X0 + 0.5, PAD + 0.5, CW - 1, H - PAD * 2 - 1, RADIUS)
    cairo_stroke(cr)

    -- ░ cabecera
    text(cr, 'Gráficos', L, GY.head, 10.5, true, C.text, 'l')
    local topology = ''
    if IGPU and DGPU then
        topology = (DGPU.driver == 'nvidia') and 'Optimus' or 'doble GPU'
    elseif #GPUS > 0 then
        topology = 'GPU única'
    end
    text(cr, topology, R, GY.head, 9, false, C.dim, 'r')
    separator(cr, GY.sep1)

    -- ░ GPU integrada: sin dato de uso (el kernel lo reserva a root),
    --   así que mostramos la frecuencia real del motor gráfico
    if IGPU then
        local act = tonumber(first_line(IGPU.sysfs .. '/gt_act_freq_mhz')) or 0
        local cur = tonumber(first_line(IGPU.sysfs .. '/gt_cur_freq_mhz')) or 0
        local top = tonumber(first_line(IGPU.sysfs .. '/gt_RP0_freq_mhz'))
                    or tonumber(first_line(IGPU.sysfs .. '/gt_max_freq_mhz')) or 1
        local tmp = TEMP_DEV and ('%d°'):format(num('${hwmon ' .. TEMP_DEV .. ' temp 1}')) or ''
        local main, state, frac
        if act > 0 then
            main, state, frac = ('%d MHz'):format(act), 'activa', act / top
        else
            -- gt_act_freq_mhz a 0 = motor apagado (RC6); cur es solo la petición
            main, state, frac = 'en reposo', ('RC6 · petición %d MHz'):format(cur), 0
        end
        gpu_block(cr, IGPU, GY.a, frac, A.teal, main, state, frac,
                  ('frecuencia · máx %d MHz  ·  %s del paquete'):format(top, tmp))
    else
        text(cr, 'sin GPU integrada', L, GY.a, 9, false, C.dim, 'l')
    end
    separator(cr, GY.sep2)

    -- ░ GPU dedicada: solo se interroga si no está suspendida, para no
    --   despertarla (en Optimus cada consulta cuesta batería)
    if DGPU then
        if DGPU.driver == 'nvidia' then
            nvidia_poll()
            if NV.awake and NV.data then
                local d = NV.data
                gpu_block(cr, DGPU, GY.b, d.util / 100, load_color(A.green, d.util),
                          ('%d°  ·  %.2f GHz'):format(d.temp, d.clock / 1000),
                          NV.stale and 'sin carga · en espera' or 'activa',
                          d.used / math.max(1, d.total),
                          ('VRAM %d de %d MiB'):format(d.used, d.total))
            else
                local st = NV.state or 'desconocido'
                local label = (st == 'suspended') and 'en reposo · D3cold' or
                              (st == 'active' and 'sin carga · en espera' or st)
                gpu_block(cr, DGPU, GY.b, 0, A.green, 'sin carga', label, 0,
                          'no se consulta mientras no haya trabajo')
            end
        else
            gpu_block(cr, DGPU, GY.b, 0, A.green, DGPU.driver, '', 0, 'sin métricas para este driver')
        end
    else
        text(cr, 'sin GPU dedicada', L, GY.b - 1, 9, false, C.dim, 'l')
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
