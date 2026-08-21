# 👁 GRAN HERMANO v2.0

Sistema de control totalitario **voluntario** para Arch Linux, inspirado en *1984* de George Orwell. Una experiencia inmersiva de compromiso conductual (estilo "locked mode"): el Gran Hermano vigila tu cuenta, castiga tus excesos y te vaporiza si te desvías.

## ⚖️ Contrato de diseño

Este software se rige por tres garantías no negociables:

1. **Consentimiento informado**: la instalación exige leer un contrato completo y teclear `ACEPTO LA VIGILANCIA`.
2. **Alcance limitado**: solo vigila la cuenta que consiente. Nunca otras cuentas del sistema.
3. **Salida siempre disponible**: protocolo oficial con período de reflexión + válvula de emergencia. Este software **no puede atraparte**: no toca BIOS/UEFI/GRUB, no se reinstala a escondidas y no resiste su desinstalación legítima.

## 🏛️ Arquitectura

```
/opt/bigbrother/
├── bin/
│   ├── bigbrother.sh      CLI: panel, informes, arrepentimiento
│   ├── surveillance.sh    Bucle principal de vigilancia (servicio systemd)
│   ├── castigos.sh        Castigos niveles 1-4
│   ├── propaganda.sh      Ministerio de Propaganda (servicio systemd)
│   ├── time_control.sh    Presupuesto diario de tiempo
│   ├── vaporizador.sh     Exilio aleatorio ponderado + ley marcial
│   └── lib.sh             Biblioteca compartida
├── etc/                   config.conf, bases de datos, frase_liberacion
├── logs/                  vigilancia/, castigos/, vaporizaciones/
└── assets/                Efigies del Partido
```

## 🎯 Triggers de vigilancia

| Trigger | Umbral | Escalada |
|---|---|---|
| Tiempo de sesión | 180 min/día (+60 extra) | aviso → N1 → N2 → N3 → vaporización |
| Wine (software subversivo) | acumulado diario | 5min → N2 · 15min → N3 · 30min → vaporización |
| YouTube (propaganda enemiga) | acumulado diario | 20min aviso · 30min N1 · 40min N2 · 60min N3 |
| Sudo (intento de rebelión) | por comando | `-l` aviso · `su` N2 · `systemctl` N3 · `passwd` vaporización |

## 📊 Niveles de castigo

- **N1 — La Mirada del Hermano**: overlay 3-5s + advertencia.
- **N2 — La Visita de O'Brien**: overlay 5-8s + seguimiento propagandístico.
- **N3 — La Omnipresencia**: overlay continuo 5-15 min + bloqueo de entrada (X11) + sesión bloqueada.
- **N4 — La Vaporización**: apagado programado + exilio de 6-72h (aleatorio ponderado, con modificadores por reincidencia/sudo/wine). Al arrancar durante el exilio, la ley marcial expulsa la sesión gráfica hasta la hora de retorno (despertar automático por RTC).

## 🚪 Protocolos de salida

```bash
# Oficial (inmersivo): período de reflexión obligatorio + frase
sudo /opt/bigbrother/bin/bigbrother.sh arrepentimiento

# Emergencia: salida inmediata (nunca puede fallar)
sudo /opt/bigbrother/desinstalar.sh emergencia
```

La frase de liberación se muestra una vez al instalar y queda en `/opt/bigbrother/etc/frase_liberacion` (legible solo por root).

## 📦 Instalación

```bash
sudo ./instalar.sh
```

Dependencias: `bash`, `systemd`, `libnotify`, `feh` (X11) o `swayimg`/`imv` (Wayland), `sqlite3`, `util-linux` (rtcwake), opcionales: `imagemagick`, `xorg-xinput`.

## 🔍 Comandos del ciudadano

```bash
bigbrother estado            # panel de control supremo
bigbrother informes [fecha]  # informe de actividad
bigbrother propaganda        # probar doctrina
```

## 🧠 Notas técnicas

- Detección de YouTube vía historial de Firefox/Chromium (cada visita pesa `PESO_YOUTUBE_SEG` segundos).
- Detección de sudo vía `journalctl` (`_COMM=sudo`).
- El bloqueo de entrada es best-effort en X11; en Wayland se sustituye por overlay + bloqueo de sesión.
- Todo evento queda registrado en `registros.db`; los castigos en `logs/castigos/`.

*"El poder no es un medio; es un fin."*
