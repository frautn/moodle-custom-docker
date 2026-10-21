#!/bin/sh
set -eu

trap 'exit 0' TERM INT

while true; do
    started=$(date +%s)
    if php /var/www/html/admin/cli/cron.php; then
        :
    else
        status=$?
        printf 'Moodle cron failed (exit %s); retrying on the next cycle.\n' "$status" >&2
    fi
    elapsed=$(($(date +%s) - started))
    if [ "$elapsed" -lt 300 ]; then
        sleep "$((300 - elapsed))" &
        wait "$!"
    fi
done
