La solution complète se trouve dans [`02_exercices_sujet/exercice10`](../02_exercices_sujet/exercice10/README.md).

```bash
cd 02_exercices_sujet/exercice10
cp .env.example .env
docker-compose up -d --build
docker-compose ps
curl http://localhost:8080/api/info/env

curl -i -X POST http://localhost:8080/api/notes \
  -H 'Content-Type: application/json' \
  -d '{"title":"Test persistance","content":"Cette note doit survivre aux redémarrages.","category":"TEST","priority":"MEDIUM"}'
curl http://localhost:8080/api/notes

docker-compose down
docker-compose up -d
sleep 20
curl http://localhost:8080/api/notes

# Modifier APP_NAME dans .env et recréer uniquement l'application :
docker-compose up -d --force-recreate app
curl http://localhost:8080/api/info/app

# Supprimer les données ajoutées; le script d'initialisation réinsère les notes de démonstration.
docker-compose down -v
docker-compose up -d
sleep 20
curl http://localhost:8080/api/notes
```
