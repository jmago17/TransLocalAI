@AGENTS.md

2026-11-03: Voz opcional integrado con SDK 4.2.3 exacto. Aviso de licencia en `PRIVACY_VOZ.md`.

2026-11-17/18: auditoría en `docs/auditoria-2026-11-17.md` y arreglos C1, vocabulario, I1/I2/I4 (grabación que sobrevive a interrupciones y cierres), C2/P1 (Whisper sin red, WhisperKit fijado a revisión), T4/T5 (segmentos limpios y exportación SRT/VTT). 99 tests en simulador; nada probado en iPhone real.
**Antes de cualquier build de TestFlight/App Store:** el campo nuevo `segmentTimings` debe aparecer en el esquema Development de CloudKit (correr un build Debug con iCloud que sincronice una transcripción de Whisper) y desplegarse a Production en CloudKit Console.
2026-11-18/19: banco `tools/WhisperBench` (mide la app real con un audio local). Whisper va **sin prompt**: cualquier prompt hundía la cobertura con large-v3-v20240930 (medido; no reintroducirlo sin volver a pasar el banco).
2026-11-20: la corrección difusa de vocabulario no toca códigos con cifras (OP10A ≠ OP20A). `tools/ASRBench` compara apps contra Qwen3-ASR y Parakeet (README dentro).
Estado, pendientes y lo no verificado: `estado.md`.
2026-11-22: indicadores de "IA pensando" con ThinkingOrbs 1.1.0 (SPM exacto). `TranscribingAnimation` y las barras con progreso real se quedan; falta el aviso MIT en la app.
2026-11-23: "multilingual" forzaba inglés en Whisper (faltaba `detectLanguage`); arreglado junto con detección de idioma en 8 ventanas, colapso de bucles y huecos mal contados. Medido contra Quick Subs con `tools/ASRBench`; no cambiar el idioma/motor por defecto sin volver a pasar el banco.
2026-11-24: tramos en idioma ajeno (menos del 5 % del tiempo) se retranscriben en los idiomas del audio; líneas-eco colapsadas. HiTZ bilingüe eu-es evaluado y descartado (pierde la mitad de las palabras fuera del Parlamento); no repetir sin modelo nuevo.
