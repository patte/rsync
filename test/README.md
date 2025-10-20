# rsync – test harness

This test harness runs completely inside `test/`, isolating keys/data from development.

## Quick start (local)

```bash
cd test
make test-local
```

## Clean up

```bash
make down
make clean
```

## In CI

The GitHub Actions workflow runs the same scripts/run.sh using docker-compose.test.yml.