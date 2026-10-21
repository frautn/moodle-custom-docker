#!/bin/sh
# Runs Moodle scheduled tasks every minute.
while true; do
    su -s /bin/sh www-data -c "php /var/www/html/admin/cli/cron.php" || true
    sleep 60
done
