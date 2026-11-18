# Auditoría TransLocalAI — 2026-11-17

Base: `c1e1c57` (main). Solo lectura: no se ha modificado código.

Nivel de comprobación de cada hallazgo:
- **[ejecutado]**: reproducido ejecutando el código real (tests o binario con el fuente de producción).
- **[leído]**: confirmado leyendo el código (incluido el fuente de WhisperKit en la revisión fijada).
- **[plausible]**: deducido del código, sin reproducir.

## Qué se ha verificado y qué no

- Build iOS (scheme `Transcriber`, simulador iPhone 17, iOS 27.3, Xcode-beta 27.3): **compila**.
- Unit tests: los **53 tests (9 suites) pasan**, pero el run acaba en `TEST FAILED`. `MeetingNotesProbeTests.pccRespondPlainProbe` mata el proceso dos veces con `Fatal error: Missing entitlement: com.apple.developer.private-cloud-compute` (ver C1).
- Build macOS (`TranscriberMac`): compila con `CODE_SIGNING_ALLOWED=NO`. Firmado falla porque no hay perfil para `com.josumartinez.transcriber.mac`; es un problema del entorno, no del código.
- Vocabulario: ejecutado `TranscriptionVocabulary.correcting` real con casos en español (C3, C4).
- **No verificado**: dispositivo físico, modo avión, consumo de memoria con audios de 1-2 h, inferencia real (Whisper/Voz/Apple), sync de CloudKit, Live Activities, App Intents en segundo plano.

## Estado de los arreglos

- **2026-11-17, arreglados C1, C3, C4 y C9** (sin commit):
  - **C1**: `hasPrivateCloudComputeEntitlement` lee el entitlement del binario en macOS (`SecTaskCopyValueForEntitlement`). En iOS exige la clave `TLPrivateCloudComputeEntitled` en Info.plist, que hoy no existe, así que el valor es `false`. La preferencia de PCC pasa a estar desactivada por defecto en ajustes de iOS y Mac, lo que cubre la parte de C17 sobre el valor por defecto.
  - **C3**: si la palabra está en minúscula o abre frase, un término con mayúscula solo la corrige si tiene 5 letras o más (coincidencia exacta) o 7 o más (parecido). Los nombres con mayúscula a mitad de frase se corrigen como antes.
  - **C4**: el reemplazo manual (detalle y palabras sospechosas) es literal y de palabra entera, y solo se guarda como alias si no contiene `,`, `:`, `=` ni saltos de línea.
  - **C9**: `TranscriptionTerminology.activeVocabularyLines` y `activeCanonicalTerms` excluyen los términos desactivados (y los de serie borrados). Se usan en todos los motores, en Share, en "Fix names", en palabras sospechosas y en la revisión IA. Se ha eliminado `correcting(_:)` sin términos, para que no se pueda volver a usar la lista sin filtrar.
- **Verificado**: tests iOS en simulador, 69 de 70 pasan, incluidos 6 nuevos de regresión. Builds de Mac (sin firma) y de Share compilan. El benchmark de vocabulario sigue compilando.
- **Falla 1 test**, `MeetingNotesProbeTests.onDeviceRespondProbe`: el simulador anuncia el modelo como `.available` pero rechaza la inferencia (`Simulator is not supported`). Es del entorno y existía antes; hasta ahora quedaba tapado por el crash de C1.
- **No verificado**: C1 en un Mac firmado con el entitlement y en un iPhone real; C9 no tiene test unitario, porque requiere inyectar el almacén (ver C14).
- **Límite conocido de C3**: con términos de 5 letras o más, el plegado de ñ y tildes sigue activo, porque es lo que corrige "inaki" → "Iñaki". Un término como "Peñas" seguiría cambiando "penas".

- **2026-11-17, arreglados I1, I2 e I4** (sin commit):
  - **Formato**: la grabación pasa de AAC `.m4a` a PCM 16 bits mono 16 kHz en `.caf` (unos 115 MB/h, frente a ~30–55 MB/h antes). Probado matando el proceso a mitad de escritura (`kill -9`, AVAudioFile en macOS): el `.m4a` no abre (`ExtAudioFileOpenURL` falla), AAC en `.caf` abre con 0 frames, WAV abre con 0 frames y PCM en `.caf` conserva todo lo escrito. 16 kHz es la frecuencia a la que todos los motores remuestrean, así que no se pierde nada de lo que ve Whisper.
  - **I1**: `AudioRecorderManager` observa `interruptionNotification` (pausa; reanuda sola si llega `.shouldResume`, si no muestra "Resume Recording") y `mediaServicesWereReset`. Implementa `audioRecorderEncodeErrorDidOccur` y trata `didFinish(successfully: false)`: en los tres fallos cierra el fichero, conserva el audio y avisa con "Recording Stopped". El contador y la Live Activity muestran tiempo grabado (pausa incluida); `ContentState` gana `timerStart` y `pausedElapsed`.
  - **I2**: marca "pendiente" (`PendingRecordings`, UserDefaults) al empezar; al parar se crea la entrada en la biblioteca en el acto y "Transcribe Now" la rellena. `RecordingRecovery` crea entradas para marcas sin entrada al arrancar, al volver a primer plano y cada vez que la grabación se para. Solo recupera ficheros marcados, para no resucitar entradas borradas a propósito (en este u otro dispositivo). Tras parar, "Cancel" pasa a "Done" porque el audio ya está guardado.
  - **I4**: `StopRecordingIntent` guarda la entrada antes de descargar el modelo o transcribir; si la transcripción falla, la entrada queda solo con audio y el diálogo lo dice.
