# TransLocalAI — Traspaso de sesión

Documento para continuar el trabajo en una sesión nueva de Claude Code.
Última actualización: 2026-06-20.

---

## Qué es el proyecto

**TransLocalAI** es una app iOS/iPadOS (proyecto Xcode `Transcriber`, bundle
`com.josumartinez.transcriber`) que actúa de **cliente de un pipeline de actas de
reunión**. Repo: `github.com/jmago17/TransLocalAI`. Ruta local:
`~/Documents/Developer/TransLocalAI/` (iCloud).

Flujo del pipeline (vive en el Mac mini M4):
```
audio (iPad/iPhone) → ~/Reuniones/Inbox → whisper.cpp → transcripción .txt
→ Claude/LLM redacta el acta → nota en Apple Notes (carpeta "Actas")
```
Convención crítica: **el nombre del audio (sin extensión) = título exacto de la
nota en Apple Notes**.

La app es el mando a distancia + monitor del pipeline. Hoy habla con el Mac por
HTTP (`actas-server`, ver abajo) con fallback a iCloud.

---

## Estado del repo (rama `main`)

App reconstruida en 6 fases + fixes + preparación App Store. Commits relevantes
ya en `main` y pusheados:
- Núcleo de integración (`Shared/`: ActasServerClient, ActasServerConfig,
  PipelineModels, ICloudInboxBridge).
- UI con 4 tabs: **Actas** (dashboard del pipeline), **Biblioteca**, **Grabar**,
  **Ajustes**. `RootTabView`, `ActasView`, `PipelineController` (@Observable),
  `PipelineJob` (SwiftData + CloudKit).
- Share extension reorientada a "Enviar al Mac" (HTTP→iCloud fallback).
- Fallback offline WhisperKit + reenvío al reconectar.
- App Intent "Enviar audio para el acta" + notificaciones locales.
- **App Store**: versión 1.2, build 25. Se arregló rechazo ITMS-90626 (la
  metadata de Siri/App Intents no puede contener "mac" ni "apple" — saneado en
  `SendToMacIntent` y `TranscriberShortcuts`).
- `ExportOptions.plist` + `scripts/build-upload.sh`: archive + subida headless a
  ASC con cloud signing (API key en `~/.config/asc-api/`). Este Mac NO tiene
  certificado de firma local (es desechable), por eso cloud signing.

### Build / toolchain
- **Xcode en SSD externo**: exportar siempre
  `DEVELOPER_DIR=/Volumes/Almacen/Applications/Xcode.app/Contents/Developer`
  antes de cualquier xcodebuild.
- Deployment target iOS 26.2. Swift 6, default actor isolation = MainActor
  (los tipos de datos van marcados `nonisolated`).
- pbxproj usa grupos sincronizados con el filesystem (Xcode 16+). Grupo `Shared/`
  asociado a targets Transcriber + TranscriberShare. Editar pbxproj con el gem
  `xcodeproj` (instalado).
- Simulador de prueba: iPhone 17 id `38F50DAE-4CC0-4A78-A13F-BC16BB5BD815`.
  OJO: en el simulador la app conecta al server por `customHost=127.0.0.1`
  (las IP LAN disparan permiso de Red Local que el simulador no concede).
  Sembrar defaults del App Group con el sim apagado vía PlistBuddy en
  `.../Containers/Shared/AppGroup/<id>/Library/Preferences/group.com.josumartinez.transcriber.plist`.

---

## Infraestructura en el Mac (fuera del repo)

### actas-server (`~/actas-server/`)
- Control plane HTTP FastAPI, LaunchAgent `com.josu.actas-server` (`:8776`,
  RunAtLoad + KeepAlive). Proyecto `uv`. Wrapper `~/actas-server/run.sh`.
- Token bearer en `~/.config/actas-server/token`. Bind 0.0.0.0; accesible por
  Tailscale `100.123.146.23:8776` y LAN `192.168.31.108:8776`.
