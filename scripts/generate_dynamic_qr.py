from pathlib import Path

from PIL import Image, ImageDraw
from reportlab.graphics import renderSVG
from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.graphics.shapes import Drawing


ROOT = Path(__file__).resolve().parents[1]
TARGET = "https://meridianblueorca.com/go/"
OUTPUT = ROOT / "assets" / "qr"


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    qr = QrCodeWidget(TARGET)
    x0, y0, x1, y1 = qr.getBounds()
    size = 1200
    scale = size / max(x1 - x0, y1 - y0)
    drawing = Drawing(size, size, transform=[scale, 0, 0, scale, 0, 0])
    drawing.add(qr)
    renderSVG.drawToFile(drawing, str(OUTPUT / "meridianblueorca-dynamic-qr.svg"))
    qr.qr.make()
    modules = qr.qr.modules
    quiet_zone = 4
    module_count = len(modules) + quiet_zone * 2
    box = size // module_count
    offset = (size - box * module_count) // 2 + quiet_zone * box
    image = Image.new("RGB", (size, size), "white")
    draw = ImageDraw.Draw(image)
    for row, values in enumerate(modules):
        for column, enabled in enumerate(values):
            if enabled:
                x = offset + column * box
                y = offset + row * box
                draw.rectangle((x, y, x + box - 1, y + box - 1), fill="black")
    image.save(OUTPUT / "meridianblueorca-dynamic-qr.png", dpi=(300, 300))


if __name__ == "__main__":
    main()
