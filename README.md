# 👁 GRAN HERMANO (minimal)

Sistema de *"locked mode"* voluntario para **Arch Linux**, reducido a su mínima expresión:
vigila el tiempo de sesión gráfica y, cada hora de uso, altera tu entorno con la voz de
**Bertram Gilfoyle** (mensajes escritos por IA) y una travesura aleatoria.

> Basado en la idea de *1984*, pero sin drama: no toca BIOS, no te reinstala, no te retiene.
> Es un compromiso contigo mismo: el miedo es psicológico, no criptográfico.

---

## ⏱ El ciclo

```
hora de sesión cumplida
        │
        ├─ 0 s    ── Notificación escrita por IA (voz de Gilfoyle)
        ├─ 10 s   ── Se abre una terminal: la IA te advierte que deberías
        │            estar haciendo algo más productivo (efecto teletipo)
        └─ 5 min  ── Se ejecuta UNA travesura aleatoria:
                       🔌1. Apagar el computador
                       🎵2. Reproducir una música aleatoria
                       💻3. Terminal de "hackeo" falso a lo película
```

El ciclo se repite cada hora nueva de uso acumulado (`INTERVALO_HORAS`). Se reinicia cada día.

## 📁 Arquitectura

```
/opt/bigbrother/
├── bin/
│   ├── surveillance.sh     Servicio systemd: mide tiempo y dispara el ciclo
│   ├── gilfoyle.py         Genera los mensajes con IA (OpenRouter/DeepSeek)
│   ├── travesuras.sh       Selecciona y ejecuta la travesura aleatoria
│   ├── mostrar_aviso.sh    Abre la terminal y escribe el aviso con teletipo
│   ├── fake_hack.sh        El "hackeo" simulado de colores y barras
│   ├── time_control.sh     Contador diario de segundos de sesión
│   └── lib.sh              Funciones compartidas (notify, terminal, sesión)
├── etc/
│   ├── config.conf         Configuración del watcher
│   ├── .env                OPENROUTER_API_KEY (solo root)
│   ├── usuarios.db         Cuenta vigilada + consentimiento
│   ├── registros.db        Registro plano de eventos
│   └── frase_liberacion    Frase para desinstalar (solo root)
└── bin/gilfoyle.py etc.
```

## 🧠 Los mensajes de IA

`gilfoyle.py` pide a un modelo de OpenRouter (por defecto `deepseek/deepseek-chat`) que escriba
el mensaje encarnando a **Bertram Gilfoyle**: cínico, condescendiente, satanista laveyano y en
español.

- La clave se toma de `non_ia_tool/.env` en el repositorio (o se pide durante la instalación)
  y se guarda en `/opt/bigbrother/etc/.env` con permisos `600`.
- **Cada respuesta real de la IA se guarda** en `/opt/bigbrother/etc/respuestas_ia.json`
  (historial con fecha, modo y horas; se recorta al máximo `BIGBROTHER_JSON_MAX`, 200 por defecto).
- Si la API falla (offline, rate-limit, sin clave...), el sistema **recicla**: reutiliza una
  respuesta guardada en el JSON (prefiriendo el mismo modo) antes de caer al catálogo local.
  El flujo nunca se detiene.

## 💥 La travesura (una de estas, al azar)

| # | Travesura | Detalle |
|---|---|---|
| 1 | **Apagar** | Avisa y programa `shutdown -h +1` (cancelable con `shutdown -c`) |
| 2 | **Música** | Busca un archivo aleatorio en `MUSICA_DIR` (`*.mp3/ogg/wav/flac/m4a/opus`), lo reproduce 45 s y lo corta |
| 3 | **Hackeo falso** | Abre una terminal a pantalla completa con el espectáculo de `fake_hack.sh` |

## 📦 Instalación

```bash
sudo ./instalar.sh
```

1. Elige la cuenta a vigilar y escribe `ACEPTO`.
2. Se guarda tu **frase de liberación** (muéstrala, solo aparece una vez).
3. Se configura el servicio `bigbrother.service` (arranque automático).

**Dependencias:**

| Paquete | Obligatorio | Uso |
|---|---|---|
| `bash`, `systemd`, `libnotify` | ✅ | Base y notificaciones |
| Terminal (`kitty`, `konsole`, `xfce4-terminal`, `xterm`, ...) | ✅ | Abrir el aviso y el hackeo |
| Reproductor (`mpv`, `ffplay`, `mpg123`, `ogg123`, `play`, `paplay`) | ⚠️ opcional | Travesura de música |
| `OPENROUTER_API_KEY` | ⚠️ opcional | Mensajes de IA (si no, frases locales) |

## ⚙️ Configuración (`/opt/bigbrother/etc/config.conf`)

| Clave              | Default                 | Descripción |
|--------------------|-------------------------|-------------|
| `USUARIO_VIGILADO` | `$SUDO_USER`            | Cuenta a vigilar |
| `INTERVALO_HORAS`  | `1`                     | Cada cuántas horas de uso se dispara el ciclo |
| `MUSICA_DIR`       | `~/Music` del usuario   | Directorio para la travesura de música |
| `MODELO`           | `deepseek/deepseek-chat`| Modelo OpenRouter para los mensajes de Gilfoyle |

> Los tiempos del ciclo (10 s → terminal, 5 min → travesura) están fijos en
> `surveillance.sh` (función `lanzar_flujo`).

## 🔍 Servicio

```bash
systemctl status bigbrother      # estado
journalctl -u bigbrother -f      # registros del servicio
```

Todo evento relevante también se anota en `/opt/bigbrother/etc/registros.db`.

## 🚪 Salida (siempre disponible)

```bash
sudo /opt/bigbrother/desinstalar.sh emergencia   # requiere la frase de liberación
```

Para recordarla: `sudo cat /opt/bigbrother/etc/frase_liberacion`

## 🧾 Notas técnicas

- Se cuenta tiempo de sesión X11/Wayland activa vía `loginctl` (tick de 30 s).
- `run_as_user` inyecta `DISPLAY`/`XAUTHORITY` o `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR` desde los
  procesos del usuario para abrir terminales/notificaciones en su sesión.
- Este software **no** se defiende contra su desinstalación: un administrador siempre gana,
  y el protocolo de salida existe para que nunca quedes atrapado.

*"El poder no es un medio; es un fin."*