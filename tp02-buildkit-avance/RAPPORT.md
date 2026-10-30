# Rapport — TP02 BuildKit avancé

Les livrables sont dans `tp02-buildkit-avance/`. Les commandes de build directes sont à lancer depuis ce dossier ; elles utilisent les sources conservées dans `26-10/tp02-buildkit-avance/starter/shop-worker`. Le `pip.conf` local pointe vers PyPI, est ignoré par Git et exclu du contexte Docker ; il est transmis au builder uniquement avec `--secret`.

## 1. Fuite du secret

Un `ARG` n'est pas un mécanisme de gestion de secrets. Une valeur peut être exposée dans l'historique de build (`docker history --no-trunc`), dans les logs/commandes CI et dans le cache si elle est interpolée dans une instruction `RUN` ou écrite dans un fichier. Si elle est recopiée dans `ENV`, elle apparaît aussi dans `docker inspect` sous `.Config.Env`. `ARG` seul n'est pas nécessairement visible dans `.Config.Env` : l'absence dans `docker inspect` ne rend donc pas son usage sûr. Un fichier créé ou copié dans une couche intermédiaire reste récupérable même s'il est supprimé dans une couche suivante.

Avec un montage BuildKit de type `secret`, le contenu n'est ni ajouté à l'image ni au cache de couche. Le montage n'existe que pendant le `RUN` concerné. Le fichier monté n'est jamais copié dans l'image finale.

La démonstration effective avec `docker history` n'a pas pu être exécutée ici, faute de daemon Docker.

## 2. Montage de secret

```bash
docker build --file Dockerfile \
  --secret id=pipconf,src=../26-10/tp02-buildkit-avance/starter/shop-worker/pip.conf \
  -t worker:1.0 ../26-10/tp02-buildkit-avance/starter/shop-worker
docker history --no-trunc worker:1.0
docker run --rm worker:1.0 cat /etc/pip.conf
```

La dernière commande doit échouer car `/etc/pip.conf` n'existe pas dans l'image finale ; c'est le résultat attendu. Le `RUN` de pip voit le fichier pendant l'installation seulement. Pour des dépendances Git privées, `--mount=type=ssh` transmet l'agent SSH au build sans copier la clé privée. Un token peut être fourni par `--secret id=TOKEN,env=TOKEN`, puis consommé dans un `RUN --mount=type=secret,id=TOKEN,env=TOKEN`; il ne faut pas le convertir en `ARG` ou `ENV`.

## 3. Cache pip

Le Dockerfile place les fichiers de dépendances avant le code applicatif. Un changement de code ne réexécute donc pas l'installation. Un changement de `requirements.txt` invalide sa couche d'installation, mais le cache mount `/root/.cache/pip` peut fournir les distributions déjà téléchargées. Son identifiant inclut `TARGETARCH`, afin de séparer les wheels amd64 et arm64.

| Mesure demandée | Temps constaté |
|---|---|
| Premier `docker build` avec secret | Non mesuré : le daemon Docker n'est pas disponible dans cet environnement |
| Rebuild après purge du cache de couches | Non mesuré |
| Rebuild après ajout d'une dépendance | Non mesuré |

Commandes de mesure à exécuter sur un builder fonctionnel :

```bash
time docker build --file Dockerfile \
  --secret id=pipconf,src=../26-10/tp02-buildkit-avance/starter/shop-worker/pip.conf \
  -t worker:1.0 ../26-10/tp02-buildkit-avance/starter/shop-worker
docker builder prune -f
time docker build --file Dockerfile \
  --secret id=pipconf,src=../26-10/tp02-buildkit-avance/starter/shop-worker/pip.conf \
  -t worker:1.0 ../26-10/tp02-buildkit-avance/starter/shop-worker
echo "requests==2.32.3" >> ../26-10/tp02-buildkit-avance/starter/shop-worker/requirements.txt
time docker build --file Dockerfile \
  --secret id=pipconf,src=../26-10/tp02-buildkit-avance/starter/shop-worker/pip.conf \
  -t worker:1.0 ../26-10/tp02-buildkit-avance/starter/shop-worker
# Retirer ensuite cette ligne de test de requirements.txt.
```

**Attention au commentaire de l'énoncé :** le cache mount est distinct du cache de couches, mais il n'est pas garanti qu'un `docker builder prune -f` le préserve. Buildx expose les enregistrements `exec.cachemount` à `buildx prune`; pour purger les autres entrées en conservant ce type, utiliser `docker buildx prune -f --filter 'type!=exec.cachemount'` et vérifier le comportement du builder employé. `--no-cache` force les instructions à se réexécuter, mais ne désactive pas à lui seul un cache mount encore présent.

