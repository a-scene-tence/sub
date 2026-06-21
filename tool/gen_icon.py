#!/usr/bin/env python3
"""인프레임(In-Frame) 런처 아이콘 마스터 PNG 생성기.

자막 프레임 글리프: 둥근 사각 프레임 외곽선 + 내부 하단 자막 줄 2개(아래가 더 짧음).
색은 파스텔 인디고, 바탕은 흰색 둥근 사각(플랫폼이 모서리 마스킹).

생성물:
  assets/icon/in_frame.png     1024 불투명 흰 바탕 + 글리프(캔버스 ~58%)  → iOS·Android 레거시
  assets/icon/in_frame_fg.png  1024 투명 바탕 + 글리프(~42%, 어댑티브 안전영역) → Android foreground

Pillow가 있으면 사용(슈퍼샘플링), 없으면 순수 표준 라이브러리 SDF 래스터라이저로 폴백.
이후 `dart run flutter_launcher_icons`가 각 플랫폼 크기로 펼친다.
"""
import math
import os
import struct
import zlib

SIZE = 1024
INDIGO = (124, 133, 240)  # #7C85F0 파스텔 인디고
WHITE = (255, 255, 255)

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")


# ---- 글리프 기하 (정사각 글리프 박스 크기 G, 중앙 cx/cy 기준) --------------------
def _geometry(size, glyph_frac):
    g = size * glyph_frac
    cx = cy = size / 2.0
    box_top = cy - g / 2.0
    box_left = cx - g / 2.0
    return {
        "g": g,
        "cx": cx,
        "cy": cy,
        "hx": g / 2.0,
        "hy": g / 2.0,
        "radius": g * 0.18,
        "stroke": g * 0.088,
        "bar_h": g * 0.088,
        # 자막 줄 2개(박스 상단 기준 세로 위치, 좌측 정렬 폭).
        "top_bar": (box_left + g * 0.20, box_top + g * 0.60, g * 0.58),
        "bot_bar": (box_left + g * 0.20, box_top + g * 0.77, g * 0.40),
    }


# ===================== Pillow 경로 =====================
def _render_pillow(size, glyph_frac, transparent_bg):
    from PIL import Image, ImageDraw

    ss = 4
    s = size * ss
    geo = _geometry(s, glyph_frac)
    if transparent_bg:
        img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    else:
        img = Image.new("RGBA", (s, s), WHITE + (255,))
    d = ImageDraw.Draw(img)

    cx, cy, hx, hy = geo["cx"], geo["cy"], geo["hx"], geo["hy"]
    r, w = geo["radius"], geo["stroke"]
    # 프레임 외곽선.
    d.rounded_rectangle(
        [cx - hx, cy - hy, cx + hx, cy + hy],
        radius=r,
        outline=INDIGO + (255,),
        width=int(round(w)),
    )
    # 자막 줄.
    for bx, by, bw in (geo["top_bar"], geo["bot_bar"]):
        bh = geo["bar_h"]
        d.rounded_rectangle(
            [bx, by - bh / 2, bx + bw, by + bh / 2],
            radius=bh / 2,
            fill=INDIGO + (255,),
        )
    return img.resize((size, size), Image.LANCZOS)


def _save_pillow(path, img):
    img.save(path, "PNG")


# ===================== 순수 표준 라이브러리 폴백 =====================
def _rrect_sdf(px, py, cx, cy, hx, hy, r):
    qx = abs(px - cx) - (hx - r)
    qy = abs(py - cy) - (hy - r)
    ox = max(qx, 0.0)
    oy = max(qy, 0.0)
    return math.hypot(ox, oy) + min(max(qx, qy), 0.0) - r


def _render_stdlib(size, glyph_frac, transparent_bg):
    geo = _geometry(size, glyph_frac)
    cx, cy, hx, hy = geo["cx"], geo["cy"], geo["hx"], geo["hy"]
    r, w = geo["radius"], geo["stroke"]
    bars = []
    for bx, by, bw in (geo["top_bar"], geo["bot_bar"]):
        bh = geo["bar_h"]
        bars.append((bx + bw / 2, by, bw / 2, bh / 2, bh / 2))  # center-based rrect

    ss = 3  # 슈퍼샘플(3x3=9 서브픽셀).
    inv = 1.0 / ss
    buf = bytearray(size * size * 4)
    for y in range(size):
        row = y * size * 4
        for x in range(size):
            hits = 0
            for sy in range(ss):
                py = y + (sy + 0.5) * inv
                for sx in range(ss):
                    px = x + (sx + 0.5) * inv
                    inside = False
                    # 프레임 외곽선: |sdf| <= stroke/2.
                    if abs(_rrect_sdf(px, py, cx, cy, hx, hy, r)) <= w / 2:
                        inside = True
                    else:
                        for (bcx, bcy, bhx, bhy, br) in bars:
                            if _rrect_sdf(px, py, bcx, bcy, bhx, bhy, br) <= 0:
                                inside = True
                                break
                    if inside:
                        hits += 1
            cov = hits / (ss * ss)
            o = row + x * 4
            if transparent_bg:
                buf[o] = INDIGO[0]
                buf[o + 1] = INDIGO[1]
                buf[o + 2] = INDIGO[2]
                buf[o + 3] = int(round(cov * 255))
            else:
                buf[o] = int(round(INDIGO[0] * cov + WHITE[0] * (1 - cov)))
                buf[o + 1] = int(round(INDIGO[1] * cov + WHITE[1] * (1 - cov)))
                buf[o + 2] = int(round(INDIGO[2] * cov + WHITE[2] * (1 - cov)))
                buf[o + 3] = 255
    return buf


def _write_png(path, w, h, rgba):
    def chunk(typ, data):
        return (
            struct.pack(">I", len(data))
            + typ
            + data
            + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)
        )

    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += rgba[y * stride : (y + 1) * stride]
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


# ===================== 엔트리 =====================
def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    targets = [
        ("in_frame.png", 0.58, False),
        ("in_frame_fg.png", 0.42, True),
    ]
    use_pillow = True
    try:
        import PIL  # noqa: F401
    except Exception:
        use_pillow = False

    for name, frac, transparent in targets:
        path = os.path.normpath(os.path.join(OUT_DIR, name))
        if use_pillow:
            _save_pillow(path, _render_pillow(SIZE, frac, transparent))
        else:
            _write_png(path, SIZE, SIZE, _render_stdlib(SIZE, frac, transparent))
        print(f"wrote {path} ({'Pillow' if use_pillow else 'stdlib'})")


if __name__ == "__main__":
    main()