- Capa fina y stateless sobre `~/Reuniones/`: NO ejecuta whisper ni Claude.
  `/api/upload` deja audio en `Inbox/`; `/api/command` deja JSON en `Commands/`.
- Endpoints: health, status, transcriptions[/{name}], upload, command,
  retry/{audio|text}/{file}, logs/{stream}, SSE events.
- Circuit-breaker `pipeline.probe_fs_access` (timeout 8s, cooldown 12s, 1 hilo):
  si una lectura fría de iCloud se cuelga, devuelve 503 `fs_unavailable` rápido;
  health expone `fsAccessible`.

### Pipeline launchd (familia "actas", ficha `launchagents/redactor-actas.md`)
- `com.josu.transcribir-actas` — WatchPaths sobre `~/Reuniones/Inbox`.
- `com.josu.redactor-actas` — WatchPaths sobre `~/Reuniones/Transcripciones`.
- `com.josu.actas-control` — Commands/Status para la app.
- Scripts en `~/bin/`: `watch-inbox-actas.sh`, `transcribir-reunion.sh`,
  `watch-transcripciones.sh`, `redactar-acta.sh`, `watch-actas-commands.sh`,
  `actas-status.sh`, `notificar.sh`. Doc viva: `~/bin/CLAUDE.md`.
- whisper-cli en `/opt/homebrew/bin/`, modelo
  `~/whisper-models/ggml-large-v3-turbo-q5_0.bin`. claude CLI en `~/.local/bin/`.
- `redactar-acta.sh` ya CREA la nota en Actas si no existe (no hace falta
  prepararla a mano antes de la reunión).

### ⚠️ PROBLEMA ACTIVO: pipeline parado por FDA-bash
- En el panel/app "Control" sale `not running` / rojo. Causa real:
  **`com.josu.actas-control` sale con exit 1**. El 1-jun el log mostró
  `Operation not permitted` al escribir `~/Reuniones/Status/pipeline.json` —
  los agentes **bash** (transcribir/redactor/control) NO pueden tocar la carpeta
  iCloud desde launchd sin Full Disk Access para `/bin/bash`.
- Hay 2 audios atascados en `~/Reuniones/Inbox/` desde el 1-jun; el transcriptor
  no corre desde el 24-may. Uno de los 2 es basura (título de invitación de
  calendario `[EXTERNAL] Updated invitation...`); el otro real
  (`Instalación & PEM MTPL. Seguimiento semanal 11`).
- IMPORTANTE: el server en **python SÍ lee** la carpeta (no necesita FDA), por
  eso la app conecta; pero el pipeline que transcribe está parado.
- Pendiente: o conceder FDA a `/bin/bash`, o —mejor— la migración de abajo.

---

## ✅ HECHO: app de Mac nativa (target TranscriberMac)

Construida 2026-06-20. Target macOS `TranscriberMac` en el mismo `.xcodeproj`,
bundle `com.josumartinez.transcriber.mac`, app de barra de menú (LSUIElement),
**no sandboxed** (Developer ID — necesario para ejecutar whisper.cpp y Apple
Events a Notas). Compila y arranca estable. Ficheros en `TranscriberMac/`:
- `TranscriberMacApp.swift` — MenuBarExtra (popover) + Window + Settings;
  ModelContainer SwiftData+CloudKit compartido con iOS; arranca el processor.
- `PipelineProcessor.swift` — observa PipelineJob sincronizados por CloudKit,
  reclama los `transport == .cloudkit && stage == .queued`, procesa
  transcripción → redacción → Notas, actualiza el stage (visible en iOS).
  Poll 20s + reclaim de colgados; descarga el audio del contenedor iCloud.
- `MacTranscriber.swift` — motor elegible: Apple Speech / WhisperKit (engines de
  Core/) / whisper.cpp CLI (ffmpeg + whisper-cli).
- `ActaRedactor.swift` — Apple Foundation Models (default) / OpenAI API / CLI
  OpenAI / CLI Claude. Mismo prompt de acta; preserva notas manuales; salida HTML.
- `NotesWriter.swift` — lee/crea/actualiza/muestra la nota en carpeta Actas vía
  AppleScript (Apple Events nativos).
