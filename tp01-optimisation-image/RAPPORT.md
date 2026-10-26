# Rapport — optimisation de l'image ShopAPI

## Comparaison avant / après

Mesures relevées avec Colima et `docker image ls`; les temps de rebuild dépendent du cache local.

| Mesure | Image historique | Image optimisée `shopapi:1.4.2` |
|---|---:|---:|
| Taille | 1.06 GB | 177 MB |
| Couches filesystem | 9 | 10 |
| Rebuild après changement de source | 19.34 s, `npm install` rejoué | 1.07 s, étapes `npm ci` en cache |
| Utilisateur | `root` (UID 0) | `node` (UID 1000) |
| Arrêt SIGTERM | 10.09 s | 0.11 s |

Le build optimisé sans modification source, cache chaud, a pris `0.27 s`. Le comptage de couches n'a pas diminué; le gain de taille vient surtout de l'absence de la majeure partie de l'image Node et des outils inutiles dans le runtime, pas d'une réduction du nombre de couches.

## Image standard

Le stage `test` s'exécute avec `docker buildx build --target test` : `npm test` passe (1 test) et `npm run lint` réussit. Hadolint ne produit aucune sortie pour `Dockerfile` (code retour 0). Le runtime a répondu `healthy`, `/products` a renvoyé les trois produits mémoire, et les vérifications confirment l'absence de `.env`, du dump SQL et des dépendances `nodemon`/`eslint`. Les labels OCI contiennent la version `1.4.2`, la révision `c9def30` et la source du dépôt.

Pour respecter la limite de 200 MB, le dernier stage est basé sur Alpine 3.23.4 épinglé par digest; il copie le binaire Node 20.20.2 et ses bibliothèques nécessaires depuis l'image officielle `node:20-alpine`, elle aussi épinglée. L'image officielle Node complète mesure à elle seule 194 MB avec le moteur local; la garder telle quelle en runtime dépassait donc la cible une fois les dépendances applicatives ajoutées. Le binaire Node, les dépendances de production et l'utilisateur `node` sont vérifiés dans l'image finale.

## Bonus

**B1 — Distroless.** `Dockerfile.distroless` produit une image de 199 MB, exécutée avec l'utilisateur non-root UID 65532. Le healthcheck utilise `/nodejs/bin/node` pour sonder `/health`; aucun shell ni `wget` n'est disponible, ce qui réduit les possibilités de diagnostic interactif. Hadolint ne produit aucune sortie pour ce Dockerfile et le healthcheck/API ont été vérifiés.

**B2 — Cache BuildKit.** Trois builds `--no-cache` identiques côté dépendances ont été chronométrés : sans cache mount `7.64 s`, cache mount froid `4.50 s`, puis cache mount chaud `3.14 s`. La commande `npm ci --omit=dev` a pris respectivement `1.6 s`, `1.5 s` et `1.5 s`; sur ce petit projet et ce réseau, le gain se voit surtout dans le temps total de build. Le mount `id=shopapi-b2b3-npm,target=/root/.npm` reste disponible même lorsque le cache de couches est désactivé. Avec le Dockerfile final, le rebuild après changement de `src/server.js` a pris `1.07 s`; BuildKit a indiqué `CACHED` pour les deux étapes d'installation npm.

**B3 — Reproductibilité OCI.** Deux exports Buildx `type=oci` successifs, avec `--no-cache`, `SOURCE_DATE_EPOCH=1793006927` (timestamp du commit), arguments version/révision fixes, `rewrite-timestamp=true` et provenance désactivée, ont donné le même digest de manifeste : `sha256:d08306d1ad5fb0e54412e1781df219b4acbd23c8eca02fe34e91ae6471eecb0b`. Les deux configs avaient également le digest `sha256:f86bbf60133938236646e7171e41d8132da7f96bb39b41e5153b37d766def119`. Les causes de dérive initiales étaient les tags d'image flottants, l'absence de lockfile et les timestamps de build; les digests de base, le lockfile et les timestamps sont maintenant contrôlés. La provenance BuildKit a été désactivée pour éviter des attestations variables, au prix de ne pas embarquer ces attestations dans ces exports.
