@AGENTS.md

2026-11-03: Voz opcional integrado con SDK 4.2.3 exacto. Aviso de licencia en `PRIVACY_VOZ.md`.

2026-11-17/18: auditoría en `docs/auditoria-2026-11-17.md` y arreglos C1, vocabulario, I1/I2/I4 (grabación que sobrevive a interrupciones y cierres), C2/P1 (Whisper sin red, WhisperKit fijado a revisión), T4/T5 (segmentos limpios y exportación SRT/VTT). 99 tests en simulador; nada probado en iPhone real.
**Antes de cualquier build de TestFlight/App Store:** el campo nuevo `segmentTimings` debe aparecer en el esquema Development de CloudKit (correr un build Debug con iCloud que sincronice una transcripción de Whisper) y desplegarse a Production en CloudKit Console.
Estado, pendientes y lo no verificado: `estado.md`.
