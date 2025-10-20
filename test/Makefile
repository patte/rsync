# All paths are relative to the test/ directory
IMAGE_TAG := rsync:test
COMPOSE    := docker compose -f docker-compose.test.yml

.PHONY: keys data up down clean logs test-local

keys:
	mkdir -p tmp/keys/clients tmp/keys/host
	chmod 0777 tmp/keys/host
	test -f tmp/keys/clients/test || ssh-keygen -t ed25519 -f tmp/keys/clients/test -N ""
	# Also generate a second user key to test multiple users
	test -f tmp/keys/clients/test2 || ssh-keygen -t ed25519 -f tmp/keys/clients/test2 -N ""

data:
	mkdir -p fixtures/test-data tmp/data
	chmod 0777 tmp/data
	test -f fixtures/test-data/test-file.txt || echo "This is a test file." > fixtures/test-data/test-file.txt
	@test -f fixtures/test-data/large-file.bin || dd if=/dev/urandom of=fixtures/test-data/large-file.bin bs=1048576 count=1

up: keys
	$(COMPOSE) build
	$(COMPOSE) down -v
	$(COMPOSE) up -d

down:
	$(COMPOSE) down -v

clean:
	rm -rf tmp

logs:
	$(COMPOSE) logs --no-color rsync || true

test-local: data up
	bash scripts/run.sh