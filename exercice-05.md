```bash
docker network create mysql-adminer-net
docker volume create mysql-data
docker run -d --name mysql-db --network mysql-adminer-net --restart unless-stopped -e MYSQL_ROOT_PASSWORD=rootpass123 -e MYSQL_DATABASE=app_db -e MYSQL_USER=app_user -e MYSQL_PASSWORD=app_pass123 -v mysql-data:/var/lib/mysql mysql:8.4
until docker exec mysql-db mysqladmin ping -h 127.0.0.1 -u root -prootpass123 --silent; do sleep 2; done
docker run -d --name adminer-db --network mysql-adminer-net --restart unless-stopped -e ADMINER_DEFAULT_SERVER=mysql-db -p 127.0.0.1:8080:8080 adminer
docker exec mysql-db mysql -u app_user -papp_pass123 app_db -e "CREATE TABLE exercices (id INT AUTO_INCREMENT PRIMARY KEY, nom VARCHAR(100) NOT NULL); INSERT INTO exercices (nom) VALUES ('Docker'), ('MySQL'), ('Adminer');"
open http://localhost:8080
docker exec mysql-db mysql -u app_user -papp_pass123 app_db -e "SELECT * FROM exercices;"
docker rm -f mysql-db
docker run -d --name mysql-db --network mysql-adminer-net --restart unless-stopped -e MYSQL_ROOT_PASSWORD=rootpass123 -e MYSQL_DATABASE=app_db -e MYSQL_USER=app_user -e MYSQL_PASSWORD=app_pass123 -v mysql-data:/var/lib/mysql mysql:8.4
until docker exec mysql-db mysqladmin ping -h 127.0.0.1 -u root -prootpass123 --silent; do sleep 2; done
docker exec mysql-db mysql -u app_user -papp_pass123 app_db -e "SELECT * FROM exercices;"
docker kill mysql-db
sleep 5
docker inspect --format '{{.State.Status}}' mysql-db
docker exec mysql-db mysql -u app_user -papp_pass123 app_db -e "SELECT * FROM exercices;"
docker rm -f adminer-db mysql-db
cat > compose.yaml <<'EOF'
services:
  mysql:
    image: mysql:8.4
    container_name: mysql-compose
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: rootpass123
      MYSQL_DATABASE: app_db
      MYSQL_USER: app_user
      MYSQL_PASSWORD: app_pass123
    volumes:
      - mysql-data:/var/lib/mysql
    networks:
      - mysql-adminer-net
  adminer:
    image: adminer
    container_name: adminer-compose
    restart: unless-stopped
    environment:
      ADMINER_DEFAULT_SERVER: mysql-compose
    ports:
      - "127.0.0.1:8080:8080"
    networks:
      - mysql-adminer-net
volumes:
  mysql-data:
    external: true
networks:
  mysql-adminer-net:
    external: true
EOF
docker compose up -d
until docker exec mysql-compose mysqladmin ping -h 127.0.0.1 -u root -prootpass123 --silent; do sleep 2; done
open http://localhost:8080
docker exec mysql-compose mysql -u app_user -papp_pass123 app_db -e "SELECT * FROM exercices;"
```
