```bash
mkdir -p site-exercice-03
printf '%s\n' '<h1>Hello World - Exercice 03</h1>' > site-exercice-03/index.html
docker run -d --name exercice-03-nginx -p 8080:80 -v "$PWD/site-exercice-03:/usr/share/nginx/html:ro" nginx:alpine
open http://localhost:8080
```
