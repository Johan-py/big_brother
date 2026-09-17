#!/usr/bin/env python3
"""
analiza.py - CLI que conecta con OpenRouter (DeepSeek u otro modelo) para
analizar archivos de reto CTF, con prompts especializados por categoría,
pre-análisis local (file/strings/exiftool) y escaneo rápido de flags.

Uso básico:
    OPENROUTER_API_KEY=sk-or-... ./analiza.py archivo1.txt archivo2.bin

Categoría específica (mejor prompt, más señal, menos ruido):
    ./analiza.py --cat web reto.js
    ./analiza.py --cat reversing --cat forense binario.elf imagen.pcap

Analizar un directorio completo (recursivo) del reto:
    ./analiza.py --cat crypto ./reto_crypto/

Guardar todo en un solo reporte:
    ./analiza.py --cat web -o reporte.md ./reto_web/

Solo escaneo local de flags, sin gastar tokens de API:
    ./analiza.py --scan-only ./reto/

Variables de entorno:
    OPENROUTER_API_KEY   (obligatoria salvo --scan-only)
    ANALIZA_MODEL        modelo por defecto
    ANALIZA_FLAG_REGEX   regex extra de flags separado por coma
"""

import argparse
import concurrent.futures
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import threading
import urllib.request
import urllib.error

# ---------------------------------------------------------------------------
# Entorno / constantes
# ---------------------------------------------------------------------------

def _load_env() -> None:
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
    if not os.path.isfile(path):
        return
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip())

API_URL = "https://openrouter.ai/api/v1/chat/completions"
DEFAULT_MODEL = os.environ.get("ANALIZA_MODEL", "deepseek/deepseek-chat")
MAX_WORKERS = int(os.environ.get("ANALIZA_WORKERS", "4"))

C_YELLOW = "\033[1;33m"
C_CYAN = "\033[1;36m"
C_GREEN = "\033[1;32m"
C_RED = "\033[1;31m"
C_DIM = "\033[2m"
C_RESET = "\033[0m"


class Spinner:
    """Animación de carga en loop mientras se procesan los archivos.

    Se dibuja en stderr con retorno de carro (\r) para no ensuciar stdout
    (que es donde van los resultados o el reporte). Cuando stderr no es un
    terminal (tubería/archivo), se desactiva sola.
    """
    FRAMES = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

    def __init__(self, total: int):
        self.total = total
        self.done = 0
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def _run(self) -> None:
        i = 0
        while not self._stop.is_set():
            frame = self.FRAMES[i % len(self.FRAMES)]
            text = f" {C_CYAN}{frame}{C_RESET}"
            if self.total:
                text += f" {C_DIM}{self.done}/{self.total}{C_RESET}"
            sys.stderr.write("\r" + text + " ")
            sys.stderr.flush()
            i += 1
            self._stop.wait(0.1)

    def start(self) -> None:
        if not sys.stderr.isatty():
            return
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def tick(self) -> None:
        self.done += 1

    def stop(self) -> None:
        if self._thread is None:
            return
        self._stop.set()
        self._thread.join(timeout=0.3)
        sys.stderr.write("\r" + " " * 20 + "\r")
        sys.stderr.flush()

# ---------------------------------------------------------------------------
# Prompts por categoría — mismas 7 categorías del README del equipo
# ---------------------------------------------------------------------------

BASE_RULES = """Eres un asistente de triage para retos de CTF. Sé directo,
técnico y accionable. No expliques teoría general salvo que sea clave para
el siguiente paso. Estructura SIEMPRE la respuesta así:

## Observaciones
(lo más relevante del archivo/output, en viñetas)

## Hipótesis
(qué tipo de vulnerabilidad/técnica es probable, ordenado por probabilidad)

## Próximos pasos
(comandos o herramientas concretas a correr a continuación, en orden)

## Flags / secretos detectados
(cualquier cosa con forma de flag: `algo{...}`, tokens, hashes sueltos,
credenciales. Si no hay nada, dilo explícitamente: "ninguno visible")
"""

