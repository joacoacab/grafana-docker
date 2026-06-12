#DO NOT CHANGE
include .env

psql:
	@docker exec -it ${DB_CONTAINER} psql -U ${DATABASE_USER} -d ${DATABASE_NAME}

start:
	@docker-compose up -d

stop:
	@docker-compose down

restart:
	@docker-compose restart

postgres:
	@docker exec -it ${DB_CONTAINER} bash
.PHONY: postgres

grafana-db:
	@docker exec -it ${DB_CONTAINER} psql -U grafana_user -d grafana