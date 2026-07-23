#!/usr/bin/env python3
"""Generate the MailScrub app icon master PNG (1024x1024).

Concept (UI_SPEC §16): removal, not cleaning. An open envelope whose flap has
been peeled/lifted away and floats above it, tilted, mid-motion. Two-three
simple shapes so it stays legible in monochrome at 16pt. Blue accent #0A7CFF.
Rendered at 4x and downscaled with LANCZOS for clean anti-aliased edges.
"""
from PIL import Image, ImageDraw, ImageFilter
import math

SS = 4                # supersample factor
S = 1024 * SS         # working size
OUT = "/Users/brooksc/code/MailScrub.mac/Packages/MailScrubKit/Resources/AppIcon.png"

def sc(v):
    return int(round(v * SS))

# --- background: vertical blue gradient, full bleed ---
top = (10, 124, 255)      # #0A7CFF accent
bot = (0, 82, 214)        # #0052D6 deeper blue
bg = Image.new("RGB", (S, S), top)
px = bg.load()
grad = Image.new("RGB", (1, 1024))
gpx = grad.load()
for y in range(1024):
    t = y / 1023
    gpx[0, y] = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
bg = grad.resize((S, S))
img = bg.convert("RGBA")

draw = ImageDraw.Draw(img)

WHITE = (255, 255, 255, 255)
SEAM = (10, 124, 255, 255)   # accent seams on the white envelope

# --- envelope body (white rounded rectangle) ---
# content is inset ~10% from the 1024 canvas edges (~102px margin).
bx0, by0, bx1, by1 = 210, 478, 814, 768
draw.rounded_rectangle([sc(bx0), sc(by0), sc(bx1), sc(by1)],
                       radius=sc(46), fill=WHITE)

# front-pocket seam: two lines rising from the bottom corners to a center
# point — the open-envelope front pocket (the flap that used to seal it is
# gone). Reads as an opened envelope even in monochrome.
seam_w = sc(18)
cx, cy = 512, 574
draw.line([sc(bx0 + 24), sc(by1 - 24), sc(cx), sc(cy)], fill=SEAM, width=seam_w)
draw.line([sc(bx1 - 24), sc(by1 - 24), sc(cx), sc(cy)], fill=SEAM, width=seam_w)

# --- the peeled-away flap, on its own layer so it can rotate + cast a shadow ---
# A downward-pointing triangle (envelope-flap shape) hovering just above the
# envelope's open top: the flap lifted off, mid-removal.
flap = Image.new("RGBA", (S, S), (0, 0, 0, 0))
fd = ImageDraw.Draw(flap)
ax, ay = 272, 322
bx, by = 752, 322
px_, py_ = 512, 434
fd.polygon([(sc(ax), sc(ay)), (sc(bx), sc(by)), (sc(px_), sc(py_))], fill=WHITE)

# tilt it slightly so it looks lifted/peeled on one side
angle = 4
flap = flap.rotate(angle, resample=Image.BICUBIC, center=(sc(512), sc(374)))
# small right nudge for motion
dx, dy = sc(10), sc(0)
flap = flap.transform(flap.size, Image.AFFINE, (1, 0, -dx, 0, 1, -dy),
                      resample=Image.BICUBIC)

# soft shadow beneath the lifted flap for a peel/3D depth cue
alpha = flap.split()[3]
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
shadow.paste((0, 40, 110, 70), mask=alpha)
shadow = shadow.filter(ImageFilter.GaussianBlur(sc(7)))
shadow = shadow.transform(shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, sc(15)),
                          resample=Image.BICUBIC)
img = Image.alpha_composite(img, shadow)
img = Image.alpha_composite(img, flap)

# --- downscale ---
final = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
final.save(OUT)
print("wrote", OUT, final.size)