- **Verificado**: tests iOS en simulador iPhone 17, todos pasan (incluidos 4 nuevos de `RecordingRecoveryTests`; esta vez también pasó `onDeviceRespondProbe`, así que su fallo en el simulador es intermitente). La build incluye el widget.
- **No verificado**: llamada real, Siri o alarma en un iPhone; que `AVAudioRecorder` con PCM/CAF se comporte igual que `AVAudioFile` al matar la app (el experimento usó `AVAudioFile`); `mediaServicesWereReset` (solo se provoca desde Ajustes de desarrollador); la Live Activity en pausa.
- **Fuera de este arreglo**: el botón de stop de la Live Activity sigue sin hacer nada (I10) e intents con contenedores distintos (I5).

- **2026-11-17, arreglados C2 y P1** (sin commit):
  - **C2**: `WhisperLocalModels` (en `Core/WhisperDecodingSupport.swift`, compilado también por Share) resuelve la carpeta del modelo **antes** de ir a la red. Si el proceso ya la descargó y verificó, y siguen estando los `coremldata.bin`, `model.mil` y `weights/weight.bin` de MelSpectrogram, AudioEncoder y TextDecoder, no hay llamada de red. Si no, descarga y la marca como verificada. Si la descarga falla y en la ruta por defecto hay una copia completa (modelos descargados antes de este cambio), la usa. Al descargar también precarga el tokenizer, para que la primera transcripción tras descargar sin red no lo necesite. Si WhisperKit no consigue cargar una carpeta verificada, se olvida para que el siguiente intento descargue de nuevo. Los dos `WhisperModelManager` (app y Share) llaman a lo mismo.
  - **P1**: WhisperKit fijado a la revisión exacta `ba094495` (antes rama `main` en esa misma revisión, así que no cambia el código). No se sube a una versión etiquetada: v0.16.0 está 3 commits después pero añade unas 13.500 líneas (TTSKit y cambios en la entrada de audio), y v1.1.1 41 commits. Subir de versión es una decisión aparte que hay que medir con el banco de pruebas.
- **Verificado**: tests iOS en simulador, todos pasan (86 casos, incluidos 4 nuevos de `WhisperOfflineModelTests`: sin red tras verificar, fallback a una copia antigua completa, descarga parcial que sigue fallando y carpeta dañada que vuelve a la red). Build de Mac (sin firma) correcta; la build resolvió WhisperKit en `ba09449`.
- **No verificado**: una transcripción real en modo avión en un iPhone o en el Mac. El tokenizer de quien ya transcribió está en disco, pero eso no se ha comprobado en un dispositivo real. Si una carpeta corrupta conserva el tamaño de los ficheros, el snapshot de Hub podría no volver a bajarlos.
- **Dato del informe**: Quick Subs usa el mismo modelo (`openai_whisper-large-v3-v20240930_626MB`, visto en su contenedor en este Mac). La diferencia de calidad viene de la configuración y la limpieza, no del modelo.
- **Fuera de este arreglo**: la extensión Share tiene su propio sandbox y descarga su propia copia del modelo (626 MB más); es parte de C6.

- **2026-11-17, hechos T4 y T5 del informe Quick Subs** (sin commit):
  - **T4** (`Core/TranscriptSegments.swift`, compilado también por Share): `tidy` quita las líneas vacías o de solo puntuación; parte los segmentos de más de 12 s por final de frase, luego por `, ; :` y si no por palabras; y fusiona las líneas de hasta 3 palabras con la vecina si la pausa es menor de 1,5 s, el resultado tiene 20 palabras o menos y dura 12 s o menos. No pierde ninguna palabra (está en los tests). Lo usan los dos motores Whisper (app y Share) y Voz. Voz parte ya con sus tiempos de palabra reales a 12 s (antes a 20 s).
  - **Límite de T4**: sin `wordTimestamps`, en Whisper los tiempos de los trozos de un segmento partido se reparten por número de caracteres. No se ha activado `wordTimestamps` porque cuesta tiempo de proceso y toca el decodificador; hay que medirlo con el banco (criterio de +30 % como máximo).
  - **T5**: campo nuevo `Transcription.segmentTimings: Data?` (JSON con inicio y fin de cada línea; opcional, compatible con CloudKit). Lo guardan la grabación, la importación, la retranscripción y los intents de transcribir. La exportación (`SubtitleExport`, en "More Actions" y el menú Share del detalle) parte del texto **tal como está editado**: cada línea `[mm:ss]` recupera su inicio y fin por el segundo de su marca; las líneas sin marca se añaden a la anterior. Sin tiempos guardados (Apple Speech, transcripciones antiguas) el fin se estima por número de palabras y nunca invade la línea siguiente. Las líneas largas se reparten en varios subtítulos de 2 líneas de 42 caracteres como máximo, y el último fin nunca pasa de la duración del audio. Se exporta en SRT y en WebVTT; la exportación `[mm:ss] texto` sigue igual.
- **Verificado**: 99 tests iOS en simulador pasan, 13 nuevos en `TranscriptSegmentsTests`: líneas de puntuación, fusión, corte de 38 s en [19:07], corte sin puntuación, ediciones del usuario, duración, transcripciones antiguas y un **validador estricto de SRT y WebVTT** (índices, formato de tiempos, fin mayor que inicio, sin solapes, dentro de la duración, 1 o 2 líneas de texto). El importador de la app lee el SRT exportado. El test de Voz sigue dando la misma salida. Build de Mac correcta.
- **No verificado**: el menú de compartir en un dispositivo real (que el fichero llegue con su extensión `.srt`/`.vtt` a Archivos o Mail); el efecto en la reunión de prueba de 28 min, que necesita el banco.
- **Antes de publicar una build de TestFlight o App Store**: desplegar el esquema de CloudKit de Development a Production en CloudKit Console. El campo `segmentTimings` se crea solo en Development; en Production un registro con un campo que no existe en el esquema no se guarda, y esa transcripción dejaría de sincronizarse.

