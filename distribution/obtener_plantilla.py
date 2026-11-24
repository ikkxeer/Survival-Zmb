"""Descarga solo la plantilla de Windows x64 del paquete oficial de Godot 4.7.2
(1,2 GB) mediante peticiones por rangos y la instala donde la busca el editor.

    python distribution/obtener_plantilla.py

Útil en integración continua o en equipos sin el editor gráfico. El paquete
completo y su SHA-256 están en distribution/DISTRIBUCION.md.
"""
import hashlib
import os
import struct
import sys
import urllib.request
import zlib
from pathlib import Path

URL = "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
MEMBERS = ["templates/version.txt", "templates/windows_release_x86_64.exe"]


def fetch(start, end):
    req = urllib.request.Request(URL, headers={"Range": f"bytes={start}-{end}"})
    return urllib.request.urlopen(req).read()


def central_directory():
    size = int(urllib.request.urlopen(urllib.request.Request(URL, method="HEAD")).headers["Content-Length"])
    tail = fetch(size - 65536, size - 1)
    i = tail.rfind(b"PK\x05\x06")
    cd_size, cd_off = struct.unpack("<II", tail[i + 12:i + 20])
    if 0xFFFFFFFF in (cd_size, cd_off):
        j = tail.rfind(b"PK\x06\x07")
        rec_off = struct.unpack("<Q", tail[j + 8:j + 16])[0]
        cd_size, cd_off = struct.unpack("<QQ", fetch(rec_off, rec_off + 55)[40:56])
    return fetch(cd_off, cd_off + cd_size - 1)


def entries(cd):
    p, out = 0, {}
    while cd[p:p + 4] == b"PK\x01\x02":
        method, = struct.unpack("<H", cd[p + 10:p + 12])
        csize, usize = struct.unpack("<II", cd[p + 20:p + 28])
        nlen, elen, clen = struct.unpack("<HHH", cd[p + 28:p + 34])
        loff, = struct.unpack("<I", cd[p + 42:p + 46])
        name = cd[p + 46:p + 46 + nlen].decode()
        extra, q = cd[p + 46 + nlen:p + 46 + nlen + elen], 0
        while q < len(extra):
            hid, hlen = struct.unpack("<HH", extra[q:q + 4])
            if hid == 1:
                vals, k = extra[q + 4:q + 4 + hlen], 0
                for field in ("usize", "csize", "loff"):
                    if locals()[field] == 0xFFFFFFFF:
                        value, = struct.unpack("<Q", vals[k:k + 8])
                        k += 8
                        if field == "usize": usize = value
                        elif field == "csize": csize = value
                        else: loff = value
            q += 4 + hlen
        out[name] = (method, csize, usize, loff)
        p += 46 + nlen + elen + clen
    return out


def main():
    home = Path(os.environ.get("APPDATA") or Path.home() / ".local/share")
    target = home / ("Godot" if os.name == "nt" else "godot") / "export_templates" / "4.7.2.stable"
    target.mkdir(parents=True, exist_ok=True)
    table = entries(central_directory())
    for name in MEMBERS:
        method, csize, usize, loff = table[name]
        nlen, elen = struct.unpack("<HH", fetch(loff, loff + 29)[26:30])
        data = fetch(loff + 30 + nlen + elen, loff + 30 + nlen + elen + csize - 1)
        if method == 8:
            data = zlib.decompress(data, -15)
        if len(data) != usize:
            sys.exit(f"Tamaño inesperado en {name}")
        (target / Path(name).name).write_bytes(data)
        print(f"{name}: {usize} bytes, SHA-256 {hashlib.sha256(data).hexdigest()}")
    print(f"Plantilla instalada en {target}")


if __name__ == "__main__":
    main()
