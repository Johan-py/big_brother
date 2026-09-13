# 👁 GRAN HERMANO v3.0

Sistema de control totalitario **voluntario** para Arch Linux, inspirado en *1984* de George Orwell. Una experiencia inmersiva de compromiso conductual (estilo "locked mode"): el Gran Hermano vigila tu cuenta, castiga tus excesos y te vaporiza si te desvías.

> Nivel de control: **ESTRICTO** — cupo diario intacto (180 min + 60 extra), escaladas de castigo ~3× más rápidas, exilio más largo y propaganda más frecuente.

## ⚖️ Contrato de diseño

Este software se rige por tres garantías no negociables:

1. **Consentimiento informado**: la instalación exige leer un contrato completo y teclear `ACEPTO LA VIGILANCIA`.
2. **Alcance limitado**: solo vigila la cuenta que consiente. Nunca otras cuentas del sistema.
3. **Salida siempre disponible**: protocolo oficial con período de reflexión + válvula de emergencia. Este software **no puede atraparte**: no toca BIOS/UEFI/GRUB, no se reinstala a escondidas y no resiste su desinstalación legítima.

## 🏛️ Arquitectura

```
/opt/bigbrother/
├── bin/
│   ├── bigbrother.sh      CLI: panel, informes, arrepentimiento (vía /usr/local/bin)
│   ├── surveillance.sh    Bucle principal de vigilancia (servicio systemd)
│   ├── castigos.sh        Castigos niveles 1-4
│   ├── propaganda.sh      Ministerio de Propaganda (servicio systemd)
│   ├── time_control.sh    Presupuesto diario de tiempo
│   ├── vaporizador.sh     Exilio aleatorio ponderado + ley marcial
│   └── lib.sh             Biblioteca compartida (sqlite)
├── etc/                   config.conf, estado.db (sqlite), frase_liberacion
├── logs/                  vigilancia/, castigos/, vaporizaciones/
└── assets/                Efigies del Partido
```

Todo el estado vive en `etc/estado.db` (sqlite 3): registros, contadores diarios, triggers de castigo, exilios y protocolo de salida. Escrituras transaccionales con `busy_timeout`, sin ficheros sueltos con `flock`.

## 🎯 Triggers de vigilancia

| Trigger | Umbral | Escalada |
|---|---|---|
| Tiempo de sesión | 180 min/día (+60 extra) | aviso (3 min exceso) → N1 (6) → N2 (12) → N3 (18) → vaporización |
| Wine (software subversivo) | acumulado diario | 1min aviso · 2min N2 · 5min N3 · 9min vaporización |
| YouTube (propaganda enemiga) | acumulado diario | 6min aviso · 10min N1 · 14min N2 · 20min N3 |
| Sudo (intento de rebelión) | por comando | `-l` aviso · `su` N2 · `systemctl` N3 · `passwd` vaporización |

## 📊 Niveles de castigo

- **N1 — La Mirada del Hermano**: overlay 5-8s + advertencia.
- **N2 — La Visita de O'Brien**: overlay 8-11s + seguimiento propagandístico.
- **N3 — La Omnipresencia**: overlay continuo 15-30 min configurable + bloqueo de entrada (X11) + sesión bloqueada. Duración por trigger en config (`TIEMPO_N3_DUR_S`, `WINE_N3_DUR_S`, `YOUTUBE_N3_DUR_S`, `SUDO_N3_DUR_S`).
- **N4 — La Vaporización**: apagado programado + exilio de 6-96h (duración ponderada ×`EXILIO_MULT`, con modificadores por reincidencia/sudo/wine). Al arrancar durante el exilio, la ley marcial expulsa la sesión gráfica hasta la hora de retorno (despertar automático por RTC). Si `VAPORIZACION_HABILITADA=0`, N4 se degrada a N3.

## 🚪 Protocolos de salida

```bash
# Oficial (inmersivo): período de reflexión obligatorio + frase
sudo /usr/local/bin/bigbrother arrepentimiento

# Emergencia: salida inmediata (nunca puede fallar)
sudo /opt/bigbrother/desinstalar.sh emergencia
```