## Comparación con el informe de calidad frente a Quick Subs (2026-11-17)

Informe aportado por Josu: reunión técnica en inglés de ~28 min. Con Whisper, Translocal iguala a Quick Subs en palabras inexistentes (1,1 % frente a 1,0 %) y le gana en cobertura (0 huecos frente a ~2 min). Pierde en términos técnicos y nombres, y en formato de segmentos. Contrastado con el código actual:

| Tarea | Qué hay ya | Qué falta | Valoración |
|---|---|---|---|
| **T1** glosario como prompt | `WhisperDecodingSupport.promptTokens`: `DecodingOptions.promptTokens`, filtra `>= specialTokenBegin`, términos ordenados por uso (`whisperPromptTerms`), tope 96 tokens. Idioma forzado configurable. | Prompt en frase natural (hoy es `" Glossary: a, b, c."`). Varios glosarios por proyecto con uno activo. Detección de bucles y eco del prompt en los segmentos **primarios** (hoy `isRepetitionLoop` solo filtra la recuperación de huecos). | Sí. Subir el tope a ~200 tokens **solo** con el banco de pruebas: el propio informe avisa del riesgo de alucinaciones y 96 se eligió por eso. |
| **T2** corrección determinista | `TranscriptionVocabulary.correcting`: alias por término (`AVEVA: Aviva, amiva`), alias de varias palabras, coincidencia difusa con plegado y Levenshtein, protegida desde C3. | Las variantes de la tabla como alias. Regla de estaciones `OB 10` → `OP10`. | **Parcial.** Los alias cuyo texto es inglés corriente o dependen del contexto (`DNA`→DLL, `residency`→redundancy, `a native`→Iñaki, `a lever`→AVEVA, `Dwyer on Apple TV`→"dry run on a VTP") **no** pueden ser globales: el reemplazo es de palabra entera sin contexto y estropearía otras reuniones ("a native speaker" → "Iñaki speaker"). Solo son aceptables dentro de un glosario de proyecto que el usuario activa para esa reunión, que es por qué T1 pide glosarios por proyecto. Double Metaphone es solo para inglés y la app trabaja en es/eu/en: no aporta frente a lo que hay. |
| **T3** limpieza IA local | `AICorrectionService` con FoundationModels en el dispositivo, por bloques, con validación, y como **sugerencias** que el usuario acepta. PCC desactivado por defecto desde C1. | Salvaguarda de WER del 25 % por segmento. | El enfoque actual (sugerencias revisables) es más seguro que reescribir el texto. Hacerlo solo si tras T1+T2 quedan errores. |
| **T4** segmentación | Segmentos de Whisper con inicio y fin; fusión de huecos recuperados. | Quitar líneas vacías **o solo puntuación** (hoy `guard !text.isEmpty` deja pasar `[01:51] .`). Fusionar líneas muy cortas y partir segmentos largos. WhisperKit da `wordTimestamps`, hoy no se pide. | Sí, bajo riesgo. |
| **T5** SRT/VTT | `TranscriptFileParser` **importa** SRT/VTT. | El fin de cada segmento se pierde: se guarda texto plano `[mm:ss] texto`. Exportar SRT/VTT exige guardar los segmentos (campo nuevo opcional en `Transcription`, compatible con CloudKit). Recortar el último fin a la duración. | Sí. Requiere decidir el campo nuevo en el esquema sincronizado. |
| **T6** voz baja | Perfiles `Balanced` y `Maximum coverage` con umbrales explícitos; VAD de WhisperKit; reintento relajado de huecos de 10 s o más; métricas de cobertura. | Que el banco de pruebas mida huecos de 5 s o más con energía de voz (RMS relativo). | Ya cubierto en el código; falta medirlo. El cambio de I2 a PCM 16 kHz quita la compresión AAC antes de Whisper; no debería empeorar la voz baja, pero hay que confirmarlo con el banco. |
| **Evaluación** | `scripts/VocabularyBenchmark.swift` (solo texto). | Banco con el audio real (ruta por variable de entorno, fuera de git), métricas del informe y `eval_report.md`. | Imprescindible antes de dar nada por mejorado; necesita el audio de la reunión. |

**Lo que el informe no ve y condiciona su punto 4 ("todo local, sin llamadas de red"):**
- **C2**: hoy cada transcripción con Whisper contacta con huggingface.co y sin red falla. Va antes que T1–T6.
- **P1**: WhisperKit sigue la rama `main`, así que `promptTokens` y `wordTimestamps` pueden cambiar sin aviso. Fijar versión antes de apoyarse en ellas.

**Orden propuesto:** C2 + P1 → T4 (líneas de solo puntuación, fusión y corte) → T5 (guardar segmentos y exportar SRT/VTT) → banco de pruebas con el audio → T1 (frase natural, glosarios por proyecto, bucles en primarios) → T2 (alias de la tabla en el glosario MTPL + regla de estaciones) → volver a medir → T3 solo si hace falta.

## Comparación con auditorías anteriores