CATEGORY_PROMPTS = {
    "crypto": BASE_RULES + """
Contexto: reto de Crypto. Presta atención a: encoding vs cifrado vs hashing,
Base64/32/58/85, hex, XOR, cifrados clásicos (César/ROT/Vigenère), RSA
(n, e, c, factores pequeños, exponente bajo, módulo común), AES (modo de
operación, IV, padding), longitudes/formatos de hash. Si ves números grandes,
trátalos como posible n/e/c de RSA y sugiere si aplica RsaCtfTool.
""",
    "web": BASE_RULES + """
Contexto: reto de Web. Presta atención a: rutas/parámetros sospechosos,
cookies, JWT, headers de auth, queries SQL, inputs reflejados (XSS/SSTI),
referencias a archivos (LFI/RFI/path traversal), objetos serializados,
comentarios HTML/JS con pistas, endpoints de API no documentados.
Si es código fuente (JS/PHP/Python/etc.), señala funciones de manejo de
input sin sanitizar y el flujo de datos hasta el sink.
""",
    "reversing": BASE_RULES + """
Contexto: reto de Reversing. Si el contenido es output de `file`, `strings`,
`objdump`, `readelf`, `checksec` o similar, interpreta: arquitectura, si
tiene protecciones (NX/PIE/canary/RELRO), funciones interesantes por nombre,
strings que parezcan claves/flags/comparaciones hardcodeadas, y si hay
lógica de validación de input (posible algoritmo a invertir). Sugiere el
siguiente comando exacto de Ghidra/GDB/pwndbg a correr.
""",
    "forense": BASE_RULES + """
Contexto: reto de Forense. Si es output de `exiftool`, `binwalk`, `tshark`,
o metadata de archivo, busca: metadata anómala, firmas de archivo embebido
(magic bytes que no matchean la extensión), streams de red sospechosos,
timestamps inconsistentes, y datos ocultos en EOF/slack space. Sugiere el
siguiente comando de extracción/carving concreto.
""",
    "osint": BASE_RULES + """
Contexto: reto de OSINT. Si el contenido es un username, email, imagen o
metadata, identifica pistas para correlacionar: nombres de usuario
reutilizables, dominios, coordenadas GPS en EXIF, referencias a redes
sociales, marcas de agua o texto visible en imágenes. Sugiere qué buscar
exactamente y en qué fuente (Wayback Machine, whois, redes específicas).
""",
    "stego": BASE_RULES + """
Contexto: reto de Esteganografía. Si es metadata de imagen/audio o strings
de un binario de imagen, busca: comentarios/campos de metadata inusuales,
diferencias de tamaño entre dimensiones declaradas y datos reales, canales
de color anómalos, cadenas de passphrase visibles, referencias a
herramientas de stego. Sugiere el comando exacto (steghide/zsteg/stegsolve)
y, si aplica, una lista corta de passphrases a probar con stegseek.
""",
    "misc": BASE_RULES + """
Contexto: reto de Misc — puede ser cualquier cosa (programación, trivia,
protocolo custom, lenguaje esotérico, encoding en capas, automatización).
Identifica primero si hay una capa de encoding reconocible (Base64/32/58/62/
85, hex, URL-encode, gzip/zlib) antes de asumir que es un algoritmo custom.
Si parece un mini-servicio (netcat/socket), describe el protocolo observado.
""",
}

DEFAULT_CATEGORY = "misc"

# ---------------------------------------------------------------------------
# Escaneo local de flags (gratis, antes de gastar tokens)
# ---------------------------------------------------------------------------

DEFAULT_FLAG_PATTERNS = [
    r"[a-zA-Z0-9_]{2,20}\{[^{}\s]{3,200}\}",   # flag{...}, picoCTF{...}, CTF{...}
    r"[A-Fa-f0-9]{32,64}",                      # hashes MD5/SHA sueltos
]

def build_flag_regex(extra: str | None):
    patterns = list(DEFAULT_FLAG_PATTERNS)
    if extra:
        patterns.extend(p.strip() for p in extra.split(",") if p.strip())
    return re.compile("|".join(f"(?:{p})" for p in patterns))

