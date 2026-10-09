L'implémentation complète (API Spring Boot, Hibernate/JPA, MySQL et Docker Compose) se trouve dans [`exercise-08`](../exercise-08/README.md).

```bash
cd exercise-08
cp .env.example .env
mvn test
docker compose up --build -d
docker compose ps

curl -i http://localhost:8080/api/v1/dogs
curl -i -X POST http://localhost:8080/api/v1/dogs \
  -H 'Content-Type: application/json' \
  -d '{"name":"Rex","birthDate":"2021-02-10","breed":"Labrador","sterilized":true}'
# Réutiliser l'id retourné par le POST pour les requêtes suivantes.
curl -i http://localhost:8080/api/v1/dogs/1
curl -i -X PUT http://localhost:8080/api/v1/dogs/1 \
  -H 'Content-Type: application/json' \
  -d '{"name":"Rex","birthDate":"2021-02-10","breed":"Labrador","sterilized":false}'
curl -i -X DELETE http://localhost:8080/api/v1/dogs/1

docker compose down
# Pour supprimer également les données MySQL : docker compose down -v
```