La auditoría de 2026-10-16 (13 hallazgos) solo existe en un enlace externo de ChatGPT, no en el repo, así que **no se ha podido deduplicar** contra ella. Si algún hallazgo de abajo ya estaba allí y sigue sin corregir, queda **reconfirmado** en este código. `docs/cleanup-validation.md` (caché de vocabulario y limpieza de AudioFileManager) no se solapa con nada de esta lista. Recomendación: guardar las auditorías en `docs/` del repo.

---

## 1. Core compartido (iOS + Mac + Share)

### C1 · CRÍTICA · Crash al generar notas en iOS por PCC sin entitlement [ejecutado]
- **Dónde**: `Core/MeetingNotesService.swift:51-61` (`hasPrivateCloudComputeEntitlement`), `:41-45`, `:98-107`.
- **Problema**: cuando no hay `embedded.mobileprovision`, la función devuelve `true`. Ese caso se da en el simulador, en App Store y en TestFlight. `Transcriber/Transcriber.entitlements` (iOS) **no** tiene `com.apple.developer.private-cloud-compute`, y la preferencia PCC vale `true` por defecto. `respond` no lanza un error: hace un `fatalError`. Reproducido en el test runner.
- **Consecuencia**: en iOS 27 con PCC disponible, la app se cierra al pulsar "notas" o al lanzar el Atajo de notas. En Mac no pasa, porque su entitlement sí lo declara.
- **Solución**: no deducir el entitlement de la ausencia de perfil. Usar un flag de compilación o una clave de Info.plist que solo exista en los targets que declaran el entitlement. Mientras iOS no lo tenga, `false`. Poner la preferencia PCC a `false` por defecto (ver C17).

### C2 · CRÍTICA · Whisper no funciona sin conexión aunque el modelo esté descargado [leído]
- **Dónde**: `Core/WhisperModelManager.swift:48` y su copia `TranscriberShare/WhisperModelManager.swift:45`.
- **Problema**: `ensureModelAvailable` llama siempre a `WhisperKit.download`. Esa función (WhisperKit `ba09449`, `WhisperKit.swift:255`) hace primero `hubApi.getFilenames` contra huggingface.co, y si falla relanza el error sin mirar la copia local.
- **Consecuencia**: en modo avión no se puede transcribir en euskera ni en multilingüe, aunque el large-v3 esté ya en el dispositivo. Además, cada transcripción contacta con Hugging Face, cosa que no se declara. Contradice el texto "will be reused offline" (`ImportAudioView.swift:236`).
- **Solución**: persistir la carpeta local resuelta. Si contiene los `.mlmodelc`, pasarla como `modelFolder` con `download: false`. Ir a la red solo si falta el modelo.

### C3 · ALTA · La corrección de vocabulario estropea palabras comunes, incluso con los términos por defecto [ejecutado]
- **Dónde**: `Core/TranscriptionVocabulary.swift:391-422` (`normalize`, `bestReplacement`), términos por defecto en `:12`.
- **Problema**: el plegado de diacríticos convierte la ñ en n y quita las tildes. La coincidencia exacta no exige longitud mínima, y la pasada difusa se aplica también a palabras en minúscula.
- **Resultados reales**:
  - "No lo borra nadie, en la forja." pasa a "No lo **Borja** nadie, en la **Borja**." ("Borja" viene **por defecto**).
  - Con el término "Peña": "Qué pena" pasa a "Qué **Peña**".
  - Con el término "Mas": "más café" pasa a "**Mas** café".
- **Consecuencia**: el texto se corrompe en silencio en todas las transcripciones (Whisper, Voz, Apple, Share y "Fix names").
- **Solución**: en la pasada difusa y en la exacta con plegado, no tocar tokens en minúscula a mitad de frase (`suspiciousTerms` ya hace esto). Distinguir ñ/n. Exigir coincidencia exacta de diacríticos por debajo de 5 letras.

### C4 · ALTA · El reemplazo manual con comas reescribe todo el texto y queda guardado en iCloud [ejecutado]
- **Dónde**: `Transcriber/TranscriptionDetailView.swift:897-906`; `TranscriptionVocabulary.swift:87-97`.
- **Problema**: la selección se interpola sin escapar en `"\(canonical): \(variant)"`, y `parse` la parte por comas. Además pasa por el filtro difuso.
- **Resultados reales**:
  - Al cambiar "sí, claro" por "Sí, claro.": "Dijo sí, claro, y luego claro que sí." queda como "Dijo Sí, Sí, claro.., Sí, claro., y luego Sí, claro. que Sí, Sí, claro...".
  - Al cambiar "pausa larga" por "causa", "una pausa larga" queda como "una causa", y cualquier "pausa" suelta también acaba en "causa".
  - `recordCorrection` guarda el alias en el vocabulario sincronizado, así que el daño se aplica también a las transcripciones futuras.
- **Solución**: reemplazar solo la ocurrencia seleccionada, o todas las literales con vista previa. No pasar por `correcting`. Guardar el alias solo para palabras sin `,`, `:` ni `=`.

### C5 · ALTA · En reuniones largas se pierden decisiones y tareas [leído]
- **Dónde**: `Core/MeetingNotesService.swift:167-188` (`mergeCaps`).
- **Problema**: la fusión en árbol limita la salida final a 3 decisiones y 3 tareas. `assemble()`, la fusión sin pérdidas, es código muerto. Los tests `assemblyPreservesAllPartsAndDistinctTasks` y `lateChunkIncludedInBoundedGroups` prueban esa ruta que no se usa.
- **Consecuencia**: en 2 h (unas 45 partes) sobreviven como mucho 3 tareas, elegidas por el modelo. Los tests en verde dan una falsa confianza.
- **Solución**: unir Decisiones y Tareas de forma determinista con `assemble()`, porque ya están validadas con su cita. Fusionar con el LLM solo Resumen y Puntos clave.

