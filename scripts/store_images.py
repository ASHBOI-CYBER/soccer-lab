"""App Store images in the style the team picked (2026-11-23): a bold headline, a short line, and a real screen from the
app in a phone, on a dark blue background with a glowing wave. 1320 x 2868 (iPhone 6.9-inch).

    python scripts/store_images.py <folder with app screenshots> <output folder>

Every screen shown is a real screenshot of Soccer Lab; nothing claims users, ratings or results the app doesn't have.
"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
FONTS = r"C:\Windows\Fonts"
HEAD = ImageFont.truetype(os.path.join(FONTS, "impact.ttf"), 210)
BODY = ImageFont.truetype(os.path.join(FONTS, "segoeuib.ttf"), 54)
CHIP = ImageFont.truetype(os.path.join(FONTS, "segoeuib.ttf"), 50)
BLUE, HI = (30, 120, 255), (125, 184, 255)

# (file, headline lines, sub line, bullets, layout)
PAGES = [
    ("m1-home", ["TRAIN LIKE", "A PRO"], None,
     ["A daily plan for your position", "150+ drills with moving diagrams", "Timer, XP and streaks"], "bottom"),
    ("m2-coach", ["ASK SOCCO"], "Your AI football buddy. It knows your position, your sessions and your food.", None, "top"),
    ("m3-timer", ["EVERY REP", "COUNTS"], "Start the drill, beat the clock, rate your reps and earn XP.", None, "top"),
    ("m4-film", ["ANALYZE", "LIKE A PRO"], "Upload a clip. Get a score, what to fix and the drills that fix it.", None, "bottom"),
    ("m5-scan", ["FUEL YOUR", "GAME"], "Snap your plate. See calories and protein in seconds.", None, "bottom"),
    ("m8-nutrition", ["HIT YOUR", "NUMBERS"], "Calories, protein, carbs and water, set for your body and your goal.", None, "top"),
    ("m6-profile", ["GROW EVERY", "DAY"], "Level up your skill map, keep your streak and climb the ranks.", None, "top"),
]


def background():
    img = Image.new("RGB", (W, H), (3, 6, 16))
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(glow)
    # a big blue glow low on the page, and a bright wave line through it
    d.ellipse((-500, int(H * 0.52), W + 500, int(H * 1.35)), fill=(10, 50, 170))
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    img = Image.blend(img, glow, 0.85)
    wave = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wave)
    pts = [(x, H * 0.60 + math.sin(x / W * math.pi * 1.6 + 0.6) * 120) for x in range(-20, W + 21, 8)]
    for width, alpha in [(60, 40), (26, 90), (8, 255)]:
        wd.line(pts, fill=(60, 140, 255, alpha), width=width, joint="curve")
    wave = wave.filter(ImageFilter.GaussianBlur(3))
    img = img.convert("RGBA")
    img.alpha_composite(wave)
    return img


def phone(shot, width):
    s = Image.open(shot).convert("RGB")
    h = int(s.height * width / s.width)
    s = s.resize((width, h), Image.LANCZOS)
    r = int(width * 0.13)
    mask = Image.new("L", (width, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width, h), radius=r, fill=255)
    bezel = int(width * 0.028)
    frame = Image.new("RGBA", (width + 2 * bezel, h + 2 * bezel), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle((0, 0, frame.width - 1, frame.height - 1), radius=r + bezel, fill=(16, 18, 24),
                         outline=(70, 78, 96), width=4)
    frame.paste(s, (bezel, bezel), mask)
    return frame


def shadowed(layer, blur=40, spread=(0, 30)):
    sh = Image.new("RGBA", (layer.width + 200, layer.height + 200), (0, 0, 0, 0))
    a = layer.split()[3].point(lambda v: 170 if v else 0)
    sh.paste((0, 0, 0, 255), (100 + spread[0], 100 + spread[1]), a)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    sh.alpha_composite(layer, (100, 100))
    return sh


def wrap(text, font, width, d):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if d.textlength(t, font=font) <= width:
            cur = t
        else:
            lines.append(cur)
            cur = w
    return lines + [cur]


def page(name, head, sub, bullets, layout):
    img = background()
    d = ImageDraw.Draw(img)
    pw = 880
    ph = phone(os.path.join(SRC, name + ".png"), pw)
    ph = shadowed(ph)
    margin = 90
    if layout == "top":
        y = 170
        for line in head:
            d.text((margin, y), line, font=HEAD, fill="white")
            y += 205
        if sub:
            for line in wrap(sub, BODY, W - 2 * margin, d):
                d.text((margin, y + 20), line, font=BODY, fill=(205, 214, 235))
                y += 70
        img.alpha_composite(ph, ((W - ph.width) // 2, y + 40))
    else:
        img.alpha_composite(ph, ((W - ph.width) // 2, -340))
        y = H - 210 - 205 * len(head) - (len(wrap(sub, BODY, W - 2 * margin, d)) * 70 if sub else 0) - (len(bullets) * 120 + 60 if bullets else 0)
        for line in head:
            d.text((margin, y), line, font=HEAD, fill="white")
            y += 205
        if sub:
            for line in wrap(sub, BODY, W - 2 * margin, d):
                d.text((margin, y + 20), line, font=BODY, fill=(205, 214, 235))
                y += 70
        if bullets:
            y += 60
            for b in bullets:
                tw = d.textlength(b, font=CHIP)
                d.rounded_rectangle((margin, y, margin + tw + 150, y + 96), radius=48, fill=(14, 24, 52), outline=(50, 90, 180), width=3)
                cx, cy = margin + 52, y + 48
                d.ellipse((cx - 24, cy - 24, cx + 24, cy + 24), fill=BLUE)
                d.line([(cx - 11, cy), (cx - 3, cy + 9), (cx + 12, cy - 9)], fill="white", width=7)
                d.text((margin + 98, y + 18), b, font=CHIP, fill="white")
                y += 120
    return img.convert("RGB")


for i, (name, head, sub, bullets, layout) in enumerate(PAGES, 1):
    if not os.path.exists(os.path.join(SRC, name + ".png")):
        print("missing", name)
        continue
    out = os.path.join(OUT, f"{i:02d}-{name.split('-', 1)[1]}.png")
    page(name, head, sub, bullets, layout).save(out, optimize=True)
    print("made", out)
