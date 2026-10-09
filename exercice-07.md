```bash
mkdir -p exercise-07
cd exercise-07
cat > init.sql <<'EOF'
CREATE DATABASE IF NOT EXISTS kennelDB;
USE kennelDB;

CREATE TABLE clients (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  nom VARCHAR(100) NOT NULL,
  prenom VARCHAR(100) NOT NULL,
  date_naissance DATE NOT NULL,
  pseudonyme VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE adresses (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  numero VARCHAR(20) NOT NULL,
  rue VARCHAR(150) NOT NULL,
  code_postal VARCHAR(20) NOT NULL,
  commune VARCHAR(100) NOT NULL
);

CREATE TABLE clients_adresses (
  client_id BIGINT NOT NULL,
  adresse_id BIGINT NOT NULL,
  PRIMARY KEY (client_id, adresse_id),
  FOREIGN KEY (client_id) REFERENCES clients(id),
  FOREIGN KEY (adresse_id) REFERENCES adresses(id)
);

CREATE TABLE chiens (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  nom VARCHAR(100) NOT NULL,
  date_naissance DATE NOT NULL,
  race VARCHAR(100) NOT NULL,
  sterilise BOOLEAN NOT NULL,
  client_id BIGINT,
  FOREIGN KEY (client_id) REFERENCES clients(id)
);

CREATE TABLE chats (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  nom VARCHAR(100) NOT NULL,
  date_naissance DATE NOT NULL,
  race VARCHAR(100) NOT NULL,
  sterilise BOOLEAN NOT NULL,
  client_id BIGINT,
  FOREIGN KEY (client_id) REFERENCES clients(id)
);

INSERT INTO clients (nom, prenom, date_naissance, pseudonyme) VALUES
  ('Martin', 'Alice', '1990-04-12', 'alice90'),
  ('Durand', 'Paul', '1985-11-03', 'paul_d');

INSERT INTO adresses (numero, rue, code_postal, commune) VALUES
  ('12', 'Rue des Lilas', '75001', 'Paris'),
  ('4B', 'Avenue Victor Hugo', '69001', 'Lyon');

INSERT INTO clients_adresses (client_id, adresse_id) VALUES (1, 1), (2, 2);

INSERT INTO chiens (nom, date_naissance, race, sterilise, client_id) VALUES
  ('Rex', '2021-02-10', 'Labrador', TRUE, 1),
  ('Milo', '2020-06-05', 'Beagle', FALSE, 2);

INSERT INTO chats (nom, date_naissance, race, sterilise, client_id) VALUES
  ('Minette', '2019-08-20', 'Européen', TRUE, 1),
  ('Nala', '2022-01-14', 'Siamois', FALSE, 2);
EOF
cat > Dockerfile <<'EOF'
FROM mysql:8.4
COPY init.sql /docker-entrypoint-initdb.d/01-init.sql
EOF
docker build -t kennel-db:latest .
docker run -d --name kennel-db -e MYSQL_ROOT_PASSWORD=kennelpass kennel-db:latest
until docker exec kennel-db mysqladmin ping -h 127.0.0.1 -uroot -pkennelpass --silent; do sleep 2; done
docker exec kennel-db mysql -uroot -pkennelpass -e "USE kennelDB; SHOW TABLES; SELECT * FROM chiens; SELECT * FROM chats;"
```