### C6 · ALTA · Varias copias del modelo Whisper en RAM [leído]
- **Dónde**: `Core/TranscriptionEngine.swift:232-243`. `HybridTranscriptionService()` se crea como `let` en `ImportAudioView.swift:32`, `RecordingView.swift:32`, `TranscriptionDetailView.swift:806` y en los intents.
- **Problema**: la clave de la caché incluye el idioma, así que detectar el idioma (clave `nil`) y transcribir (`es-ES`) cargan dos instancias del mismo large-v3, de 626 MB. Además cada vista tiene su propia caché y recarga el modelo.
- **Solución**: una caché global con clave `modelId`; el idioma va en `DecodingOptions`. Mantener como máximo un modelo residente y liberarlo con el aviso de memoria.

### C7 · ALTA · El audio largo se carga entero en memoria [leído / jetsam plausible]
- **Dónde**: `Core/TranscriptionEngine.swift:298`; Share `:384`.
- **Problema**: `transcribe(audioPath:)` carga todo el audio en Float32 a 16 kHz (unos 460 MB para 2 h), y el troceado VAD lo duplica. A eso se suma el modelo.
- **Solución**: leer el `AVAudioFile` por ventanas de 5-10 min, llamar a `transcribe(audioArray:)` en cada una y desplazar los timestamps.

### C8 · MEDIA · Las notas locales fallan enteras con facilidad [plausible alta]
- **Dónde**: `MeetingNotesService.swift:36-37`, `:193-216`, `:303`.
- **Problema**:
  - El límite de validación (≤850 caracteres) contradice los topes del propio prompt (unos 1.780).
  - `maximumResponseTokens` de 350 trunca la salida.
  - Un preámbulo del modelo invalida la respuesta.
  - Que una sola de las 45 partes falle dos veces aborta todo.
  - `guardrailViolation`, `exceededContextWindowSize` y `unsupportedLanguageOrLocale` no se capturan.
- **Solución**: alinear los límites, limpiar el preámbulo antes de validar y degradar una parte fallida a "Parte N no resumible" en lugar de abortar.

### C9 · MEDIA · Desactivar un término no lo desactiva [leído]
- **Dónde**: `TranscriptionVocabulary.swift:72-81`; usos en `TranscriptionEngine.swift:362`, `VozTranscriptionEngine.swift:69`, `ShareHybridTranscriptionService.swift:126,445`.
- **Problema**: `correcting`, `suspiciousTerms` y el prompt de la revisión IA ignoran el estado `.disabled`; solo se respeta en el sesgo de los motores.
- **Solución**: filtrar las entradas desactivadas antes de esas tres llamadas.

### C10 · MEDIA · La autodetección descarga Whisper aunque el motor elegido sea Apple [leído]
- **Dónde**: `ImportAudioView.swift:351` → `TranscriptionEngine.swift:430-447` (`preferApple` es `false` por defecto).
- **Consecuencia**: en la primera importación se descargan 626 MB mientras pone "Detecting language…".
- **Solución**: `preferApple: engine != .whisper`, o usar Whisper para detectar solo si el modelo ya está en local.

