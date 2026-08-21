from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1024, 500
BG      = (13, 13, 13)         # #0D0D0D
NARANJA = (232, 118, 58)       # #E8763A
CREMA   = (245, 240, 232)      # #F5F0E8
MUTED   = (176, 168, 160)

AV = "/System/Library/Fonts/Avenir Next.ttc"
def font(idx, size): return ImageFont.truetype(AV, size, index=idx)
BOLD, DEMI, MEDIUM = 0, 2, 5

img = Image.new("RGB", (W, H), BG)

# ── resplandor naranja detrás del ícono ───────────────────────────────────
glow = Image.new("L", (W, H), 0)
gd = ImageDraw.Draw(glow)
gd.ellipse([70, 120, 400, 400], fill=46)
glow = glow.filter(ImageFilter.GaussianBlur(72))
img.paste(Image.new("RGB", (W, H), NARANJA), (0, 0), glow)

d = ImageDraw.Draw(img)

# ── ícono con esquinas redondeadas ────────────────────────────────────────
ICON = 232
icono = Image.open("/Users/reyfer/aura-flutter/store/play/icon-512.png").convert("RGB")
icono = icono.resize((ICON, ICON), Image.LANCZOS)
mask = Image.new("L", (ICON, ICON), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, ICON-1, ICON-1], radius=52, fill=255)
IX, IY = 104, (H - ICON) // 2
img.paste(icono, (IX, IY), mask)

# ── helper: texto con tracking ────────────────────────────────────────────
def tracked(draw, xy, texto, f, fill, tracking=0):
    x, y = xy
    for ch in texto:
        draw.text((x, y), ch, font=f, fill=fill)
        x += draw.textlength(ch, font=f) + tracking
    return x

def tracked_w(draw, texto, f, tracking=0):
    return sum(draw.textlength(c, font=f) for c in texto) + tracking * max(0, len(texto) - 1)

TX = 404   # inicio del bloque de texto

# ── wordmark ──────────────────────────────────────────────────────────────
f_marca = font(BOLD, 66)
tracked(d, (TX, 146), "AURA PASS", f_marca, CREMA, tracking=8.5)

# punto naranja de la marca, al final
wm_w = tracked_w(d, "AURA PASS", f_marca, 8.5)
d.ellipse([TX + wm_w + 6, 146 + 52, TX + wm_w + 20, 146 + 66], fill=NARANJA)

# ── regla naranja ─────────────────────────────────────────────────────────
d.rectangle([TX, 236, TX + 96, 239], fill=NARANJA)

# ── bajada ────────────────────────────────────────────────────────────────
f_sub = font(MEDIUM, 27)
d.text((TX, 266), "El marketplace de fitness y experiencias", font=f_sub, fill=MUTED)
d.text((TX, 301), "de Buenos Aires", font=f_sub, fill=MUTED)

# ── claim ─────────────────────────────────────────────────────────────────
f_claim = font(DEMI, 21)
tracked(d, (TX, 354), "MOVÉ.  EXPLORÁ.  VIVÍ.", f_claim, NARANJA, tracking=2.2)

out = "/Users/reyfer/aura-flutter/store/play/feature-graphic-1024x500.png"
img.save(out, "PNG", optimize=True)
print("guardado:", out)
print("tamaño  :", img.size)
