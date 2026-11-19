"""Independent stdlib decoder for the pinned noninterlaced RGBA8 atlas PNG contract."""
import hashlib
import struct
import zlib

SIGNATURE = b"\x89PNG\r\n\x1a\n"


def need(condition, reason):
    if not condition:
        raise ValueError(reason)


def paeth(a, b, c):
    p = a + b - c
    x, y, z = abs(p - a), abs(p - b), abs(p - c)
    return a if x <= y and x <= z else (b if y <= z else c)


def rgba_digest(path, expected):
    data = path.read_bytes()
    need(len(data) <= 50_000_000 and data.startswith(SIGNATURE), "invalid atlas PNG")
    pos = 8
    pieces = []
    header = closed = ended = False
    while pos < len(data):
        need(pos + 12 <= len(data), "truncated PNG chunk")
        n, kind = struct.unpack_from(">I4s", data, pos)
        stop = pos + 8 + n
        need(stop + 4 <= len(data), "truncated PNG body")
        payload = data[pos+8:stop]
        need(zlib.crc32(kind + payload) == struct.unpack_from(">I", data, stop)[0], "PNG chunk CRC mismatch")
        pos = stop + 4
        if kind == b"IHDR":
            need(not header and pos == 33 and n == 13, "PNG header misplaced")
            w, h, depth, color, compression, filter_, interlace = struct.unpack(">IIBBBBB", payload)
            need((w,h) == expected and 0 < w <= 2000 and 0 < h <= 4000 and (depth,color,compression,filter_,interlace) == (8,6,0,0,0), "unsupported atlas PNG dimensions or mode")
            header = True
        elif kind == b"IDAT":
            need(header and not closed, "PNG IDAT misplaced")
            pieces.append(payload)
        elif kind == b"IEND":
            need(header and pieces and n == 0 and pos == len(data), "PNG IEND misplaced")
            ended = True
            break
        else:
            need(header and kind.isalpha() and kind[0] & 32 and kind not in (b"acTL", b"fcTL", b"fdAT"), "unsupported critical or animated PNG")
            if pieces:
                closed = True
    need(ended, "incomplete PNG")
    stride = w * 4
    count = h * (stride + 1)
    inflate = zlib.decompressobj()
    raw = inflate.decompress(b"".join(pieces), count + 1)
    need(len(raw) == count and inflate.eof and not inflate.unused_data and not inflate.unconsumed_tail, "PNG inflate length mismatch")
    digest = hashlib.sha256()
    above = bytearray(stride)
    for y in range(h):
        offset = y * (stride + 1)
        typ = raw[offset]
        row = bytearray(raw[offset+1:offset+1+stride])
        if typ == 1:
            for i in range(4,stride):
                row[i] = (row[i] + row[i-4]) & 255
        elif typ == 2:
            row = bytearray((x + b) & 255 for x,b in zip(row,above))
        elif typ == 3:
            for i in range(stride):
                row[i] = (row[i] + (((row[i-4] if i >= 4 else 0) + above[i]) >> 1)) & 255
        elif typ == 4:
            for i in range(stride):
                a,c = (row[i-4], above[i-4]) if i >= 4 else (0,0)
                row[i] = (row[i] + paeth(a,above[i],c)) & 255
        else:
            need(typ == 0, "invalid PNG row filter")
        digest.update(row)
        above = row
    return (w,h), digest.hexdigest()