def scan_for_flags(text: str, regex) -> list[str]:
    hits = regex.findall(text) if isinstance(regex.findall(text), list) else []
    # findall con múltiples grupos puede devolver tuplas si hay grupos, así
    # que usamos finditer para quedarnos con el match completo siempre.
    return sorted({m.group(0) for m in regex.finditer(text)})

# ---------------------------------------------------------------------------
# Pre-análisis local: enriquecer el contenido antes de mandarlo al modelo
# ---------------------------------------------------------------------------

def run_cmd(cmd: list[str], timeout: int = 15) -> str:
    if shutil.which(cmd[0]) is None:
        return f"[{cmd[0]} no está instalado, se omite]"
    try:
        r = subprocess.run(cmd, capture_output=True, text=True,
                           timeout=timeout, errors="replace")
        return (r.stdout + r.stderr).strip()
    except subprocess.TimeoutExpired:
        return f"[{cmd[0]} excedió el timeout de {timeout}s]"
    except Exception as e:
        return f"[error corriendo {cmd[0]}: {e}]"

def is_probably_text(path: str) -> bool:
    mime, _ = mimetypes.guess_type(path)
    if mime and mime.startswith("text"):
        return True
    try:
        with open(path, "rb") as f:
            chunk = f.read(2048)
        if b"\x00" in chunk:
            return False
        chunk.decode("utf-8")
        return True
    except Exception:
        return False

def enrich_binary(path: str) -> str:
    """Para binarios: corre file/strings/exiftool y arma un bloque de contexto
    barato en vez de mandar el binario crudo (que gasta tokens inútilmente)."""
    parts = [f"[file]\n{run_cmd(['file', path])}"]
    parts.append(f"[strings -n 6 | head -100]\n" +
                 run_cmd(["bash", "-c", f"strings -n 6 -- {path!r} | head -100"]))
    if shutil.which("exiftool"):
        parts.append(f"[exiftool]\n{run_cmd(['exiftool', path])}")
    if shutil.which("checksec") and run_cmd(["file", path]).lower().find("elf") != -1:
        parts.append(f"[checksec]\n{run_cmd(['checksec', '--file=' + path])}")
    return "\n\n".join(parts)

def read_content(path: str, max_chars: int) -> str:
    if is_probably_text(path):
        try:
            with open(path, "rb") as f:
                raw = f.read(max_chars)
            return raw.decode("utf-8", errors="replace")
        except OSError as e:
            return f"[no se pudo leer: {e}]"
    else:
        return enrich_binary(path)

# ---------------------------------------------------------------------------
# Llamada a la API
# ---------------------------------------------------------------------------

def call_api(api_key: str, model: str, system_prompt: str, user_content: str,
             timeout: int, retries: int = 3) -> str:
    payload = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content},
        ],
    }).encode("utf-8")

    req = urllib.request.Request(
        API_URL,
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://github.com/",
            "X-Title": "analiza.py",
        },
        method="POST",
    )

    last_err = None
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            return data["choices"][0]["message"]["content"]
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            if e.code == 429 and attempt < retries:
                last_err = f"429 rate-limited, reintentando ({attempt}/{retries})..."
                print(f"{C_YELLOW}[warn]{C_RESET} {last_err}", file=sys.stderr)
                continue
            return f"[error API {e.code}]: {body}"
        except urllib.error.URLError as e:
            last_err = f"error de red: {e.reason}"
        except (KeyError, IndexError):
            return f"[respuesta inesperada de la API]: {json.dumps(data)}"
        except Exception as e:
            last_err = f"error inesperado: {e}"
    return f"[fallo tras {retries} intentos: {last_err}]"

# ---------------------------------------------------------------------------
# Procesamiento por archivo
# ---------------------------------------------------------------------------

