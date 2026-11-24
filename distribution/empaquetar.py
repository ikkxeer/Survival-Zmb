"""Genera el ZIP de Windows desde una copia del proyecto y las plantillas oficiales."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.7.2.stable"
NAME = "LaUltimaVerbena"


def build(godot, destination):
    version = subprocess.check_output([godot, "--version"], text=True).strip()
    if not (version == VERSION or version.startswith(VERSION + ".")):
        raise SystemExit(f"Se necesita Godot {VERSION}. Versión detectada: {version}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([godot, "--headless", "--path", str(ROOT), "--import"], check=True)
    with tempfile.TemporaryDirectory() as staging:
        stage = Path(staging)
        executable = stage / (NAME + ".exe")
        subprocess.run(
            [godot, "--headless", "--path", str(ROOT), "--export-release",
             "Windows x64", str(executable)], check=True
        )
        data = executable.with_suffix(".pck")
        if not executable.is_file() or not data.is_file() or not data.stat().st_size:
            raise SystemExit("La exportación no generó el ejecutable y el paquete de datos.")
        # El exportador puede añadir bibliotecas según el renderizador configurado.
        files = [(p, p.relative_to(stage)) for p in sorted(stage.rglob("*")) if p.is_file()]
        dist = ROOT / "distribution"
        for p in [dist / "JUGAR.txt", *sorted((dist / "licencias").glob("*.txt"))]:
            files.append((p, p.relative_to(dist)))
        with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as tmp:
            archive = Path(tmp.name)
        try:
            with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
                for source, target in files:
                    bundle.write(source, (Path(NAME) / target).as_posix())
            with zipfile.ZipFile(archive) as bundle:
                if bundle.testzip() is not None:
                    raise SystemExit("Falló la verificación de integridad del ZIP.")
            os.replace(archive, destination)
        finally:
            archive.unlink(missing_ok=True)
    print(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Ruta al editor Godot estándar")
    parser.add_argument("--salida", type=Path, default=ROOT / "build" / (NAME + "-win64.zip"))
    args = parser.parse_args()
    build(args.godot, args.salida.resolve())
