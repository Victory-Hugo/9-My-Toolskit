#!/usr/bin/env python3
import argparse
from pathlib import Path
from PIL import Image, ImageOps

A4_INCHES = (8.27, 11.69)


def a4_pixels(dpi):
    return (int(A4_INCHES[0] * dpi), int(A4_INCHES[1] * dpi))


def list_images(input_dir):
    exts = {".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp"}
    paths = [p for p in Path(input_dir).iterdir() if p.suffix.lower() in exts]
    return sorted(paths, key=lambda p: p.name.lower())


def open_image(path):
    img = Image.open(path)
    img = ImageOps.exif_transpose(img)
    if img.mode in ("RGBA", "LA"):
        bg = Image.new("RGB", img.size, (255, 255, 255))
        bg.paste(img, mask=img.split()[-1])
        return bg
    if img.mode != "RGB":
        img = img.convert("RGB")
    return img


def best_scale_for_cell(img_w, img_h, cell_w, cell_h, max_upscale, max_w_px, max_h_px):
    scale0 = min(cell_w / img_w, cell_h / img_h, max_w_px / img_w, max_h_px / img_h)
    if scale0 > max_upscale:
        scale0 = max_upscale
    area0 = (img_w * scale0) * (img_h * scale0)

    scale1 = min(cell_w / img_h, cell_h / img_w, max_w_px / img_h, max_h_px / img_w)
    if scale1 > max_upscale:
        scale1 = max_upscale
    area1 = (img_h * scale1) * (img_w * scale1)

    if area1 > area0:
        return scale1, True
    return scale0, False


def choose_grid(images_sizes, start_idx, remaining, page_w, page_h, margin, gap, max_upscale,
                max_w_px, max_h_px,
                max_cols=10, max_rows=10, min_cell=120):
    best = None
    for rows in range(1, max_rows + 1):
        for cols in range(1, max_cols + 1):
            cell_w = (page_w - 2 * margin - (cols - 1) * gap) / cols
            cell_h = (page_h - 2 * margin - (rows - 1) * gap) / rows
            if cell_w < min_cell or cell_h < min_cell:
                continue
            capacity = rows * cols
            count = min(remaining, capacity)
            used_area = 0.0
            for i in range(count):
                img_w, img_h = images_sizes[start_idx + i]
                scale, _ = best_scale_for_cell(
                    img_w,
                    img_h,
                    cell_w,
                    cell_h,
                    max_upscale,
                    max_w_px,
                    max_h_px,
                )
                used_area += (img_w * scale) * (img_h * scale)
            fill_ratio = used_area / (page_w * page_h)
            score = (fill_ratio, count)
            if best is None or score > best[0]:
                best = (score, rows, cols, cell_w, cell_h)
    if best is None:
        rows, cols = 1, 1
        cell_w = page_w - 2 * margin
        cell_h = page_h - 2 * margin
        return rows, cols, cell_w, cell_h
    return best[1], best[2], best[3], best[4]


def pack_images_to_pdf(
    input_dir,
    output_pdf,
    dpi=300,
    margin=0,
    gap=0,
    max_upscale=1.0,
    min_cell=120,
):
    images = list_images(input_dir)
    if not images:
        raise SystemExit("No images found in input directory.")

    images_sizes = []
    for p in images:
        with Image.open(p) as img:
            images_sizes.append(img.size)

    page_w, page_h = a4_pixels(dpi)
    px_per_cm = dpi / 2.54
    max_w_px = 10 * px_per_cm
    max_h_px = 15 * px_per_cm
    pages = []
    idx = 0

    while idx < len(images):
        remaining = len(images) - idx
        rows, cols, cell_w, cell_h = choose_grid(
            images_sizes, idx, remaining, page_w, page_h, margin, gap, max_upscale,
            max_w_px, max_h_px, min_cell=min_cell
        )
        page = Image.new("RGB", (page_w, page_h), (255, 255, 255))
        placed = 0

        for r in range(rows):
            for c in range(cols):
                if idx >= len(images):
                    break
                img = open_image(images[idx])
                scale, rotate = best_scale_for_cell(
                    img.width,
                    img.height,
                    cell_w,
                    cell_h,
                    max_upscale,
                    max_w_px,
                    max_h_px,
                )
                if rotate:
                    img = img.rotate(90, expand=True)
                new_w = max(1, int(img.width * scale))
                new_h = max(1, int(img.height * scale))
                resized = img.resize((new_w, new_h), Image.LANCZOS)

                cell_x = margin + c * (cell_w + gap)
                cell_y = margin + r * (cell_h + gap)

                if c < cols / 2:
                    x0 = int(cell_x)
                elif c > (cols - 1) / 2:
                    x0 = int(cell_x + (cell_w - new_w))
                else:
                    x0 = int(cell_x + (cell_w - new_w) / 2)

                if r < rows / 2:
                    y0 = int(cell_y)
                elif r > (rows - 1) / 2:
                    y0 = int(cell_y + (cell_h - new_h))
                else:
                    y0 = int(cell_y + (cell_h - new_h) / 2)
                page.paste(resized, (x0, y0))

                idx += 1
                placed += 1
            if idx >= len(images):
                break

        pages.append(page)
        if placed == 0:
            break

    pages[0].save(output_pdf, save_all=True, append_images=pages[1:], resolution=dpi)


def run(
    input_dir,
    output_pdf,
    dpi=300,
    margin=0,
    gap=0,
    max_upscale=1.0,
    min_cell=120,
):
    output_path = Path(output_pdf)
    if output_path.is_dir():
        output_path = output_path / "output_a4.pdf"
    pack_images_to_pdf(
        input_dir=input_dir,
        output_pdf=str(output_path),
        dpi=dpi,
        margin=margin,
        gap=gap,
        max_upscale=max_upscale,
        min_cell=min_cell,
    )
    return str(output_path)


def main():
    parser = argparse.ArgumentParser(
        description="Pack images into multi-page A4-sized PDF."
    )
    parser.add_argument("input_dir", help="Directory containing input images.")
    parser.add_argument("output_pdf", help="Output PDF file path.")
    parser.add_argument("--dpi", type=int, default=300, help="Output PDF DPI.")
    parser.add_argument("--margin", type=int, default=0, help="Page margin in pixels.")
    parser.add_argument("--gap", type=int, default=0, help="Gap between cells in pixels.")
    parser.add_argument(
        "--max-upscale",
        type=float,
        default=1.0,
        help="Maximum allowed upscale factor for images.",
    )
    parser.add_argument(
        "--min-cell",
        type=int,
        default=120,
        help="Minimum cell size in pixels for grid search.",
    )
    args = parser.parse_args()

    output_pdf = run(
        input_dir=args.input_dir,
        output_pdf=args.output_pdf,
        dpi=args.dpi,
        margin=args.margin,
        gap=args.gap,
        max_upscale=args.max_upscale,
        min_cell=args.min_cell,
    )
    print(f"Saved: {output_pdf}")


if __name__ == "__main__":
    main()
