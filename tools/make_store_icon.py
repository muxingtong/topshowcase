#!/usr/bin/env python3
"""
从分层图标合成应用市场（AGC）提交用的直角图标。

背景：HarmonyOS 的应用图标是「分层图标」——background.png（底）+ foreground.png（主体），
由系统在设备上叠合并自适形形状。但 AGC 上架要的是**非分层的直角图标**，
需要自己把两层合成一张交出去。

本机没有 PIL / ImageMagick，所以这里用标准库（zlib + struct）自己解 PNG、合成、再编码。

另外做了一件规范要求、但原始素材没做到的事：**裁掉前景多余的留白**。
官方要求前景图「禁止自行添加内边距」，而现有 foreground.png 主体只占 43%、
四周留白 28% —— 直接合出来的图标会显得很小。这里按主体外接框重新取景，
让主体占到画布的 FILL_RATIO。

用法：
    python3 tools/make_store_icon.py
输出（写到 store-icon/）：
    app_icon_1024.png    1024×1024，直角，主提交件
    app_icon_216.png     216×216，直角，备选尺寸
"""
import struct
import zlib
import os

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG_PATH = os.path.join(APP_DIR, 'AppScope/resources/base/media/background.png')
FG_PATH = os.path.join(APP_DIR, 'AppScope/resources/base/media/foreground.png')
OUT_DIR = os.path.join(APP_DIR, 'store-icon')

# 主体在成图里占的比例。太小显得空，太大贴边——0.6 是图标主体的通行值
FILL_RATIO = 0.60
# alpha 超过它才算「主体像素」，用来算外接框；避免把极淡的柔边算进去
ALPHA_FLOOR = 16


# ---------------------------------------------------------------- PNG 解码

def decode_png(path):
    """解 8bit / RGBA / 非交织的 PNG，返回 (w, h, bytearray(RGBA))。"""
    data = open(path, 'rb').read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError(f'{path} 不是 PNG')
    i = 8
    idat = b''
    w = h = 0
    while i < len(data):
        ln = struct.unpack('>I', data[i:i + 4])[0]
        typ = data[i + 4:i + 8]
        payload = data[i + 8:i + 8 + ln]
        if typ == b'IHDR':
            w, h, bd, ct, _, _, inter = struct.unpack('>IIBBBBB', payload)
            if bd != 8 or ct != 6 or inter != 0:
                raise ValueError(f'{path} 需要 8bit/RGBA/非交织，实际 bd={bd} ct={ct} inter={inter}')
        elif typ == b'IDAT':
            idat += payload
        elif typ == b'IEND':
            break
        i += 12 + ln

    raw = zlib.decompress(idat)
    stride = w * 4
    out = bytearray(w * h * 4)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        ft = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if ft == 1:
            for x in range(4, stride):
                line[x] = (line[x] + line[x - 4]) & 255
        elif ft == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif ft == 3:
            for x in range(stride):
                a = line[x - 4] if x >= 4 else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif ft == 4:
            for x in range(stride):
                a = line[x - 4] if x >= 4 else 0
                b = prev[x]
                c = prev[x - 4] if x >= 4 else 0
                pa = abs(b - c)
                pb = abs(a - c)
                pc = abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, out


# ---------------------------------------------------------------- PNG 编码

def encode_png(w, h, rgba, path):
    """把 RGBA 字节写成 PNG（8bit / 真彩+Alpha）。每行滤波字节用 0（None）。"""
    stride = w * 4
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(typ, payload):
        return (struct.pack('>I', len(payload)) + typ + payload
                + struct.pack('>I', zlib.crc32(typ + payload) & 0xffffffff))

    body = (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
            + chunk(b'IEND', b''))
    open(path, 'wb').write(body)
    return len(body)


# ---------------------------------------------------------------- 处理

def bbox_of_alpha(w, h, rgba, floor=ALPHA_FLOOR):
    """主体（alpha 明显不为 0）的外接框。"""
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        row = y * w * 4
        for x in range(w):
            if rgba[row + x * 4 + 3] > floor:
                if x < minx: minx = x
                if x > maxx: maxx = x
                if y < miny: miny = y
                if y > maxy: maxy = y
    return minx, miny, maxx, maxy


