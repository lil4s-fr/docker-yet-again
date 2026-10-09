```bash
docker network create exercice-04-net
docker run -it --name ping-builder ubuntu:22.04 bash
apt-get update && apt-get install -y iputils-ping
exit
docker commit ping-builder ubuntu-ping:latest
docker run -dit --name ping-1 --network exercice-04-net ubuntu-ping:latest sleep infinity
docker run -dit --name ping-2 --network exercice-04-net ubuntu-ping:latest sleep infinity
docker exec ping-1 ping -c 4 ping-2
docker exec ping-2 ping -c 4 ping-1
```