### C11 · MEDIA · El posprocesado pesado corre en el MainActor [leído / tirón no medido]
- **Dónde**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` en los targets de app y Mac. Afecta a `WhisperKitSession`, `WhisperKitEngine` y `HybridTranscriptionService` (`TranscriptionEngine.swift:299-370`).
- **Problema**: el bucle de segmentos, `merge` y `correcting` por segmento corren en el hilo principal. Share no tiene aislamiento por defecto, así que su copia del código tiene una semántica de concurrencia distinta.
- **Solución**: marcar esos tipos como `nonisolated` o actores, y corregir el vocabulario una sola vez sobre el texto ya unido.

### C12 · MEDIA · La recuperación de huecos reintenta los primeros, no los más largos [leído]
- **Dónde**: `TranscriptionEngine.swift:317-347`, `WhisperDecodingSupport.swift:79-90,141-159`.
- **Problema**: `gaps.prefix(4/6)` coge los huecos más tempranos. Además, `noSpeechThreshold` 0,9 sobre silencio real favorece alucinaciones ("Gracias.", "Subtítulos por…").
- **Solución**: ordenar los huecos por duración, descartar los que sean silencio por energía y filtrar los resultados por `noSpeechProb`/`avgLogprob` y por una lista de frases alucinadas típicas.

### C13 · MEDIA · Revisión IA: casi nunca propondrá nada y no comprueba disponibilidad [plausible]
- **Dónde**: `Core/AICorrectionService.swift:19-37`, `:89-95`, `:151-153`.
- **Problema**:
  - Exige que el modelo dé el offset exacto en caracteres. Un LLM local no lo hace bien, así que casi todo se descarta y se muestra "No clear transcription errors".
  - 6.000 caracteres más hasta 100 términos más el esquema rozan los ~4K tokens del modelo.
  - Un error en un trozo tira los trozos ya hechos.
  - No se comprueba `availability` ni `supportsLocale`.
- **Lo que está bien**: no puede inventar ni borrar texto. Solo aplica sustituciones validadas, con aprobación del usuario y comprobando la instantánea.
- **Solución**: localizar la propuesta por texto y contexto en código, no por offset. Trozos de unos 2.500 caracteres, `catch` por trozo, y comprobar disponibilidad e idioma antes de abrir la hoja.

### C14 · MEDIA · Los tests escriben en el almacén real (App Group e iCloud KVS) [leído]
- **Dónde**: `TranscriberTests/TranscriptionPipelineTests.swift:85-150`.
- **Problema**:
  - `recordCorrection("Wallix","Wallace")` no se limpia nunca, así que deja el alias "Wallix = Wallace" en el vocabulario sincronizado si se ejecuta con una cuenta de iCloud.
  - Hay tests que dependen del estado previo del almacén (que exista "Danobat", que "Wallix" salga el primero).
- **Solución**: inyectar un `UserDefaults` efímero y un KVS falso.

### C15 · MEDIA · El primer arranque puede sobrescribir el vocabulario de iCloud con los términos por defecto [plausible]
- **Dónde**: `TranscriptionVocabulary.swift:342-349`.
- **Problema**: en una instalación nueva, antes de que baje el KVS, se suben los términos por defecto con `updatedAt = now`, y como gana la escritura más reciente, sobrescriben lo que hubiera en iCloud.
- **Solución**: si no hay nada local ni en la nube, no subir nada y esperar a `didChangeExternally` (`initialSync`), o escribir con `updatedAt = 0`.

### C16 · BAJA · Varios del pipeline
- La detección de idioma de Apple compara `Locale.identifier` como texto ("es-ES" frente a "es_ES"). Si no coinciden, devuelve "en-US" con puntuación 0 (`SpeechTranscriptionManager.swift:167,199-200`). Solución: `supportedLocale(equivalentTo:)`, y nil si la puntuación es 0. [plausible]
- Los `try?` de `TranscriptionEngine.swift:323,327` se tragan el `CancellationError`; añadir `try Task.checkCancellation()`.
- En `.auto` solo se cae a Whisper ante `unsupportedLanguage`. Si falla la descarga del asset de Apple, el usuario ve un error.
- Se piden `.volatileResults` y luego se descartan, que es trabajo inútil (`SpeechTranscriptionManager.swift:62,195`).
- APIs obsoletas: `Text + Text` (`SuspiciousTermsView.swift:141-144`, warning confirmado) y `.cornerRadius` (`CorrectionReviewView.swift:273`).
- `suspiciousTerms` calcula los snippets de todos los candidatos en el MainActor antes de aplicar `prefix(25)` (`SuspiciousTermsView.swift:148`).

### C17 · MEDIA · Privacidad: PCC activado por defecto en una app "local" [leído]
- **Dónde**: `MeetingNotesService.swift:41-45`, `:221-261`; `LocalSettingsView.swift:7`; `MacSettingsView.swift:7`.
- **Problema**:
  - El texto se envía a Private Cloud Compute sin que el usuario lo haya activado. En Mac funciona de verdad.
  - La salida de PCC no pasa por `validate` (citas).
  - Las `instructions` del usuario no tienen límite.
  - La fusión final no está acotada.
  - Con PCC no se informa del progreso.
- **Solución**: `false` por defecto, la misma validación que en local y acotar la fusión.

---

## 2. App iOS (incluye Share y Widgets)

### I1 · CRÍTICA · Una llamada corta la grabación sin aviso [leído]
- **Dónde**: `Transcriber/AudioRecorderManager.swift:45-92`, `:163-169`; `RecordingView.swift:86-91`. Un grep de `interruption`/`routeChange` no da ningún resultado.
- **Problema**: ante una llamada, Siri o una alarma, `AVAudioRecorder` se pausa y no se reanuda, pero la UI y la Live Activity siguen contando. Si el sistema termina la grabación con `flag == false`, no se paran los timers ni se cierra la Live Activity, y el `.m4a` se queda sin entrada en la biblioteca.
- **Consecuencia**: si hay una llamada en el minuto 10 de una reunión de 1 h, solo se guardan 10 minutos y nadie avisa.
- **Solución**: observar `interruptionNotification` (y reanudar si llega `.shouldResume`) y `mediaServicesWereReset`; implementar `audioRecorderEncodeErrorDidOccur`; en el camino de fallo, llamar a `stopRecording()` y dar de alta la entrada.

### I2 · ALTA · Sin recuperación si la app muere a mitad de grabación [leído]
- **Dónde**: `RecordingView.swift:55-68`, `:277-298`.
- **Problema**: el `Transcription` se crea solo al pulsar "Save" o "Transcribe". Si la app muere, el `.m4a` (AAC) queda sin finalizar y probablemente ilegible. Cancel después de Stop deja un fichero huérfano, y no hay escaneo de huérfanos al arrancar.
- **Solución**: crear la entidad al empezar a grabar, con estado "grabando". Grabar en `.caf` o por segmentos, y recuperar los huérfanos al arrancar.

### I3 · ALTA · En iPad, abrir el detalle durante una grabación cambia la sesión de audio a `.playback` [leído / efecto plausible]
- **Dónde**: `TranscriptReaderPane.swift:93`, `:279-280`; `TranscriptPlayerView.swift:246-247`.
- **Problema**: `setCategory(.playback)` y `setActive(true)` se ejecutan en `onAppear`, no al pulsar play.
- **Consecuencia**: el micrófono deja de capturar mientras la UI sigue en "grabando", y se corta el audio de otras apps con solo abrir el detalle.
- **Solución**: no tocar la sesión si hay una grabación activa, y activarla al pulsar play.

### I4 · ALTA · "Stop Recording" en segundo plano transcribe antes de guardar [leído]
- **Dónde**: `Transcriber/AppIntents/StopRecordingIntent.swift:27-58`.
- **Problema**: fuerza `"multilingual"` (large-v3, con descarga si falta), transcribe todo y solo al final crea la entidad. Además ignora el motor y el idioma que haya elegido el usuario.
- **Consecuencia**: si el intent supera el tiempo de ejecución o falla, la grabación ya está parada y el audio queda fuera de la biblioteca.
- **Solución**: guardar primero la entrada solo con audio y transcribir después, en la app o con `BGContinuedProcessingTask`.

### I5 · ALTA · Cada intent crea su propio `ModelContainer` con otra configuración de CloudKit [leído / efecto plausible]
- **Dónde**: `StopRecordingIntent.swift:41-43,60-62`, `StopRecordingLiveActivityIntent.swift:23-25`, `GetTranscriptionsIntent.swift:31-32`, `SearchTranscriptionsIntent.swift:30-31`, `TranscribeAndSaveIntent.swift:103` (`.none`). La app usa `.private(...)` en `TranscriberApp.swift:42-46`.
- **Problema**: hay varios coordinadores sobre el mismo `default.store` dentro del mismo proceso.
- **Consecuencia**: es posible que la UI no vea la inserción, que el registro no se exporte a CloudKit, o que el intent falle después de haber transcrito.
- **Solución**: un único `ModelContainer` estático compartido por la app y todos los intents.

### I6 · MEDIA · La importación desde Share borra el original aunque la copia falle [leído]
- **Dónde**: `Transcriber/TranscriberApp.swift:186-217`.
- **Problema**:
  - `try? saveAudio`, y luego se borra el original igualmente.
  - El JSON pendiente se borra antes del `try? context.save()`.
  - La importación solo corre en `onAppear`, no al volver a primer plano.
  - `ShareExtensionView.swift:113` muestra "Saved" aunque no haya App Group.
- **Consecuencia**: con el disco lleno se pierden el audio y la transcripción compartidos.
- **Solución**: borrar solo tras copiar y guardar con éxito, e importar también cuando `scenePhase` pase a `.active`.

### I7 · MEDIA · La extensión Share es una copia que ya diverge de la app [leído]
- **Dónde**: `TranscriberShare/ShareHybridTranscriptionService.swift` (unas 500 líneas copiadas) y `TranscriberShare/WhisperModelManager.swift`.
- **Problema**:
  - `.auto` significa Whisper también para es/en.
  - Falta el modelo small y no conoce Voz.
  - No comprueba la cancelación.
  - Descarga los 626 MB en su propio contenedor (sin `downloadBase` del App Group) y sin progreso, dentro del límite de memoria de una extensión.
  - Las copias temporales `share-*` no se borran (`ShareExtensionView.swift:81`).
- **Solución**: un único código compartido por los dos targets. En Share: Apple para los idiomas que admite, y Whisper solo si el modelo ya existe en el App Group; si no, dejar el audio en cola para la app.

### I8 · MEDIA · La importación de audio bloquea la UI y deja ficheros huérfanos [leído]
- **Dónde**: `ImportAudioView.swift:60-68`, `:205`, `:277-288`, `:474`.
- **Problema**: la copia es síncrona, en el hilo principal y sin `NSFileCoordinator`, así que un fichero de iCloud que no esté descargado cuelga la UI. Las copias no se borran al cancelar, al cambiar de fichero ni si la transcripción falla.
- **Solución**: copiar a tmp en segundo plano con coordinación de ficheros y mover a `Audio/` solo después de guardar.

### I9 · MEDIA · `translocalai://record`: el título se usa como nombre de fichero y cualquier app puede arrancar el micrófono [leído]
- **Dónde**: `TranscriberApp.swift:97-115`; `AudioRecorderManager.swift:50-54`; `TranscribeAndSaveIntent.swift:64-68`.
- **Problema**: un título como "Reunión 1/2", o de más de 255 bytes, hace que la grabación no arranque, y solo queda un `NSLog`. Cualquier app puede abrir la URL y empezar a grabar sin confirmación (lo mitiga que la app pasa a primer plano).
- **Solución**: nombrar los ficheros con UUID y guardar el título solo en el modelo, mostrar un error visible y, opcionalmente, pedir confirmación cuando la grabación viene de una URL.