def compose_over(bg, fg, n):
    """fg over bg 的 alpha 合成（源覆盖）。两者都是 RGBA 字节。"""
    out = bytearray(n * 4)
    for i in range(n):
        o = i * 4
        sa = fg[o + 3]
        if sa == 0:
            out[o] = bg[o]; out[o + 1] = bg[o + 1]; out[o + 2] = bg[o + 2]; out[o + 3] = bg[o + 3]
        elif sa == 255:
            out[o] = fg[o]; out[o + 1] = fg[o + 1]; out[o + 2] = fg[o + 2]; out[o + 3] = 255
        else:
            ia = 255 - sa
            da = bg[o + 3]
            oa = sa + da * ia // 255
            out[o] = (fg[o] * sa + bg[o] * da * ia // 255) // oa if oa else 0
            out[o + 1] = (fg[o + 1] * sa + bg[o + 1] * da * ia // 255) // oa if oa else 0
            out[o + 2] = (fg[o + 2] * sa + bg[o + 2] * da * ia // 255) // oa if oa else 0
            out[o + 3] = oa
    return out


def crop_square(w, h, rgba, cx, cy, side):
    """以 (cx,cy) 为中心取 side×side 的正方形；越界处用边缘像素补齐。"""
    out = bytearray(side * side * 4)
    x0 = cx - side // 2
    y0 = cy - side // 2
    for y in range(side):
        sy = y0 + y
        if sy < 0: sy = 0
        if sy > h - 1: sy = h - 1
        srow = sy * w * 4
        drow = y * side * 4
        for x in range(side):
            sx = x0 + x
            if sx < 0: sx = 0
            if sx > w - 1: sx = w - 1
            s = srow + sx * 4
            d = drow + x * 4
            out[d] = rgba[s]; out[d + 1] = rgba[s + 1]
            out[d + 2] = rgba[s + 2]; out[d + 3] = rgba[s + 3]
    return out


def resize_box(w, h, rgba, nw, nh):
    """面积平均缩放。图标是大面积色块，面积平均比最近邻干净得多。"""
    out = bytearray(nw * nh * 4)
    xr = w / nw
    yr = h / nh
    for y in range(nh):
        y0 = int(y * yr)
        y1 = max(y0 + 1, int((y + 1) * yr))
        for x in range(nw):
            x0 = int(x * xr)
            x1 = max(x0 + 1, int((x + 1) * xr))
            r = g = b = a = 0
            cnt = 0
            for sy in range(y0, min(y1, h)):
                row = sy * w * 4
                for sx in range(x0, min(x1, w)):
                    s = row + sx * 4
                    r += rgba[s]; g += rgba[s + 1]; b += rgba[s + 2]; a += rgba[s + 3]
                    cnt += 1
            d = (y * nw + x) * 4
            if cnt == 0:
                cnt = 1
            out[d] = r // cnt; out[d + 1] = g // cnt
            out[d + 2] = b // cnt; out[d + 3] = a // cnt
    return out


def main():
    print('读入分层图标…')
    bw, bh, bg = decode_png(BG_PATH)
    fw, fh, fg = decode_png(FG_PATH)
    print(f'  background {bw}x{bh}   foreground {fw}x{fh}')
    if (bw, bh) != (fw, fh):
        raise SystemExit('两层尺寸不一致，无法合成')

    print('合成两层…')
    flat = compose_over(bg, fg, bw * bh)

    print('测主体外接框…')
    minx, miny, maxx, maxy = bbox_of_alpha(bw, bh, fg)
    body_w = maxx - minx + 1
    body_h = maxy - miny + 1
    cx = (minx + maxx) // 2
    cy = (miny + maxy) // 2
    print(f'  主体 {body_w}x{body_h}，中心 ({cx},{cy})，'
          f'占画布 {body_w * 100 // bw}%')

    # 取景边长：让主体占到 FILL_RATIO
    side = int(max(body_w, body_h) / FILL_RATIO)
    if side > bw:
        side = bw
    print(f'  取景 {side}x{side}（主体将占 {FILL_RATIO * 100:.0f}%）')

    framed = crop_square(bw, bh, flat, cx, cy, side)

    os.makedirs(OUT_DIR, exist_ok=True)
    outputs = [(1024, 'app_icon_1024.png'), (216, 'app_icon_216.png')]
    for size, name in outputs:
        px = framed if size == side else resize_box(side, side, framed, size, size)
        path = os.path.join(OUT_DIR, name)
        n = encode_png(size, size, px, path)
        print(f'  写出 {name}  {size}x{size}  {n / 1024:.1f} KB  '
              f'{"✓ 在 3MB 内" if n < 3 * 1024 * 1024 else "✗ 超标"}')


if __name__ == '__main__':
    main()
