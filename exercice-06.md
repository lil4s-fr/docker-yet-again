```bash
mkdir -p site-exercice-06
printf '%s\n' '<h1>Hello World - Exercice 06</h1>' > site-exercice-06/index.html
docker run -d --name exercice-06-nginx -p 8080:80 -v "$PWD/site-exercice-06:/usr/share/nginx/html" nginx:alpine
open http://localhost:8080
```
