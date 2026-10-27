# KickUnblock

App iPhone pour regarder Kick : directs avec le chat, VODs et clips des chaînes,
recherche, catégories et chaînes suivies. Construite comme TwitchUnblock : projet
XcodeGen, IPA non signée compilée par GitHub Actions, source d'installation
`apps.json` (AltStore, SideStore, Feather).

## Comment elle lit Kick

- Données : l'API de kick.com (`/stream/livestreams`, `/api/v2/channels/…`,
  `/api/search`, `/api/v1/subcategories`), avec des requêtes simples de l'app
  (URLSession et son User-Agent) — sans imiter un navigateur ni l'app Kick.
- Vidéo : le lecteur d'iOS lit directement les flux HLS de Kick (Amazon IVS pour
  les directs, `stream.kick.com` pour les VODs, `clips.kick.com` pour les clips).
- Chat : les derniers messages, relus toutes les 3 s (historique public du chat).
  Kick n'utilise plus l'ancienne connexion Pusher en direct.
- Suivis : gardés sur l'iPhone.

Si Kick refuse les requêtes de l'app, elle affiche « Kick refuse les requêtes de
l'app (erreur 403) » : dans ce cas, pas de contournement de son filtre anti-robots.

## Installer

Après le premier build de la CI : ajouter la source
`https://raw.githubusercontent.com/MXFia19/KickUnblock/main/apps.json` dans
AltStore, SideStore ou Feather, ou télécharger `KickUnblock.ipa` dans les releases.

## Développer

- Code : `Sources/` (SwiftUI, iOS 16 et plus).
- Build : chaque push sur `main` qui touche l'app (`.github/workflows/build.yml`).
- `worker/` : Worker Cloudflare d'essai (relais de l'API et des flux pour un site
  web), pas utilisé par l'app.