### I10 · MEDIA · Live Activities que no se cierran y un botón de stop que no hace nada [leído]
- **Dónde**: `AudioRecorderManager.swift:143-159`; `TranscriberWidgets/RecordingLiveActivity.swift:70-75`; `StopRecordingLiveActivityIntent.swift`.
- **Problema**:
  - Si la app muere, la actividad sigue viva y no se limpia al arrancar.
  - El "stop" es un `Image`, no un `Button(intent:)`.
  - `StopRecordingLiveActivityIntent` no se usa, y `TranscriptionLiveActivity` es código muerto.
- **Solución**: al arrancar, cerrar las actividades si no se está grabando. Convertir el intent en un `LiveActivityIntent` compartido con el widget.

### I11 · MEDIA · No hay `PrivacyInfo.xcprivacy` en ningún target [leído]
- **Problema**: se usa `UserDefaults`/`@AppStorage`, que es una "required reason API". Sin el manifiesto, la subida a App Store Connect puede dar ITMS-91053.
- **Solución**: añadir el manifiesto a la app, Share, Widgets y Mac con `NSPrivacyAccessedAPICategoryUserDefaults` (razones CA92.1 y 1C8F.1), y comprobar si el SDK de Voz trae el suyo.

### I12 · MEDIA · "Retranscribe" sobrescribe las ediciones sin confirmar [leído]
- **Dónde**: `TranscriptionDetailView.swift:604-606`, `:824-827`.
- **Solución**: un `confirmationDialog`, o guardar la versión anterior.

