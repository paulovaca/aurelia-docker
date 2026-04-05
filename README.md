# aurelia-docker

Aurelia OS ([Lordymine/aurelia](https://github.com/Lordymine/aurelia)) empacotado em Docker e publicado no GHCR.

Imagem: `ghcr.io/paulovaca/aurelia-docker:latest`

## Uso (docker-compose)

```yaml
services:
  aurelia:
    image: ghcr.io/paulovaca/aurelia-docker:latest
    container_name: aurelia
    restart: unless-stopped
    stdin_open: true
    tty: true
    environment:
      TZ: America/Sao_Paulo
    volumes:
      - ./data:/home/aurelia/.aurelia
```

## Onboarding

Depois do container rodando:

```bash
docker compose exec aurelia aurelia onboard
```

O onboarding interativo vai pedir bot token do Telegram, provider LLM, API key, user ID autorizado. Tudo salvo no volume `./data/`.

```bash
docker compose restart aurelia
docker compose logs -f aurelia
```

## Atualizar

Rebuild pega a última versão do Aurelia upstream:

```bash
# Na VPS
docker compose pull
docker compose up -d
```

Rebuild manual da imagem (trigger do workflow): Actions → "Build & Push to GHCR" → Run workflow. Ou push um commit qualquer.

O workflow também roda toda segunda às 06:00 UTC.