- `MacSettings.swift` — motores en App Group defaults; claves en Keychain.
- `LaunchAtLogin.swift` — SMAppService.
- `MenuBarContentView`/`MacMainView`/`MacSettingsView` — UI según mockups.
- Grupo sincronizado `Core/` (nuevo): los 8 ficheros cross-platform movidos de
  `Transcriber/` (engines, AudioFileManager, modelos). Sincronizado por iOS+Mac.

Integración end-to-end: `ProcessingRoute` (Shared/, App Group) = server | macApp.
iOS `submit()` con ruta macApp crea job `.cloudkit`/`.queued` y lo deja a CloudKit;
la app de Mac lo recoge. Selector en Ajustes iOS (default = server hasta validar).

### Pendiente de la app de Mac (no bloqueante)
- **Validar end-to-end de verdad**: enviar un audio desde iOS con ruta "App de
  Mac", confirmar que el job sincroniza por CloudKit, la app de Mac lo procesa y
  el acta aparece en Notas. No se ha probado el flujo CloudKit real (solo builds
  + arranque). Requiere firmar la app de Mac con el perfil real (no ad-hoc) para
  que CloudKit tenga el entitlement, y conceder permisos TCC (Automation→Notas,
  Speech). La primera vez pedirá permiso de Apple Events.
- **Firma/distribución**: Developer ID + notarización (no Mac App Store). Falta
  un flujo de export para la app de Mac (el `scripts/build-upload.sh` actual es
  para la app iOS / App Store).
- **Retirar la infra vieja** cuando esto se valide: actas-server + token + los
  agentes launchd transcribir/redactor/control. (El usuario pidió mantenerlos
  hasta validar.)
- Iconos de la app de Mac (asset catalog) — ahora usa el símbolo de sistema.

## TAREA HISTÓRICA (ya resuelta arriba): app de Mac nativa

El usuario quiere **migrar la parte del Mac de agentes launchd a una app de Mac
propia**, integrada en el mismo `Transcriber.xcodeproj` como target macOS.
Requisitos confirmados por el usuario:

1. **App de barra de menú** (menubar), arranca al iniciar sesión, procesa en
   segundo plano. NO un agente launchd suelto.
2. **Conexión por CloudKit en lugar de token/HTTP.** iOS sube audio → CloudKit →
   la app de Mac lo coge (suscripción), transcribe, redacta el acta en Apple
   Notes, actualiza estado → iOS lo ve. Sin token, sin Tailscale, sin servidor.
3. **Motor de transcripción: elegible por el usuario** — Apple SpeechAnalyzer /
   WhisperKit / whisper.cpp CLI (descargable/instalable). Default sensato.
4. **Motor de redacción: Apple Foundation Models on-device por defecto**, opción
   a OpenAI API / ChatGPT / CLIs de ambos. Claves en Keychain.
5. **Mantener server/token/agentes actuales hasta validar** que CloudKit va bien;
   luego retirarlos en una pasada. Sin ventana sin pipeline.

### Notas de implementación
- El `.xcodeproj` hoy es solo iOS (`SDKROOT=iphoneos`, device family "1,2").
  Hay que añadir un target macOS. Modelos y lógica de `Shared/` y los engines de
  transcripción (`TranscriptionEngine.swift`, etc.) NO usan UIKit → reutilizables
  cross-platform. `AICorrectionService` ya usa `FoundationModels`
  (`LanguageModelSession`, `@Generable`).
- Entitlement CloudKit ya presente en iOS:
  `iCloud.com.josumartinez.transcriber` (CloudDocuments + CloudKit).
- El modelo `PipelineJob` (SwiftData) ya está pensado con CloudKit (campos con
  default/opcionales, sin unique).
- Sugerencia de arquitectura: el `Transcription`/`PipelineJob` viaja por
  CloudKit; la app de Mac observa con `CKSubscription`/SwiftData+CloudKit, corre
  el pipeline localmente (transcribe + redacta), escribe el acta vía el MCP
  apple-notes o AppleScript/ScriptingBridge, y marca el job como done.

