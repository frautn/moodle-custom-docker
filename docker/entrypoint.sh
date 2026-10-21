#!/bin/sh
set -eu

: "${POSTGRES_DB:?POSTGRES_DB must be set}"
: "${POSTGRES_USER:?POSTGRES_USER must be set}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set}"

for file in public/index.php public/r.php admin/cli/cron.php lib/setup.php vendor/autoload.php config.php; do
    if [ ! -r "/var/www/html/$file" ]; then
        printf 'Missing readable Moodle file: /var/www/html/%s. Check the /mnt/data/moodle mount and config.php.\n' "$file" >&2
        exit 1
    fi
done

if [ ! -d /var/www/moodledata ]; then
    printf 'Missing /var/www/moodledata. Create /mnt/data/moodledata before starting Compose.\n' >&2
    exit 1
fi

umask 0007
exec docker-php-entrypoint "$@"