### I13 · BAJA · Varios de la app
- **Rendimiento del detalle** con textos largos: `TranscriptReaderPane.init` vuelve a hacer `parseBlocks` en cada render; `wordCount` y `resolvedAudioURL` (con `fileExists`) se recalculan en cada `body`; el `TextEditor` enlazado al modelo marca el registro como modificado (y se exporta a CloudKit) en cada tecla. Solución: cachear en `@State`/`onChange` y editar sobre un borrador.
- **Deployment target**: Share está en 26.2 y la app en 26.0, así que Share no aparece en 26.0-26.1. Igualarlos.
- **`CloudSyncStatus`** dice "Syncing" solo por `accountStatus`, aunque la exportación falle. Hay que recordar desplegar el esquema de CloudKit a Production.
- **Info.plist de iOS**: `NSServices` está vacío y es una clave de macOS.
- **Ficheros `.md`**: los de `Transcriber/` se empaquetan dentro del IPA (carpeta sincronizada). Los 11 de `Transcriber.xcodeproj/` están versionados ahí dentro. Moverlos a `docs/`.
- **Permisos**: `ImportAudioView` y los intents exigen el permiso de `SFSpeechRecognizer` aunque el motor sea Whisper o Voz.
- **Grabación**: el `levelTimer` a 10 Hz sigue actualizando el estado observable en segundo plano durante horas (batería).
- **Warning**: `try?` sin usar en `TranscriberApp.swift:189`.

---

## 3. App macOS

### M1 · ALTA · El Mac no guarda nada y, al cerrar la ventana, la app queda inaccesible [leído]
- **Dónde**: `TranscriberMac/MacMainView.swift:5-19`, `:57-61`; `TranscriberMac/Info.plist` (`LSUIElement = true`); no existe ningún `MenuBarExtra`. Un grep de SwiftData/ModelContainer en `TranscriberMac/` no da ningún resultado.
- **Problema**:
  - La transcripción y las notas son solo `@State`, sin SwiftData ni iCloud, así que Cmd+W pierde una hora de transcripción.
  - La `Task` no se cancela al cerrar.
  - Sin icono en el Dock ni en la barra de menús, no hay forma de volver a la app.
  - El texto "Stored on this Mac" es falso.
  - Las transcripciones del iPhone no aparecen en el Mac.
- **Solución**: quitar `LSUIElement` (o añadir un `MenuBarExtra`) y persistir con el mismo modelo y el mismo contenedor CloudKit, añadiendo el entitlement de iCloud.

### M2 · MEDIA · PCC se usa de verdad por defecto en Mac
- Ver C17. El Mac sí tiene el entitlement, así que el texto sale del dispositivo sin que el usuario lo haya activado.

---

## 4. Proyecto / build

### P1 · MEDIA · WhisperKit sigue la rama `main` [leído]
- **Dónde**: `project.pbxproj:1178-1182` (`kind = branch; branch = main`). Solo `Package.resolved` lo fija a `ba09449`.
- **Consecuencia**: un "Update Packages" o una resolución en CI pueden cambiar el comportamiento sin que nadie se dé cuenta.
- **Solución**: fijar `exactVersion`, como ya se hace con Voz 4.2.3.

### P2 · BAJA · La suite de tests no puede salir en verde en el simulador [ejecutado]
- **Dónde**: `TranscriberTests/MeetingNotesProbeTests.swift:35-45`.
- **Problema**: la guarda depende de `hasPrivateCloudComputeEntitlement` (C1), así que el probe tumba el runner y todo el run acaba en `TEST FAILED`, aunque los 53 tests pasen.
- **Solución**: se arregla con C1. Mientras tanto, sacar los probes del plan por defecto.

## Seguridad: sin hallazgos

- No hay secretos en el repo (grep de key, token, secret, license, bearer y `hf_`).
- No se necesita Keychain, porque la app no guarda credenciales.
- No hay excepciones de ATS.
- Protección de ficheros por defecto (clase C), compatible con grabar con el teléfono bloqueado.
- Endpoints que se contactan:
  - Hugging Face (también offline, ver C2)
  - Desert Ant Labs (modelo y licencia de Voz, declarado en `PRIVACY_VOZ.md`)
  - CloudKit/KVS
  - PCC

## Lo que está bien

- El modelo SwiftData es compatible con CloudKit: atributos opcionales o con valor por defecto, sin `unique` ni relaciones, y el audio fuera del modelo. Si CloudKit falla, cae a un store local.
- La aplicación de la revisión IA es segura: sustitución palabra por palabra en la ocurrencia validada, aprobación del usuario y comprobación de la instantánea.
- `correcting` es correcto en Unicode (rangos UTF-16 sobre una fuente inmutable, con benchmark).
- `VozLanguagePolicy` valida el idioma antes de descargar y está bien testeado.
- Los offsets de timestamps de VAD y de los huecos recuperados son correctos.
- Bundle IDs, App Group y contenedor iCloud son coherentes; `ITSAppUsesNonExemptEncryption` está en todos los targets.

## Orden de arreglo sugerido

1. **C1** (crash) y **I1/I2** (pérdida de grabaciones).
2. **C3/C4/C9** (corrupción del texto; arreglos pequeños y testeables).
3. **C2** (offline) y **P1** (pin de WhisperKit).
4. **I4/I5/I6** (pérdida de datos en intents y Share) e **I11** (requisito para subir a App Store Connect).
5. **C6/C7** (memoria; hay que medirlos en dispositivo antes de rediseñar).
6. **M1** (decidir qué es la app de Mac antes de tocarla).
