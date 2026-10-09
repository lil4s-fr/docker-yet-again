Les deux applications complètes (API CRUD, API de logs, MySQL et Docker Compose) se trouvent dans [`exercise-09`](../exercise-09/README.md).

```bash
cd exercise-09
cp .env.example .env
docker-compose up --build -d
docker-compose ps

curl -i http://localhost:8080/api/v1/dogs
curl -i -X POST http://localhost:8080/api/v1/dogs \
  -H 'Content-Type: application/json' \
  -d '{"name":"Rex","birthDate":"2021-02-10","breed":"Labrador","sterilized":true}'
# Remplacer 1 par l'identifiant retourné par le POST.
curl -i http://localhost:8080/api/v1/dogs/1
curl -i -X PUT http://localhost:8080/api/v1/dogs/1 \
  -H 'Content-Type: application/json' \
  -d '{"name":"Rex","birthDate":"2021-02-10","breed":"Labrador","sterilized":false}'
curl -i -X DELETE http://localhost:8080/api/v1/dogs/1
curl -i http://localhost:8080/api/v1/dogs/999999

curl -i http://localhost:8081/api/v1/logs
docker-compose logs -f crud-api logs-api
docker-compose down
# Pour supprimer aussi les données persistées : docker-compose down -v
```