La frase de liberación se muestra una vez al instalar y queda en `/opt/bigbrother/etc/frase_liberacion` (legible solo por root). `REFLEXION_HORAS` queda intacto: el contrato de salida nunca se endurece.

## 📦 Instalación

```bash
sudo ./instalar.sh
```

Dependencias: `bash`, `systemd`, `sqlite3`, `util-linux` (rtcwake/runuser), `libnotify`, `feh` (X11) o `swayimg`/`imv` (Wayland), opcionales: `imagemagick`, `xorg-xinput`.

## 🔍 Comandos del ciudadano

```bash
bigbrother estado            # panel de control supremo
bigbrother informes [fecha]  # informe de actividad
bigbrother propaganda        # probar doctrina
```

## ⚙️ Configuración

Toda la estrictez vive en `/opt/bigbrother/etc/config.conf` (plantilla: `etc/config.conf.example`). Las claves inválidas se auto-corrigen al primer arranque (`validar_config`), dejando constancia en `registros`.

| Clave | Valor | Significado |
|---|---|---|
| `LIMITE_DIARIO_MIN` | 180 | Cupo diario de sesión (min) — **sagrado** |
| `TIEMPO_EXTRA_MIN` | 60 | Tolerancia extra diaria (min) |
| `TIEMPO_ADV_MIN` / `_N1` / `_N2` / `_N3` | 3 / 6 / 12 / 18 | Minutos de exceso para aviso/N1/N2/N3 |
| `WINE_ADV_MIN` / `_N2` / `_N3` / `_N4` | 1 / 2 / 5 / 9 | Minutos acumulados de wine |
| `YOUTUBE_ADV_MIN` / `_N1` / `_N2` / `_N3` | 6 / 10 / 14 / 20 | Minutos acumulados de YouTube |
| `PESO_YOUTUBE_SEG` | 90 | Segundos que pesa cada visita al historial |
| `COOLDOWN_ADV_S` / `_N1` / `_N2` / `_N3` / `_N4` | 180 / 240 / 360 / 600 / 3600 | Cooldown entre castigos (seg) |
| `TIEMPO_N3_DUR_S` | 1800 | Duración N3 por exceso de sesión (seg) |
| `WINE_N3_DUR_S` | 1200 | Duración N3 por wine (seg) |
| `YOUTUBE_N3_DUR_S` | 1200 | Duración N3 por YouTube (seg) |
| `SUDO_N3_DUR_S` | 900 | Duración N3 por sudo (seg) |
| `VAPORIZACION_HABILITADA` | 1 | `0` degrada N4 → N3 (sin exilio) |
| `EXILIO_MULT` | 150 | +50% de duración sobre el exilio base |
| `EXILIO_MAX_H` | 96 | Tope del exilio en horas |
| `REFLEXION_HORAS` | 24 | Reflexión del protocolo de salida (contrato, intacto) |
| `PROPAGANDA_INTERVALO_MIN` | 5 | Intervalo base de propaganda (min) |

## 🧠 Notas técnicas

- Detección de YouTube vía historial de Firefox (`moz_historyvisits`), Chromium/Chrome/Edge/Brave/Vivaldi (`COUNT(DISTINCT url)`). Cada visita pesa `PESO_YOUTUBE_SEG` segundos.
- Detección de sudo vía `journalctl` (`_COMM=sudo`).
- El bloqueo de entrada es best-effort en X11; en Wayland se sustituye por overlay + bloqueo de sesión.
- Todo evento queda registrado en `estado.db` (tabla `registros`); los castigos en `logs/castigos/`.
- Al actualizar desde v2.0, los ficheros legado (`registros.db`, `.tiempo.*`, `CASTIGOS_DB`, `EXILIO_DB`, `SALIDA_DB`, `usuarios.db`) se importan a sqlite automáticamente al primer arranque.
- `shellcheck` se ejecuta en CI (`.github/workflows/shellcheck.yml`).

*"El poder no es un medio; es un fin."*