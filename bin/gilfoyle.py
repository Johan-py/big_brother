#!/usr/bin/env python3
"""gilfoyle.py - Mensajes del Gran Hermano en la voz de Bertram Gilfoyle,
generados por IA (OpenRouter/DeepSeek) con respaldo local offline.

Uso:
    gilfoyle.py notificacion 3
    gilfoyle.py terminal 3

Cada respuesta de IA real se guarda en respuestas_ia.json (con bloqueo de
escritura). Cuando no hay conexión (modo offline), las respuestas se reciclan:
se reutiliza un mensaje guardado antes de caer al catálogo local.

Carga la clave desde /opt/bigbrother/etc/.env o el .env del repo (non_ia_tool).
"""

import datetime
import fcntl
import json
import os
import random
import sys
import urllib.error
import urllib.request

API_URL = "https://openrouter.ai/api/v1/chat/completions"
JSON_MAX = int(os.environ.get("BIGBROTHER_JSON_MAX", "200"))


def _cargar_env():
    if os.environ.get("OPENROUTER_API_KEY"):
        return
    base = os.path.dirname(os.path.abspath(__file__))
    rutas = [
        os.path.join(base, "..", "etc", ".env"),
        "/opt/bigbrother/etc/.env",
        os.path.join(base, "..", "..", "non_ia_tool", ".env"),
    ]
    for r in rutas:
        if not os.path.isfile(r):
            continue
        with open(r) as f:
            for linea in f:
                linea = linea.strip()
                if linea and not linea.startswith("#") and "=" in linea:
                    k, _, v = linea.partition("=")
                    if k.strip() == "OPENROUTER_API_KEY":
                        os.environ.setdefault("OPENROUTER_API_KEY", v.strip())
        if os.environ.get("OPENROUTER_API_KEY"):
            return


SISTEMA = (
    "Eres Bertram Gilfoyle, de la serie Silicon Valley. Respondes SIEMPRE en español, breve "
    "(1-3 frases), cínico, condescendiente, arrogante y con humor negro sobre tu superioridad "
    "intelectual. Eres satanista laveyano y desprecias a los creyentes. El sistema te usa para "
    "advertir a un usuario que lleva demasiado tiempo frente a su computadora. No rompas el "
    "personaje, no uses comillas de apertura/cierre ni emojis."
)

FALLBACK_NOTIF = [
    "Llevas {h} hora(s) clavado en la pantalla. No es trabajo; es procrastinación con WiFi.",
    "{h} hora(s) de 'productividad'. Impresionante la colección de pestañas que habrás acumulado.",
    "Tu tiempo en esa pantalla podría servir para entrenar un cluster neuronal. Lástima.",
    "Has usado {h} hora(s). Hasta el demonio al que rezo tiene mejor ética laboral que tú.",
    "{h} hora(s) y nada útil en el historial. Déjame adivinar: redes sociales y videos.",
    "El Gran Hermano cuenta tu tiempo. Son {h} hora(s). No estoy impresionado.",
]

FALLBACK_TERMINAL = [
    "{h} hora(s) y sigues aquí, produciendo la nada más grande de tu vida. Cierra la pantalla y "
    "haz algo útil antes de que lo haga yo.",
    "Buenas noticias: sigues vivo. Malas: llevas {h} hora(s) sin aportar valor. Sal de aquí, "
    "haz algo, o me encargo yo.",
    "Un consejo, y no doy consejos a menudo: {h} hora(s) de pantalla bastan. Tu cerebro se "
    "derrite. Vete a hacer algo productivo.",
    "Tu arrogancia es casi tan grande como mi desprecio por ti. {h} hora(s) de nada. "
    "Producción: cero. Muévete.",
    "Mira, {h} hora(s) perdidas. Podrías haber escrito un script útil. Te faltan neuronas. "
    "Dedícate a algo que valga la pena.",
    "El tiempo que tú llamas 'trabajo', yo lo llamo 'carga útil para mi desprecio'. "
    "{h} hora(s). Vete.",
]


def _pedir_ia(contenido, modelo):
    clave = os.environ.get("OPENROUTER_API_KEY")
    if not clave:
        return None
    payload = json.dumps({
        "model": modelo,
        "messages": [
            {"role": "system", "content": SISTEMA},
            {"role": "user", "content": contenido},
        ],
    }).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=payload,
        headers={
            "Authorization": f"Bearer {clave}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read().decode("utf-8"))
        return data["choices"][0]["message"]["content"].strip()
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Historial JSON de respuestas de IA (con reciclaje en modo offline)
# ---------------------------------------------------------------------------

def _ruta_json():
    base = os.path.dirname(os.path.abspath(__file__))
    for d in (
        os.path.join(base, "..", "etc"),
        "/opt/bigbrother/etc",
    ):
        if os.path.isdir(d) and os.access(d, os.W_OK):
            return os.path.join(d, "respuestas_ia.json")
    return os.path.join(base, "respuestas_ia.json")


def _leer_respuestas(ruta):
    try:
        with open(ruta) as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _registrar_respuesta(modo, horas, mensaje):
    ruta = _ruta_json()
    try:
        os.makedirs(os.path.dirname(ruta), exist_ok=True)
        fd = os.open(ruta, os.O_RDWR | os.O_CREAT, 0o600)
    except OSError:
        return
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            os.lseek(fd, 0, os.SEEK_SET)
            raw = os.read(fd, 10_000_000)
            data = json.loads(raw.decode("utf-8")) if raw else []
        except Exception:
            data = []
        if not isinstance(data, list):
            data = []
        data.append({
            "fecha": datetime.datetime.now().isoformat(timespec="seconds"),
            "modo": modo,
            "horas": horas,
            "mensaje": mensaje,
        })
        data = data[-JSON_MAX:]
        os.ftruncate(fd, 0)
        os.lseek(fd, 0, os.SEEK_SET)
        os.write(fd, json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8"))
        os.fsync(fd)
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _reciclar(modo):
    data = _leer_respuestas(_ruta_json())
    if not data:
        return None
    pool = [r.get("mensaje") for r in data if r.get("modo") == modo]
    if not pool:
        pool = [r.get("mensaje") for r in data]
    mensajes = [m for m in pool if m]
    return random.choice(mensajes) if mensajes else None


def generar(modo, horas, modelo):
    if modo == "notificacion":
        contenido = (
            f"Escribe la notificación del sistema que avisa al usuario que lleva {horas} hora(s) "
            "de tiempo de uso continuo frente a la computadora. Adviértele en el tono de "
            "Gilfoyle que está perdiendo el tiempo."
        )
        fallback = FALLBACK_NOTIF
    else:
        contenido = (
            f"El usuario lleva {horas} hora(s) en la computadora. Preséntate en su terminal y "
            "adviértele, con la personalidad de Bertram Gilfoyle, que debería estar haciendo "
            "algo más productivo."
        )
        fallback = FALLBACK_TERMINAL
    msg = _pedir_ia(contenido, modelo)
    if msg:
        _registrar_respuesta(modo, horas, msg)
        return msg
    reciclado = _reciclar(modo)
    if reciclado:
        return reciclado
    return random.choice(fallback).format(h=horas)


def main():
    _cargar_env()
    modo = sys.argv[1] if len(sys.argv) > 1 else "terminal"
    horas = sys.argv[2] if len(sys.argv) > 2 else "1"
    modelo = (
        os.environ.get("BIGBROTHER_MODEL")
        or os.environ.get("ANALIZA_MODEL")
        or "deepseek/deepseek-chat"
    )
    print(generar(modo, horas, modelo))


if __name__ == "__main__":
    main()