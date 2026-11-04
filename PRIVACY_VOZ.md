# Voz opcional — privacidad y límites

La app principal iOS y macOS incorpora únicamente el producto **Voz** de
[desert-ant-core v4.2.3](https://github.com/Desert-Ant-Labs/desert-ant-core/tree/v4.2.3),
con requisito SPM de versión exacta. Ese SDK fija el modelo **v0.5.0**, aproximadamente
337 MB. No se incorpora Ear ni se habilita Voz en la extensión Share.

[Powered by Desert Ant Labs](https://desertant.com)

La [licencia publicada v1.1](https://license.desertant.com/latest) exige la atribución visible y una comprobación de licencia obligatoria.
Al cargar el modelo, el SDK envía un ID aleatorio de instalación, el ID de la app,
versiones del SDK/modelo y plataforma. No envía audio ni transcripciones. No se ha
modificado, desactivado ni añadido una opción para eludir esa comprobación.
El aviso `LICENSE.md` del tag todavía remite a v1.0; se conserva sin modificar en
la dependencia. El aviso de la app recoge la comprobación de licencia de v1.1
solicitada para esta integración y presente en el código de v4.2.3.
La inferencia se ejecuta localmente; una vez descargado el modelo, puede funcionar
sin conexión aunque falle la comprobación. Esto **no** significa que la app no
haga conexiones: además de la licencia y descarga, siguen existiendo iCloud y las
funciones opcionales de Private Cloud Compute para notas.

Abrir la app, los ajustes o el selector solo consulta la disponibilidad local del
modelo. La descarga y la carga se realizan al iniciar una transcripción con Voz.
La primera carga puede tardar 10–30 segundos; no se promete ese rendimiento en todos
los dispositivos. La cancelación se comprueba antes y después de las operaciones
SDK y antes de guardar: una operación interna puede tardar en terminar y la descarga
puede continuar hasta que el SDK devuelva el control. No se publican resultados
cancelados; no se borra una caché compartida que pueda estar usando otra solicitud.

Voz admite exclusivamente `bg cs da de el en es et fi fr hr hu it lt lv mt nl pl pt
ro ru sk sl sv uk`. Requiere selección explícita de idioma. No detecta idiomas ni
se usa para selección automática. Euskara y multilingüe siguen con WhisperKit,
incluso si quedó seleccionado Voz. Catalán, gallego y otros idiomas no admitidos
se rechazan antes de preparar/descargar Voz. Para audio mixto con Euskara se debe
seleccionar multilingüe/WhisperKit; elegir español no permite descubrir ni proteger
frente a una parte de audio en Euskara.

La extensión Share usa sus motores Apple/WhisperKit y lo indica en pantalla;
no comparte ni interpreta una preferencia Voz de la app. Su memoria con Voz no
se ha validado. Auto y los identificadores de modelos Whisper existentes no cambian.

Validación de esta integración: ver `estado.md` y el informe local
`/tmp/translocal-voz-20261103/result.md`. No se han descargado pesos, transcrito
grabaciones ni probado rendimiento/calidad real durante esta implementación.
