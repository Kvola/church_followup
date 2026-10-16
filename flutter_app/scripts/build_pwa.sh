#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# BUILD DE LA PWA — Suivi Évangélisation, servie par Odoo sur /suivi-evangelisation
#
#   ./scripts/build_pwa.sh                # analyse + tests, puis installe
#   ./scripts/build_pwa.sh --skip-checks  # sans vérifier (à éviter)
#
# La PWA et l'APK partagent le code, JAMAIS l'artefact : reconstruire l'un ne
# reconstruit pas l'autre. Un correctif non déployé se comporte exactement
# comme un correctif raté.
#
# Notifications web (facultatives) : FCM_WEB_APP_ID et FCM_VAPID_KEY, deux
# identifiants PUBLICS du projet Firebase. Absents, la PWA fonctionne sans
# notifications ; présents, ils sont compilés dans l'app ET écrits dans le
# service worker, pour que les deux ne divergent jamais.
#
# Sortie : addons/church_followup/static/suivi_app/
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

cd "$(dirname "$0")/.."
APP_DIR="$(pwd)"
TARGET="$APP_DIR/../static/suivi_app"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { printf '%b\n' "${YELLOW}$*${NC}"; }
ok()   { printf '%b\n' "${GREEN}$*${NC}"; }
die()  { printf '%b\n' "${RED}✗ $*${NC}" >&2; exit 1; }

RUN_CHECKS=1
[ "${1:-}" = "--skip-checks" ] && RUN_CHECKS=0

if [ "$RUN_CHECKS" -eq 1 ]; then
    info '▶ Analyse statique…'
    flutter analyze || die "l'analyse échoue — rien n'est publié."
    info '▶ Tests…'
    flutter test || die "des tests échouent — rien n'est publié."
    info '▶ Tests dans le navigateur (ce que la VM ne voit pas : kIsWeb)…'
    flutter test --platform chrome test/web_login_test.dart \
        || die "la connexion échoue dans le navigateur — rien n'est publié."
fi

# `--base-href` = `pwa_root` du contrôleur = `scope` du manifeste. Désaccordés :
# l'application s'installe puis ne retrouve plus ses fichiers (page blanche).
BASE_HREF='/suivi-evangelisation/'
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //')
DEFINES=(--dart-define="APP_VERSION=$VERSION")
if [ -n "${FCM_WEB_APP_ID:-}" ] && [ -n "${FCM_VAPID_KEY:-}" ]; then
    DEFINES+=(--dart-define="FCM_WEB_APP_ID=$FCM_WEB_APP_ID" --dart-define="FCM_VAPID_KEY=$FCM_VAPID_KEY")
    info "▶ Notifications web : activées (app Web $FCM_WEB_APP_ID)"
else
    info "▶ Notifications web : désactivées (FCM_WEB_APP_ID / FCM_VAPID_KEY non fournis)"
fi

info "▶ Construction du bundle web (base-href $BASE_HREF)…"
# Aucun BASE_URL : sur le web l'adresse reste vide (AppConstants.serverUrl).
flutter build web --release --base-href="$BASE_HREF" "${DEFINES[@]}" || die 'build web a échoué.'

# ── Gardes : on vérifie le binaire, pas l'intention ──────────────────────
# `grep -c` et non `-q` : sous pipefail, un -q qui trouve ferait échouer le tuyau.
for MOTIF in 'localhost:8069' 'iyf.ebng.world'; do
    TROUVE=$(grep -c "$MOTIF" "$APP_DIR/build/web/main.dart.js" || true)
    [ "${TROUVE:-0}" -eq 0 ] || die "le bundle contient une adresse en dur ($MOTIF) :
   sur le web, AppConstants.serverUrl doit rester vide."
done
ok '✓ Aucune adresse de serveur en dur dans le bundle'
grep -c "<base href=\"$BASE_HREF\"" "$APP_DIR/build/web/index.html" >/dev/null \
    || die "index.html ne porte pas <base href=\"$BASE_HREF\">."
grep -c "\"scope\": \"$BASE_HREF\"" "$APP_DIR/build/web/manifest.json" >/dev/null \
    || die "manifest.json n'a pas le scope $BASE_HREF."
ok "✓ base-href et scope accordés à $BASE_HREF"

# Service worker des notifications : écrit depuis les MÊMES valeurs que l'app.
SW="$APP_DIR/build/web/firebase-messaging-sw.js"
if [ -n "${FCM_WEB_APP_ID:-}" ] && [ -n "${FCM_VAPID_KEY:-}" ]; then
    sed "s|__FCM_WEB_APP_ID__|$FCM_WEB_APP_ID|" "$APP_DIR/web/firebase-messaging-sw.template.js" > "$SW"
    grep -c "__FCM_WEB_APP_ID__" "$SW" >/dev/null && die "service worker non renseigné." || true
    ok '✓ Service worker des notifications écrit'
fi
rm -f "$APP_DIR/build/web/firebase-messaging-sw.template.js"

if [ -d "$TARGET" ]; then
    BACKUP="$APP_DIR/build/bundles/suivi_app-bundle-$(date +%Y-%m-%d-%H%M).tgz"
    mkdir -p "$(dirname "$BACKUP")"
    tar czf "$BACKUP" -C "$(dirname "$TARGET")" "$(basename "$TARGET")"
    info "  ancien bundle archivé : $BACKUP"
fi
rm -rf "$TARGET"
cp -R "$APP_DIR/build/web" "$TARGET"

ok "✅ PWA installée : church_followup/static/suivi_app ($(du -sh "$TARGET" | cut -f1)), version $VERSION"
info '📲 Servie sur https://<odoo>/suivi-evangelisation'
info "   Le service worker garde l'ancienne version tant qu'il n'est pas rafraîchi :"
info "   rechargez de force, ou fermez puis rouvrez l'application installée."
