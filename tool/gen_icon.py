#!/usr/bin/env python3
"""인프레임(In-Frame) 런처 아이콘 마스터 PNG 생성기.

글리프(파스텔 회색, 단색): 둥근 사각 **프레임**(화면) 안에 **재생 ▶ 삼각형**(영상 재생)과
하단 **자막 줄 2개**(아래가 더 짧음)를 함께 담아 '영상 재생 + 자막'을 표현한다.
바탕은 흰색 둥근 사각(플랫폼이 모서리 마스킹) — 첨부 형제 앱 패밀리 톤.

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
GLYPH = (150, 157, 168)  # #969DA8 파스텔 회색
WHITE = (255, 255, 255)

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")


# ---- 글리프 기하 (정사각 글리프 박스 크기 G, 중앙 cx/cy 기준) --------------------
def _geometry(size, glyph_frac):
    g = size * glyph_frac
    cx = cy = size / 2.0
    box_top = cy - g / 2.0
    box_left = cx - g / 2.0
    # 재생 삼각형(오른쪽 방향), 상단-중앙. 무게중심이 대략 가로 중앙에 오도록.
    tcy = box_top + g * 0.40
    th = g * 0.155  # 반높이
    tlx = cx - g * 0.12
    trx = cx + g * 0.17
    tri = [(tlx, tcy - th), (tlx, tcy + th), (trx, tcy)]
    return {
        "g": g,
        "frame": {
            "cx": cx,
            "cy": cy,
            "hx": g / 2.0,
            "hy": g / 2.0,
            "radius": g * 0.18,
            "stroke": g * 0.075,
        },
        "tri": tri,
        "bar_h": g * 0.075,
        # 자막 줄 2개(좌측 정렬, 박스 상단 기준 세로 위치, 폭).
        "bars": [
            (box_left + g * 0.22, box_top + g * 0.72, g * 0.56),
            (box_left + g * 0.22, box_top + g * 0.85, g * 0.38),
        ],
    }


# ===================== Pillow 경로 =====================
def _render_pillow(size, glyph_frac, transparent_bg):
    from PIL import Image, ImageDraw

    ss = 4
    s = size * ss
    geo = _geometry(s, glyph_frac)
    img = Image.new(
        "RGBA", (s, s), (0, 0, 0, 0) if transparent_bg else WHITE + (255,)
    )
    d = ImageDraw.Draw(img)

    f = geo["frame"]
    d.rounded_rectangle(
        [f["cx"] - f["hx"], f["cy"] - f["hy"], f["cx"] + f["hx"], f["cy"] + f["hy"]],
        radius=f["radius"],
        outline=GLYPH + (255,),
        width=int(round(f["stroke"])),
    )
    d.polygon(geo["tri"], fill=GLYPH + (255,))
    for bx, by, bw in geo["bars"]:
        bh = geo["bar_h"]
        d.rounded_rectangle(
            [bx, by - bh / 2, bx + bw, by + bh / 2], radius=bh / 2, fill=GLYPH + (255,)
        )
    return img.resize((size, size), Image.LANCZOS)


def _save_pillow(path, img):
    img.save(path, "PNG")


# ===================== 순수 표준 라이브러리 폴백 =====================
def _rrect_sdf(px, py, cx, cy, hx, hy, r):
    qx = abs(px - cx) - (hx - r)
    qy = abs(py - cy) - (hy - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def _in_tri(px, py, a, b, c):
    d1 = (px - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (py - b[1])
    d2 = (px - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (py - c[1])
    d3 = (px - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (py - a[1])
    neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (neg and pos)


def _render_stdlib(size, glyph_frac, transparent_bg):
    geo = _geometry(size, glyph_frac)
    f = geo["frame"]
    tri = geo["tri"]
    bars = [(bx + bw / 2, by, bw / 2, geo["bar_h"] / 2, geo["bar_h"] / 2)
            for bx, by, bw in geo["bars"]]

    ss = 3
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
                    inside = abs(
                        _rrect_sdf(px, py, f["cx"], f["cy"], f["hx"], f["hy"], f["radius"])
                    ) <= f["stroke"] / 2
                    if not inside and _in_tri(px, py, tri[0], tri[1], tri[2]):
                        inside = True
                    if not inside:
                        for (bcx, bcy, bhx, bhy, br) in bars:
                            if _rrect_sdf(px, py, bcx, bcy, bhx, bhy, br) <= 0:
                                inside = True
                                break
                    if inside:
                        hits += 1
            cov = hits / (ss * ss)
            o = row + x * 4
            if transparent_bg:
                buf[o], buf[o + 1], buf[o + 2] = GLYPH
                buf[o + 3] = int(round(cov * 255))
            else:
                buf[o] = int(round(GLYPH[0] * cov + WHITE[0] * (1 - cov)))
                buf[o + 1] = int(round(GLYPH[1] * cov + WHITE[1] * (1 - cov)))
                buf[o + 2] = int(round(GLYPH[2] * cov + WHITE[2] * (1 - cov)))
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
    with open(path, "wb") as fp:
        fp.write(b"\x89PNG\r\n\x1a\n")
        fp.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        fp.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        fp.write(chunk(b"IEND", b""))


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