---

## TAREA EN CURSO: mockups de UI en Claude Design

Proyecto de Claude Design creado:
**https://claude.ai/design/p/9caf7c5c-7710-4c26-be50-bf4780c7286b**
(projectId `9caf7c5c-7710-4c26-be50-bf4780c7286b`, nombre "TransLocalAI — UI").

Se generaron 7 mockups HTML/CSS (look nativo iOS/macOS 26, iconos SVG inline para
que rendericen en navegador). Están en `/tmp/tla-ui/screens/` (¡temporal! ver
abajo) con primera línea `<!-- @dsCard group="..." -->`:
- `ios-actas.html` (iOS) — **SUBIDO y registrado**
- `mac-menubar.html` (macOS) — **SUBIDO y registrado**
- `ios-grabar.html` (iOS) — pendiente de subir
- `ios-biblioteca.html` (iOS) — pendiente de subir
- `ios-ajustes.html` (iOS) — pendiente de subir
- `ipad-actas.html` (iPadOS) — pendiente de subir
- `mac-window.html` (macOS) — pendiente de subir

### Bloqueo actual con Claude Design
La herramienta `DesignSync` (cargar con `ToolSearch query:"select:DesignSync"`)
falla con: **"refresh succeeded but design scopes not granted"**. El `/login`
entra pero NO concede el scope de design. El primer día sí funcionó (por eso hay
2 subidas). Reintentos de `/login` no lo arreglaron. Probar en sesión nueva:
`/logout` + `/login` completo, aceptando el scope "design" en el navegador.

### Cómo retomar la subida (cuando el scope funcione)
1. `/tmp/tla-ui/screens/` es temporal — **regenerar los 7 HTML primero** si la
   sesión es nueva (el contenido está descrito arriba; o copiarlos antes de
   cerrar esta sesión a `~/Documents/Developer/TransLocalAI/design-mockups/`).
2. `DesignSync finalize_plan` con `localDir` apuntando a la carpeta, `writes` =
   los 5 pendientes (o los 7), `deletes: []`.
3. `DesignSync write_files` con `{path, localPath}` por fichero.
4. `DesignSync register_assets` con `name`, `path`, `group` (iOS/iPadOS/macOS),
   `viewport`. Las 2 ya registradas: "Actas — dashboard" (449x908) y
   "Popover menubar" (380x560).
5. El usuario quería que "Claude Design le dé a todo" = que el agente de Design
   itere sobre las pantallas una vez subidas.

NOTA: `DesignSync` es para design systems de React; aquí se está usando solo como
canal para subir mockups HTML estáticos como tarjetas. Funciona, pero no es su
caso de uso típico.

---

## Decisiones de diseño tomadas (sistema visual de los mockups)
- Acento `#0a84ff`. Salud verde `#34c759` / ámbar `#ff9f0a` / rojo `#ff3b30`.
- Etapas del envío: En cola → Transcribiendo → Transcrito → Redactando → Acta
  lista / Error. Iconografía tipo SF Symbols (flecha-bandeja, waveform, líneas
  de texto, check sello, triángulo error).
- iOS: TabView 4 tabs. iPad: NavigationSplitView (sidebar + columnas
  cola/envíos). macOS: app menubar con popover (estrella) + ventana principal
  (procesando ahora / en cola / hechas hoy).

---

## Preferencias del usuario (Josu) — recordatorias
- Español técnico, escueto. Ejecutar el trabajo (editar/build/iterar), no dictar
  pasos. Minimizar prompts de permiso.
- Tras commit+push, resumir en 1-3 líneas qué entró. Push directo sin preguntar.
- Al ofrecer alternativas, marcar la robusta (suele elegirla).
- Mac mini es desechable; Pi y GitHub son la nube.
- Doc de LaunchAgents en
  `~/Documents/Developer/launchagents/` (skills `launchagents-doc` +
  `launchagent-panel-register`, panel en `:8766`). stderr solo para errores.
