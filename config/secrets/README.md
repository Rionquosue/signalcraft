# config/secrets

Mount point for secret files (in a deployment:
`/var/www/signalcraft/config/secrets`, read-only). Each file holds one value,
referenced from `config/signalcraft.yml` with a `*_file` setting or from the
environment with a `*_FILE` variable.

Nothing in this directory except this README is committed. For local
development and CI, `bin/dev-config` generates throwaway values.
