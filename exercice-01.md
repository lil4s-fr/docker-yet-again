```bash
docker run -it --name ubuntu-nginx-builder ubuntu:22.04 bash
apt-get update && apt-get install -y nginx
exit
docker commit ubuntu-nginx-builder ubuntu-nginx:latest
```
