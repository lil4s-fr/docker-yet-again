# Rapport — TP03 Registre privé et supply chain

Les livrables de la solution sont regroupés sous `tp03-registry-supply-chain/` à la racine du dépôt. Les sources de l'exercice restent sous `26-10/tp03-registry-supply-chain/`. Les scripts de certificats et de credentials génèrent uniquement des fichiers locaux ignorés par Git ; aucune clé privée, mot de passe ou SBOM n'est livré. L'UI est liée à loopback pour cet exercice ; pour un accès partagé, placez-la derrière un proxy HTTPS et configurez la validation de la CA interne par le proxy.

## 1. Registre sécurisé

`registry/compose.yml` démarre le registre principal, l'UI Joxit et un miroir pull-through distinct. Le registre principal monte `config.yml`, un volume nommé et des fichiers de certificat/htpasswd générés localement. `generate-certs.sh` crée une CA locale et un certificat serveur dont le SAN comprend `registry.local`; la clé privée de la CA n'est pas montée dans le conteneur. `generate-auth.sh` demande de façon interactive des mots de passe et écrit les deux utilisateurs `ci` et `dev` sous forme bcrypt.

Pour lancer la stack depuis `tp03-registry-supply-chain/` :

```bash
cd registry
./generate-certs.sh
./generate-auth.sh
```

Ajouter `127.0.0.1 registry.local` à `/etc/hosts`, puis installer `certs/registry-ca.crt` dans `/etc/docker/certs.d/registry.local:5000/ca.crt` côté daemon Docker. Le port du registre et celui de l'UI ne sont liés qu'à loopback ; l'UI est disponible sur `http://localhost:8080`. Pour un accès partagé, la placer derrière un proxy HTTPS. Ajouter `daemon.json` à la configuration existante du daemon (ne pas écraser ses autres clés), puis redémarrer Docker pour activer le miroir.

```bash
docker compose up -d
curl --cacert certs/registry-ca.crt https://registry.local:5000/v2/
docker login registry.local:5000 -u ci
docker pull alpine:3.20
docker pull alpine:3.20
docker compose logs mirror
```

Les comptes htpasswd sont authentifiés, mais le registre Distribution n'applique pas de rôles par utilisateur : `ci` et `dev` ont les mêmes droits effectifs sur ce registre. Les nommer « push » et « pull » ne crée pas de contrôle d'accès. En entreprise, Harbor, Nexus ou Artifactory ajoutent notamment RBAC, audit, politiques de scan, réplication, quotas et règles d'immutabilité. ECR, ACR et GAR s'intègrent aux identités IAM et proposent leurs contrôles de gouvernance. Cette démo utilise l'authentification basique uniquement ; elle ne prétend pas fournir la séparation des rôles demandée.

## 2. API Registry et rétention

`registry/registry-api.sh` utilise seulement `curl` et `jq` pour lister le catalogue et les tags, lire le digest avec un `HEAD` et un en-tête `Accept` explicite, puis supprimer un manifeste par digest. L'accès authentifié passe par un fichier netrc protégé, jamais par un mot de passe dans les arguments. Remplacer le placeholder ci-dessous par le mot de passe saisi pour `dev` (ne pas réutiliser cette valeur illustrative comme vrai secret) :

```bash
# Remplacer le placeholder par le mot de passe choisi pour l'utilisateur dev.
cat >"$HOME/.netrc" <<'EOF'
machine registry.local login dev password REPLACE_WITH_THE_PASSWORD_USED_BY_generate-auth.sh
EOF
chmod 600 "$HOME/.netrc"
export REGISTRY_NETRC="$HOME/.netrc"
export REGISTRY_CA_CERT="$PWD/certs/registry-ca.crt"

./registry-api.sh catalog
./registry-api.sh tags shopapi
digest="$(./registry-api.sh digest shopapi 1.4.2)"
./registry-api.sh delete shopapi "$digest"
```

L'API Registry v2 supprime un manifeste par digest, pas un alias individuellement. Si plusieurs tags pointent sur ce digest, les supprimer revient à supprimer tous ces tags. `retention.sh` protège donc tout digest encore référencé par un des N tags conservés et supprime chaque digest obsolète au plus une fois. Il est en simulation par défaut ; `--apply` rend les suppressions effectives. L'API ne publie pas d'horodatage de push pour chaque tag : le script trie par `created` dans la configuration de l'image, et place les images sans cette date en dernier. Ce n'est qu'un proxy de récence, pas un historique de publication fiable.

```bash
./retention.sh shopapi 5
./retention.sh --apply shopapi 5
```

Après suppression de manifestes, arrêter le registre avant de lancer le garbage collector, puis le redémarrer :

```bash
docker compose stop registry
docker compose run --rm --no-deps registry garbage-collect /etc/docker/registry/config.yml
docker compose up -d registry
```

## 3. Tags

`TAGGING.md` définit les tags de version et de commit immuables par convention, les tags de branche/environnement mutables, l'interdiction de `latest` en production, le déploiement par digest, le retag distant et le lien entre signature et digest. Le registre Distribution seul ne peut pas faire respecter l'immutabilité.

## 4–5. SBOM, scan, signature et release gate

`release-gate.sh` vérifie les labels OCI version/révision/source, l'utilisateur non-root et la présence d'un `HEALTHCHECK`, puis bloque sur les CVE HIGH/CRITICAL corrigeables ou tout secret détecté par Trivy. Si la porte passe, Syft génère un SBOM SPDX JSON. `--push REGISTRY_IMAGE` déclenche ensuite le push, la signature Cosign et l'attestation SBOM. Sans `--push`, la validation reste locale. Les commandes autonomes de l'énoncé sont :

```bash
cd ..
syft shopapi:1.4.2 -o spdx-json > sbom.json
jq '.packages | length' sbom.json
trivy image --severity HIGH,CRITICAL --ignore-unfixed shopapi:1.4.2
trivy image --scanners secret shopapi:legacy
cosign generate-key-pair
./release-gate.sh shopapi:1.4.2 --push registry.local:5000/shopapi:1.4.2
cosign verify --key cosign.pub registry.local:5000/shopapi:1.4.2
cosign verify-attestation --key cosign.pub registry.local:5000/shopapi:1.4.2
```

Les commandes de test de l'énoncé restent :

```bash
cd ..
./release-gate.sh shopapi:legacy
./release-gate.sh shopapi:1.4.2 --push registry.local:5000/shopapi:1.4.2
```

Avec le stockage Registry v2 utilisé ici, les artefacts Cosign peuvent apparaître sous des tags de compatibilité tels que `sha256-<digest>.sig` (et des références d'attestation). Les noms exacts dépendent de la version et du mode de stockage. La signature est liée au digest, comme expliqué dans `TAGGING.md`, jamais au nom du tag.

**Validation effective limitée par l'environnement** : `bash -n` passe pour les scripts ; des tests avec outils simulés vérifient les cas passant/refusés de la porte et l'ordre de rétention avec digest partagé ; le générateur bcrypt a produit et validé les comptes `ci`/`dev` ; le script de certificats a généré un certificat vérifié par OpenSSL avec les SAN `registry.local`, `registry` et `127.0.0.1`; les trois fichiers YAML sont analysables. Docker CLI est présent, mais aucun daemon ne répond sur le socket Colima et le plugin Compose est absent ; `syft`, `trivy`, `cosign`, `skopeo` et `crane` ne sont pas installés. Les builds du registre, les scans réels, la génération d'un SBOM d'image et les signatures n'ont donc pas été exécutés. Aucun résultat n'est simulé ou présenté comme réel.
