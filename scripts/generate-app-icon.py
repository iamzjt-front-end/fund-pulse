from pathlib import Path
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
ICON_SIZE = 1024
SCALE = 4
CANVAS = ICON_SIZE * SCALE
ICON_INSET = 100
ICON_BODY = 824
ICON_RADIUS = 185.4


def lerp(a, b, t):
    return int(round(a + (b - a) * t))


def mix(c1, c2, t):
    return tuple(lerp(c1[i], c2[i], t) for i in range(len(c1)))


def gradient_color(t):
    green = (32, 201, 151, 255)
    blue = (22, 119, 255, 255)
    red = (255, 90, 107, 255)
    if t <= 0.52:
        return mix(green, blue, t / 0.52)
    return mix(blue, red, (t - 0.52) / 0.48)


def build_gradient(size):
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            t = min(1, max(0, (x * 0.45 + y * 0.55) / (size - 1)))
            pixels[x, y] = gradient_color(t)
    return image


def draw_polyline_mask(size, points, width):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.line(points, fill=255, width=width, joint="curve")
    radius = width // 2
    for x, y in points:
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)
    return mask


def scaled(value):
    return round(value * CANVAS / ICON_SIZE)


def main():
    BUILD.mkdir(exist_ok=True)
    image = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    rect = tuple(scaled(v) for v in (ICON_INSET, ICON_INSET, ICON_INSET + ICON_BODY, ICON_INSET + ICON_BODY))
    radius = scaled(ICON_RADIUS)
    body_mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(body_mask).rounded_rectangle(rect, radius=radius, fill=255)

    shadow_rect = (rect[0], rect[1] + scaled(12), rect[2], rect[3] + scaled(12))
    shadow_mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(shadow_mask).rounded_rectangle(shadow_rect, radius=radius, fill=130)
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(scaled(28)))
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 128))
    image.alpha_composite(Image.composite(shadow, Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0)), shadow_mask))

    body = Image.composite(build_gradient(CANVAS), Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0)), body_mask)
    image.alpha_composite(body)

    draw = ImageDraw.Draw(image)
    highlight_rect = tuple(scaled(v) for v in (ICON_INSET + 2, ICON_INSET + 2, ICON_INSET + ICON_BODY - 2, ICON_INSET + ICON_BODY - 2))
    draw.rounded_rectangle(highlight_rect, radius=radius - scaled(2), outline=(255, 255, 255, 54), width=scaled(3))

    points = [
        (round(x * CANVAS / 96), round(y * CANVAS / 96))
        for x, y in [(19, 52), (32, 52), (39, 30), (52, 72), (61, 43), (77, 43)]
    ]
    shadow_offset = (round(1.25 * CANVAS / 96), round(1.6 * CANVAS / 96))
    shadow_points = [(x + shadow_offset[0], y + shadow_offset[1]) for x, y in points]
    shadow_mask = draw_polyline_mask(CANVAS, shadow_points, round(8.4 * CANVAS / 96))
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (11, 48, 104, 78))
    image.alpha_composite(Image.composite(shadow, Image.new("RGBA", (CANVAS, CANVAS)), shadow_mask))

    stroke_mask = draw_polyline_mask(CANVAS, points, round(7.2 * CANVAS / 96))
    stroke = Image.new("RGBA", (CANVAS, CANVAS), (255, 255, 255, 246))
    image.alpha_composite(Image.composite(stroke, Image.new("RGBA", (CANVAS, CANVAS)), stroke_mask))

    cx, cy, r = [round(v * CANVAS / 96) for v in (72, 24, 5.8)]
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, 248))

    image = image.resize((ICON_SIZE, ICON_SIZE), Image.Resampling.LANCZOS)
    image.save(BUILD / "icon.png")

    icons_dir = BUILD / "icons"
    icons_dir.mkdir(exist_ok=True)
    for size in (16, 24, 32, 48, 64, 128, 256, 512, 1024):
        image.resize((size, size), Image.Resampling.LANCZOS).save(icons_dir / f"{size}x{size}.png")

    image.save(BUILD / "icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "fund-pulse.iconset"
        iconset.mkdir()
        icon_sizes = {
            "icon_16x16.png": 16,
            "icon_16x16@2x.png": 32,
            "icon_32x32.png": 32,
            "icon_32x32@2x.png": 64,
            "icon_128x128.png": 128,
            "icon_128x128@2x.png": 256,
            "icon_256x256.png": 256,
            "icon_256x256@2x.png": 512,
            "icon_512x512.png": 512,
            "icon_512x512@2x.png": 1024,
        }
        for filename, size in icon_sizes.items():
            shutil.copyfile(icons_dir / f"{size}x{size}.png", iconset / filename)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(BUILD / "icon.icns")], check=True)


if __name__ == "__main__":
    main()