Référence : [documentation `docker buildx prune`](https://docs.docker.com/reference/cli/docker/buildx/prune/), qui liste `exec.cachemount` parmi les types de cache filtrables.

## 4. Multi-architecture

Mesure non réalisée : `docker version` ne trouve pas de daemon et `docker buildx` n'est pas installé. Avec le builder `docker-container` de l'exercice, exporter est nécessaire pour récupérer un résultat multi-plateforme : pousser vers un registre ou exporter un OCI layout.

```bash
docker buildx create --name shop --driver docker-container --use
docker buildx inspect --bootstrap
docker buildx build --platform linux/amd64,linux/arm64 \
  --secret id=pipconf,src=../26-10/tp02-buildkit-avance/starter/shop-worker/pip.conf \
  -t localhost:5000/shop-worker:1.0 --push \
  ../26-10/tp02-buildkit-avance/starter/shop-worker
docker buildx imagetools inspect localhost:5000/shop-worker:1.0
```

Alternative sans registre :

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  --secret id=pipconf,src=../26-10/tp02-buildkit-avance/starter/shop-worker/pip.conf \
  -t shop-worker:1.0 --output type=oci,dest=worker.tar \
  ../26-10/tp02-buildkit-avance/starter/shop-worker
```

L'index (manifest list) référence un manifeste par plateforme ; chaque manifeste référence sa configuration et ses couches. Le client choisit le manifeste correspondant à l'OS et à l'architecture de la machine. Les versions récentes de Docker avec le magasin d'images containerd peuvent aussi conserver des index multi-plateformes localement ; le builder `docker-container` ne charge toutefois pas automatiquement son résultat dans le magasin local.

`TARGETARCH` est un argument BuildKit prédéfini. Le Dockerfile le déclare dans chaque stage qui l'utilise et l'insère dans l'identifiant du cache pip (`pip-${TARGETARCH}`), pour éviter de partager des wheels incompatibles. Un build arm64 sur un hôte amd64 est plus lent sous QEMU car les instructions sont émulées. Pour accélérer, ajouter des nœuds natifs amd64 et arm64 au même builder avec `docker buildx create --append`, puis répartir les plateformes sur ces nœuds.

## 5. Cache distant

Le cache mount pip reste associé au stockage du builder ; il n'est pas le cache distant exporté dans le registre. Entre runners, ce sont les couches BuildKit exportées qui peuvent être réutilisées lorsque leurs entrées correspondent.

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  --secret id=pipconf,src=../26-10/tp02-buildkit-avance/starter/shop-worker/pip.conf \
  --cache-from type=registry,ref=localhost:5000/cache:worker \
  --cache-to type=registry,ref=localhost:5000/cache:worker,mode=max \
  -t localhost:5000/shop-worker:1.0 --push \
  ../26-10/tp02-buildkit-avance/starter/shop-worker
```

En CI, Buildx propose également `type=gha` pour GitHub Actions et `type=s3` pour un stockage S3 compatible, sous réserve de la configuration et des permissions correspondantes. `mode=min` exporte le cache nécessaire aux couches de l'image finale ; `mode=max` inclut les couches des stages intermédiaires, utile ici pour réutiliser les étapes builder et test.

## 6. Buildx Bake

`docker-bake.hcl` est placé à la racine du TP02. Le groupe `default` construit l'API du TP01 et le worker. La cible abstraite `_common` partage les plateformes, labels OCI et sources de cache ; les cibles écrivent dans des références de cache distinctes. Les builds d'images poussent vers `REGISTRY` et `worker-test` ne produit pas d'image.

Depuis `tp02-buildkit-avance` :

```bash
docker buildx bake --print
VERSION=1.0 GIT_SHA="$(git rev-parse --short HEAD)" docker buildx bake worker-test
platform="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
VERSION=1.0 docker buildx bake --set "*.platform=linux/${platform}" --load
```

`worker-test` lit et exporte aussi le cache distant configuré, mais son export `type=cacheonly` ne pousse pas d'image applicative.

Le groupe `default` et les cibles d'image nécessitent le registre configuré (par défaut `localhost:5000`) pour les images et le cache distant. `worker-test` construit uniquement le stage `test`; son export `type=cacheonly` n'ajoute pas d'image au registre.

## État des mesures

Les mesures de temps et l'inspection effective des manifestes restent à réaliser sur un environnement où le daemon Docker et Buildx sont disponibles. La CLI présente ici est Docker 29.9.1, mais aucun serveur Docker ne répond sur le socket Colima et la commande `docker buildx` est inconnue ; aucun chiffre n'a été inventé.
