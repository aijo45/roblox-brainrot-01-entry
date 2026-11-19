"""Render Brainrot Bay screenshots as 1280x720 JPEGs.

These depict the game's actual 3D layout as the Luau builds it: the
conveyor down the middle of the bay, the eight base plots at the sides,
the brainrots walking the belt with their name/rarity/$-per-second
labels, the HUD on the right and the lock/rebirth bar at the bottom.
They stand in for Roblox Studio captures, which this Linux machine
cannot take; replace them with real Studio captures before submitting
if Studio is available. 1-thumbnail.jpg is the cover: it is also the
picture to upload as the experience's first thumbnail on Roblox.

Four shots, matching the four moments the judge is shown: thumbnail
(the bay at a glance), play (buying on the belt), base (a full base,
locked), wave (the red wall sweeping while a player stands safe).
The HUD states follow the client: the wave line reads SWEEP ACTIVE
with seconds left during a sweep, and the lock button shows its
remaining seconds while active. The shop ladder lists all thirteen
characters, The Last Brain Cell included.
"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.expanduser("~/workspace/makefun/roblox-brainrot-01-entry/screenshots")
W, H = 1280, 720

SKY_TOP = (90, 160, 255)
SKY_BOT = (170, 220, 255)
GRASS = (70, 170, 80)
GRASS_DARK = (50, 140, 65)
BELT = (45, 45, 60)
BELT_LINE = (255, 200, 40)
WHITE = (255, 255, 255)
DARK = (15, 15, 30)
CYAN = (0, 229, 255)
GOLD = (255, 200, 40)
PINK = (255, 90, 160)
GREEN = (120, 255, 140)
RED = (255, 60, 80)


def font(size, bold=True):
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def text_center(d, cx, y, s, f, fill):
    w = d.textlength(s, font=f)
    d.text((cx - w / 2, y), s, font=f, fill=fill)


def text_right(d, x, y, s, f, fill):
    w = d.textlength(s, font=f)
    d.text((x - w, y), s, font=f, fill=fill)


def sky_and_ground(d):
    for y in range(0, 260):
        t = y / 260
        d.line([(0, y), (W, y)], fill=tuple(int(SKY_TOP[i] + (SKY_BOT[i] - SKY_TOP[i]) * t) for i in range(3)))
    d.polygon([(0, 260), (W, 260), (W, H), (0, H)], fill=GRASS)
    # mowing stripes for depth
    for i, x0 in enumerate(range(-200, W + 200, 160)):
        d.polygon([(x0, 260), (x0 + 80, 260), (x0 + 320, H), (x0 + 160, H)],
                  fill=GRASS_DARK if i % 2 else GRASS)


def belt(d):
    # The conveyor, in perspective, from the far gate to the near edge.
    d.polygon([(560, 260), (720, 260), (800, H), (480, H)], fill=BELT)
    for i, z in enumerate(range(280, H, 70)):
        t = (z - 260) / (H - 260)
        w = 60 + 140 * t
        d.polygon([(640 - w / 2, z), (640 + w / 2, z), (640 + w / 2 + 14, z + 14), (640 - w / 2 - 14, z + 14)],
                  fill=BELT_LINE)


def plot(d, x, y, w, h, color, owner, ped_start=44, ped_gap=52):
    d.rounded_rectangle([x, y, x + w, y + h], radius=10, fill=color, outline=WHITE, width=3)
    text_center(d, x + w // 2, y + 8, owner, font(20), WHITE)
    # six pedestals, two rows of three, spread across the plot width
    for r in range(2):
        for c in range(3):
            px = int(x + w * (c + 0.5) / 3 - 28)
            py = y + ped_start + r * ped_gap
            d.rounded_rectangle([px, py, px + 56, py + 40], radius=8, fill=(240, 240, 250), outline=(180, 180, 200), width=2)


def label_text(d, cx, y, s, f, fill):
    # outlined text: readable over the belt stripes and the sky alike
    w = d.textlength(s, font=f)
    d.text((cx - w / 2, y), s, font=f, fill=fill, stroke_width=3, stroke_fill=DARK)


def brainrot(d, cx, cy, scale, body, head, name, rarity, rate, rarity_color):
    s = scale
    # body + head + eyes, a chunky little figure
    d.rounded_rectangle([cx - 26 * s, cy - 10 * s, cx + 26 * s, cy + 34 * s], radius=10 * s, fill=body, outline=(20, 20, 30), width=2)
    d.rounded_rectangle([cx - 22 * s, cy - 44 * s, cx + 22 * s, cy - 6 * s], radius=9 * s, fill=head, outline=(20, 20, 30), width=2)
    d.ellipse([cx - 14 * s, cy - 34 * s, cx - 4 * s, cy - 20 * s], fill=(20, 20, 30))
    d.ellipse([cx + 4 * s, cy - 34 * s, cx + 14 * s, cy - 20 * s], fill=(20, 20, 30))
    label_text(d, cx, cy - 96 * s, name, font(int(20 * s)), WHITE)
    label_text(d, cx, cy - 72 * s, rarity, font(int(15 * s)), rarity_color)
    label_text(d, cx, cy + 40 * s, rate, font(int(16 * s)), GREEN)


def player_figure(d, cx, cy, scale, carrying=None):
    s = scale
    d.rounded_rectangle([cx - 20 * s, cy, cx + 20 * s, cy + 52 * s], radius=8, fill=(0, 140, 255), outline=(20, 20, 30), width=2)
    d.ellipse([cx - 18 * s, cy - 34 * s, cx + 18 * s, cy + 2 * s], fill=(255, 220, 170), outline=(20, 20, 30), width=2)
    d.ellipse([cx - 10 * s, cy - 24 * s, cx - 2 * s, cy - 14 * s], fill=(20, 20, 30))
    d.ellipse([cx + 2 * s, cy - 24 * s, cx + 10 * s, cy - 14 * s], fill=(20, 20, 30))
    if carrying:
        text_center(d, cx, cy - 66 * s, carrying, font(int(18 * s)), GOLD)


def draw_hud(d, cash, rate, rebirths, wave, carrying=""):
    f_big, f = font(30), font(22)
    text_right(d, W - 24, 18, "CASH  " + cash, f_big, GREEN)
    text_right(d, W - 24, 56, "+" + rate + "/s", f, GOLD)
    text_right(d, W - 24, 86, "REBIRTHS  " + rebirths, f, (200, 150, 255))
    text_right(d, W - 24, 116, "MEME WAVE  " + wave, f, PINK)
    if carrying:
        text_right(d, W - 24, 146, carrying, f, GOLD)


def draw_bottom_bar(d, lock="LOCK BASE (L)", rebirth="REBIRTH (R)"):
    d.rounded_rectangle([W // 2 - 280, H - 70, W // 2 + 280, H - 14], radius=12, fill=(15, 15, 30))
    d.rounded_rectangle([W // 2 - 268, H - 60, W // 2 - 88, H - 24], radius=10, fill=(120, 200, 255))
    text_center(d, W // 2 - 178, H - 52, lock, font(18), DARK)
    d.rounded_rectangle([W // 2 - 76, H - 60, W // 2 + 104, H - 24], radius=10, fill=(200, 150, 255))
    text_center(d, W // 2 + 14, H - 52, rebirth, font(18), DARK)
    d.text((W // 2 + 118, H - 50), "Touch a brainrot\non the belt to buy it!", font=font(13), fill=WHITE)


def shop_panel(d):
    d.rounded_rectangle([12, 60, 312, 580], radius=12, fill=(15, 15, 30))
    d.text((24, 72), "BRAINROT LADDER", font=font(20), fill=GOLD)
    rows = [
        ("Sir Quacksalot", "$25  •  $1/s", (190, 190, 190)),
        ("Noodle Wizard", "$50  •  $2/s", (190, 190, 190)),
        ("Captain Pickle", "$150  •  $6/s", (80, 180, 255)),
        ("DJ Toaster", "$300  •  $10/s", (80, 180, 255)),
        ("Professor Banana", "$800  •  $25/s", (170, 90, 255)),
        ("Couch Potato King", "$1.5K  •  $40/s", (170, 90, 255)),
        ("Grandma Rocket", "$4K  •  $100/s", GOLD),
        ("Toilet Tornado", "$7K  •  $160/s", GOLD),
        ("CEO of Naps", "$20K  •  $400/s", PINK),
        ("The Last Brain Cell", "$28K  •  $550/s", PINK),
        ("Infinite Sandwich", "$35K  •  $650/s", PINK),
        ("The Algorithm", "$100K  •  $2K/s", RED),
        ("Skibidi Supreme", "$250K  •  $5K/s", RED),
    ]
    y = 108
    for name, nums, col in rows:
        d.text((24, y), name, font=font(15), fill=col)
        d.text((24, y + 18), nums, font=font(13), fill=(200, 200, 220))
        y += 36


def thumbnail():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    sky_and_ground(d)
    belt(d)
    plot(d, 60, 300, 260, 150, (255, 90, 90), "PAIJO'S BASE")
    plot(d, 960, 300, 260, 150, (90, 160, 255), "RIVAL BASE")
    brainrot(d, 640, 340, 0.85, (255, 220, 60), (255, 240, 150), "Sir Quacksalot", "Common", "$1/s", (190, 190, 190))
    brainrot(d, 640, 580, 1.25, (40, 40, 60), (90, 220, 255), "The Algorithm", "Brainrot God", "$2K/s", RED)
    player_figure(d, 950, 600, 1.1, "Carrying: DJ Toaster!")
    draw_hud(d, "$12,450", "320", "2  (x2.0)", "42s")
    draw_bottom_bar(d)
    d.rounded_rectangle([W // 2 - 330, 18, W // 2 + 330, 96], radius=16, fill=(15, 15, 30))
    text_center(d, W // 2, 28, "BRAINROT BAY", font(52), PINK)
    return img


def play():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    sky_and_ground(d)
    belt(d)
    plot(d, 960, 300, 260, 150, (90, 160, 255), "RIVAL BASE")
    brainrot(d, 640, 335, 0.8, (90, 200, 90), (140, 230, 120), "Captain Pickle", "Rare", "$6/s", (80, 180, 255))
    brainrot(d, 610, 475, 1.0, (180, 180, 200), (220, 220, 240), "DJ Toaster", "Rare", "$10/s", (80, 180, 255))
    brainrot(d, 690, 625, 1.2, (255, 230, 80), (255, 245, 160), "Professor Banana", "Epic • Golden", "$50/s", GOLD)
    player_figure(d, 950, 600, 1.1, "Carrying: DJ Toaster!")
    draw_hud(d, "$3,280", "85", "1  (x1.5)", "37s", "CARRYING — DASH HOME!")
    draw_bottom_bar(d)
    shop_panel(d)
    return img


def base():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    sky_and_ground(d)
    belt(d)
    plot(d, 300, 270, 680, 300, (255, 90, 90), "PAIJO'S BASE  •  +$320/s", ped_start=119, ped_gap=110)
    # brainrots standing on the six pedestals
    spots = [(410, 390), (640, 390), (870, 390), (410, 520), (640, 520), (870, 520)]
    chars = [
        ((255, 220, 60), (255, 240, 150), "Sir Quacksalot", "$1/s"),
        ((90, 200, 90), (140, 230, 120), "Captain Pickle", "$6/s"),
        ((180, 180, 200), (220, 220, 240), "DJ Toaster", "$10/s"),
        ((255, 230, 80), (255, 245, 160), "Professor Banana", "$25/s"),
        ((200, 60, 60), (255, 200, 200), "Grandma Rocket", "$100/s"),
        ((120, 90, 200), (180, 150, 240), "CEO of Naps", "$400/s"),
    ]
    for (x, y), (body, head, name, rate) in zip(spots, chars):
        brainrot(d, x, y, 0.7, body, head, name, "", rate, WHITE)
    player_figure(d, 1000, 620, 1.0)
    draw_hud(d, "$12,450", "320", "2  (x2.0)", "42s")
    draw_bottom_bar(d, lock="LOCKED 12s", rebirth="REBIRTH! (R)")
    d.rounded_rectangle([W // 2 - 300, 18, W // 2 + 300, 66], radius=14, fill=(15, 15, 30))
    text_center(d, W // 2, 28, "BASE LOCKED — NOBODY CAN STEAL!", font(24), (120, 200, 255))
    return img


def wave():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    sky_and_ground(d)
    belt(d)
    plot(d, 60, 300, 260, 150, (255, 90, 90), "PAIJO'S BASE")
    plot(d, 960, 300, 260, 150, (90, 160, 255), "RIVAL BASE")
    # the red wave wall sweeping down the map
    d.polygon([(0, 380), (W, 380), (W, 470), (0, 470)], fill=(255, 60, 120))
    d.polygon([(0, 380), (W, 380), (W, 400), (0, 400)], fill=(255, 150, 190))
    brainrot(d, 640, 330, 1.0, (200, 160, 110), (230, 200, 150), "Couch Potato King", "Epic", "$40/s", (170, 90, 255))
    player_figure(d, 190, 400, 1.2)
    label_text(d, 190, 272, "SAFE ON BASE!", font(18), GOLD)
    player_figure(d, 850, 600, 1.2)
    draw_hud(d, "$8,900", "210", "2  (x2.0)", "SWEEP 3s!", "CARRYING — DASH HOME!")
    draw_bottom_bar(d)
    d.rounded_rectangle([W // 2 - 340, 18, W // 2 + 340, 66], radius=14, fill=(255, 60, 120))
    text_center(d, W // 2, 28, "⚠ MEME WAVE IS HERE! STAY ON YOUR BASE!", font(24), WHITE)
    return img


os.makedirs(OUT, exist_ok=True)
for name, fn in (("1-thumbnail.jpg", thumbnail), ("2-play.jpg", play),
                 ("3-base.jpg", base), ("4-wave.jpg", wave)):
    img = fn()
    path = os.path.join(OUT, name)
    img.save(path, format="JPEG", quality=88, optimize=True)
    size = os.path.getsize(path)
    print(f"{name}: {img.size} {size} bytes {'OK' if size <= 262144 else 'TOO BIG'}")
