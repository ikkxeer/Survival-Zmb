"""Plays a three-night session with an ENet host and three bot clients and checks
that every process agrees on the final state.

    python tests/run_session.py [--godot godot] [--noches 3] [--jugadores 1|2|4]

With four players one client adds 150 ms of simulated latency and another
leaves during night 2. With two, the only client has the latency.
"""
import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def launch(godot, extra):
    cmd = [godot, "--headless", "--path", str(ROOT), "-s", "tests/session_test.gd", "--"] + extra
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--noches", type=int, default=3)
    parser.add_argument("--jugadores", type=int, default=4, choices=[1, 2, 4])
    args = parser.parse_args()
    nights = f"--noches={args.noches}"
    procs = {"anfitrión": launch(args.godot, ["--host", nights])}
    time.sleep(3)
    if args.jugadores == 4:
        procs["cliente"] = launch(args.godot, [nights])
    if args.jugadores >= 2:
        procs["cliente con 150 ms"] = launch(args.godot, [nights, "--latencia=150"])
    if args.jugadores == 4:
        procs["cliente que sale"] = launch(args.godot, [nights, "--salir-noche=2"])
    results, ok = {}, True
    for name, proc in procs.items():
        out, _ = proc.communicate(timeout=1200)
        lines = [l for l in out.splitlines() if l.startswith(("RESUMEN", "SALIDA", "ERROR", "SCRIPT ERROR"))]
        for l in lines:
            print(f"[{name}] {l}")
        for l in lines:
            if l.startswith("RESUMEN"):
                results[name] = json.loads(l[len("RESUMEN "):])
            if l.startswith(("ERROR", "SCRIPT ERROR")):
                ok = False
        if proc.returncode != 0:
            print(f"[{name}] terminó con código {proc.returncode}")
            ok = False
    if "cliente que sale" in results:
        print("El cliente que debía salir llegó al final")
        ok = False
    host = results.get("anfitrión")
    if host is None:
        print("El anfitrión no llegó al resumen")
        sys.exit(1)
    for name in [n for n in ("cliente", "cliente con 150 ms") if n in procs]:
        other = results.get(name)
        if other is None:
            print(f"{name}: sin resumen")
            ok = False
            continue
        for key in ("noche", "fase", "materiales", "defensas", "jugadores", "fichas"):
            if other[key] != host[key]:
                print(f"{name}: '{key}' diverge ({other[key]} frente a {host[key]})")
                ok = False
        if abs(other["casa"] - host["casa"]) > 0.5:
            print(f"{name}: la vida de la casa diverge ({other['casa']} frente a {host['casa']})")
            ok = False
    print("Sesión coherente en todos los procesos" if ok else "Se detectaron problemas")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
