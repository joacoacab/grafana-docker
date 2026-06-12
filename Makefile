.PHONY: start stop restart logs ps status

start:
	@[ -f traefik/acme.json ] || (touch traefik/acme.json && chmod 600 traefik/acme.json)
	@docker compose up -d

stop:
	@docker compose down

restart:
	@docker compose restart

logs:
	@docker compose logs -f

ps:
	@docker compose ps

status:
	@docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
