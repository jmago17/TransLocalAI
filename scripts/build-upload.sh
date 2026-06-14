#!/bin/bash
#
# Archiva, firma (cloud signing) y sube TransLocalAI a App Store Connect sin
# abrir Xcode ni elegir nada en el Organizer. Usa la firma automática gestionada
# por Apple con una API key de ASC — no necesita certificado de distribución
# local (este Mac es desechable y no tiene llavero de firma).
#
# Uso:
#   scripts/build-upload.sh            # archive + export + SUBIDA a ASC
#   scripts/build-upload.sh --export   # archive + export a .ipa (sin subir)
#
# API key de ASC (App Store Connect → Users and Access → Integrations → App Store
# Connect API). Da el .p8 una vez y apunta estas variables (en el entorno o en
# ~/.config/asc-api/config):
#   ASC_KEY_PATH   = ruta absoluta al AuthKey_XXXX.p8
#   ASC_KEY_ID     = el Key ID (10 chars)
#   ASC_ISSUER_ID  = el Issuer ID (UUID)
#
set -euo pipefail

# --- Xcode en SSD externo (ver reference_xcode_external_drive) ---------------
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Volumes/Almacen/Applications/Xcode.app/Contents/Developer}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Transcriber"
PROJECT="$PROJECT_DIR/Transcriber.xcodeproj"
EXPORT_OPTS="$PROJECT_DIR/ExportOptions.plist"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE="$BUILD_DIR/Transcriber.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

MODE="upload"
[ "${1:-}" = "--export" ] && MODE="export"

# --- Cargar config de la API key -------------------------------------------
CONFIG="$HOME/.config/asc-api/config"
[ -f "$CONFIG" ] && . "$CONFIG"

require_key() {
    if [ -z "${ASC_KEY_PATH:-}" ] || [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ]; then
        echo "ERROR: falta la API key de ASC." >&2
        echo "Define ASC_KEY_PATH, ASC_KEY_ID y ASC_ISSUER_ID (en el entorno o en $CONFIG)." >&2
        echo "Ejemplo de $CONFIG:" >&2
        echo "  ASC_KEY_PATH=\$HOME/.config/asc-api/AuthKey_ABC123XYZ.p8" >&2
        echo "  ASC_KEY_ID=ABC123XYZ" >&2
        echo "  ASC_ISSUER_ID=12345678-aaaa-bbbb-cccc-1234567890ab" >&2
        exit 1
    fi
    [ -f "$ASC_KEY_PATH" ] || { echo "ERROR: no existe $ASC_KEY_PATH" >&2; exit 1; }
}

AUTH=(-authenticationKeyPath "${ASC_KEY_PATH:-}" \
      -authenticationKeyID "${ASC_KEY_ID:-}" \
      -authenticationKeyIssuerID "${ASC_ISSUER_ID:-}" \
      -allowProvisioningUpdates)

require_key

rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archivando $SCHEME (Release, device, cloud signing)…"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    "${AUTH[@]}"

echo "==> Exportando (${MODE}) con $EXPORT_OPTS…"
if [ "$MODE" = "export" ]; then
    # IPA local, sin subir: copia del plist con destination=export.
    TMP_OPTS="$BUILD_DIR/ExportOptions.export.plist"
    cp "$EXPORT_OPTS" "$TMP_OPTS"
    /usr/libexec/PlistBuddy -c "Set :destination export" "$TMP_OPTS"
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$TMP_OPTS" \
        -exportPath "$EXPORT_DIR" \
        "${AUTH[@]}"
    echo "✓ IPA en: $EXPORT_DIR"
else
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$EXPORT_OPTS" \
        -exportPath "$EXPORT_DIR" \
        "${AUTH[@]}"
    echo "✓ Subido a App Store Connect."
fi
