# Diagnostic de l'image historique

Les commandes ont été exécutées sur `starter/shopapi` avec Colima. Les valeurs de configuration sensibles ne sont pas reproduites.

## Taille et performance

| Problème | Preuve | Impact |
|---|---|---|
| Image finale supérieure à 1 Go | `docker image ls shopapi:legacy` → `shopapi:legacy 1.06GB` | Transferts et stockage du registre coûteux. |
| Base Ubuntu et outillage système inutiles au runtime | `docker history shopapi:legacy` → couche `apt-get install curl wget vim git build-essential python3` de `379MB`, puis Node de `173MB` | Une image Node dédiée et l'exclusion des outils de build réduisent la taille et la surface runtime. |
| Installations APT fragmentées et cache conservé | `docker history` → couches `apt-get update` de `80.7MB` et `apt-get install` de `379MB`; Hadolint signale `DL3009` et `DL3059` | Les métadonnées et fichiers temporaires persistent dans les couches; les étapes indépendantes augmentent le nombre de couches. |
| Outil de développement installé dans l'image | `docker history` → `npm install -g nodemon`, `7.54MB`; `package.json` classe aussi `nodemon` et `eslint` en dépendances de développement | Dépendances non nécessaires en production ajoutées à l'image. |
| Cache npm invalidé à chaque changement de source | Dans une copie jetable, les deux builds legacy affichent `Step 10/14 : RUN npm install`; temps mesurés : `0.13s` (cache initial) puis `19.34s` après un commentaire dans `src/server.js` | `COPY . /app` précède l'installation, donc chaque changement de code invalide la couche npm. |
| Installation non reproductible | Avant le diagnostic, `test -f package-lock.json` → `package-lock-missing`; le Dockerfile lance `npm install` | Les plages semver peuvent résoudre des versions différentes; `npm ci` ne peut pas garantir le même arbre de dépendances sans lockfile. |

## Sécurité

| Problème | Preuve | Impact |
|---|---|---|
| Processus en root | `docker run --rm shopapi:legacy id` → `uid=0(root) gid=0(root)` | Une compromission du processus dispose des privilèges root dans le conteneur. |
| Fichier `.env` copié dans l'image | `docker run --rm shopapi:legacy ls -la /app` → présence de `/app/.env` | Toute valeur sensible qui s'y trouve est conservée dans les couches de l'image. |
| Paramètre de base de données défini dans l'image | `docker run --rm shopapi:legacy env` avec valeurs masquées → `DATABASE_URL=<redacted>` | La configuration d'environnement est figée dans l'image et visible via sa configuration. |
| Dump SQL copié dans l'image | `docker run --rm shopapi:legacy ls -la /app` → présence de `/app/dump-prod-2024.sql` | Données de production potentiellement exposées et poids inutile dans chaque déploiement. |
| Environnement de développement | Historique Docker → `ENV NODE_ENV=development`; `npm install` installe aussi les dépendances de développement | Le runtime ne suit pas le mode production et embarque des composants supplémentaires. |

## Exploitabilité

| Problème | Preuve | Impact |
|---|---|---|
| Arrêt SIGTERM non transmis directement à Node | `CMD npm start` est en forme shell; `time docker stop shopapi-legacy-stop-probe-e3b270a0` → `real 10.09s`. `src/server.js` possède déjà un handler SIGTERM, mais le shell intermédiaire empêche l'arrêt rapide attendu. | Les déploiements attendent le timeout Docker avant le SIGKILL. |
| Aucun healthcheck | `docker image inspect shopapi:legacy --format '{{json .Config.Healthcheck}}'` → `null` | Docker ne peut pas distinguer un processus lancé d'une API prête. |
| Labels OCI de l'application absents | `docker image inspect shopapi:legacy --format '{{json .Config.Labels}}'` → seulement `org.opencontainers.image.version=22.04` hérité d'Ubuntu | La version, la révision et la source de ShopAPI ne sont pas traçables à partir de l'image. |
| Aucun stage de test dans le build | `docker history shopapi:legacy` ne contient que l'installation npm et le démarrage; aucun `npm test` ni `npm run lint` | Une image peut être publiée sans exécuter les vérifications du projet. |
| Avertissements Hadolint | `hadolint Dockerfile` signale notamment `DL3008` (versions APT non épinglées), `DL4006` (pipe sans `pipefail`), `DL3016` (installation npm non épinglée) et `DL3025` (`CMD` shell) | La recette ne respecte pas les pratiques de construction attendues et a échoué au lint avec son niveau warning. |

L'analyse `dive` a obtenu une efficacité de `99.5983%` et `3.999 MB` d'espace superflu (APT et journaux notamment). Cela ne compense pas les couches lourdes conservées ni les fichiers sensibles/inutiles copiés dans l'image.