def process_file(path: str, api_key: str | None, model: str, category: str,
                 max_chars: int, timeout: int, flag_regex, scan_only: bool):
    content = read_content(path, max_chars)
    local_flags = scan_for_flags(content, flag_regex)

    result_lines = [f"===== {path} ====="]
    if local_flags:
        result_lines.append(f"{C_GREEN}[flag local]{C_RESET} " +
                            ", ".join(local_flags))

    if scan_only:
        if not local_flags:
            result_lines.append(f"{C_DIM}(sin matches de flag locales){C_RESET}")
        return "\n".join(result_lines)

    system_prompt = CATEGORY_PROMPTS.get(category, CATEGORY_PROMPTS[DEFAULT_CATEGORY])
    user_content = f"Archivo: {path}\n\n{content}"
    analysis = call_api(api_key, model, system_prompt, user_content, timeout)
    result_lines.append(analysis)
    return "\n".join(result_lines)

def collect_files(paths: list[str]) -> list[str]:
    out = []
    for p in paths:
        if os.path.isdir(p):
            for root, _, files in os.walk(p):
                for fn in files:
                    out.append(os.path.join(root, fn))
        else:
            out.append(p)
    return out

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> None:
    _load_env()
    parser = argparse.ArgumentParser(
        description="Analiza archivos de reto CTF con DeepSeek vía OpenRouter, "
                    "con prompts especializados por categoría.")
    parser.add_argument("files", nargs="+",
                        help="archivos y/o directorios a analizar")
    parser.add_argument("--cat", "--category", dest="category",
                        choices=list(CATEGORY_PROMPTS.keys()),
                        default=DEFAULT_CATEGORY,
                        help=f"categoría del reto (default: {DEFAULT_CATEGORY})")
    parser.add_argument("--model", default=DEFAULT_MODEL,
                        help=f"modelo en OpenRouter (default: {DEFAULT_MODEL})")
    parser.add_argument("--prompt-file", help="override: prompt de sistema custom")
    parser.add_argument("--output", "-o", help="guardar el resultado en un archivo")
    parser.add_argument("--timeout", type=int, default=120,
                        help="timeout por petición en segundos")
    parser.add_argument("--max-chars", type=int, default=200_000,
                        help="máximo de caracteres a leer por archivo")
    parser.add_argument("--workers", type=int, default=MAX_WORKERS,
                        help="peticiones concurrentes a la API")
    parser.add_argument("--scan-only", action="store_true",
                        help="solo escaneo local de flags con regex, sin llamar a la API")
    parser.add_argument("--flag-regex", default=os.environ.get("ANALIZA_FLAG_REGEX"),
                        help="regex(es) extra de flag, separadas por coma")
    args = parser.parse_args()

    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key and not args.scan_only:
        print(f"{C_RED}[error]{C_RESET} falta OPENROUTER_API_KEY en el entorno "
              "(o usa --scan-only para saltarte la API)", file=sys.stderr)
        sys.exit(1)

    flag_regex = build_flag_regex(args.flag_regex)
    targets = collect_files(args.files)

    system_prompt_override = None
    if args.prompt_file:
        with open(args.prompt_file) as f:
            system_prompt_override = f.read()
        CATEGORY_PROMPTS[args.category] = system_prompt_override

    spinner = Spinner(len(targets))
    spinner.start()

    results = []
    try:
        if args.scan_only or args.workers <= 1:
            for t in targets:
                results.append(process_file(t, api_key, args.model, args.category,
                                            args.max_chars, args.timeout,
                                            flag_regex, args.scan_only))
                spinner.tick()
        else:
            with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
                futs = {
                    ex.submit(process_file, t, api_key, args.model, args.category,
                             args.max_chars, args.timeout, flag_regex,
                             args.scan_only): t
                    for t in targets
                }
                for _ in concurrent.futures.as_completed(futs):
                    spinner.tick()
                results = [fut.result() for fut in futs]
    finally:
        spinner.stop()

    output_text = "\n\n".join(results)

    if args.output:
        with open(args.output, "w") as f:
            f.write(output_text + "\n")
        print(f"{C_GREEN}[guardado en {args.output}]{C_RESET}")
    else:
        print(output_text)


if __name__ == "__main__":
    main()
