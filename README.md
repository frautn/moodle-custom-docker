# Production Moodle on OCI

Docker Compose runs PHP 8.3/Apache, PostgreSQL 17 (the minimum for Moodle 5.3),
and a separate Moodle cron worker. PostgreSQL is a **separate container in the
same Compose deployment**, not a second process inside the web container.
The image contains the PHP runtime and tools, not Moodle source code.
It builds natively on both amd64 and OCI Ampere arm64 hosts.

The existing Ubuntu Nginx terminates HTTPS for `https://moodle.fcr.lat` and
proxies to `127.0.0.1:8081`. Neither PostgreSQL nor the cron worker publishes a
port. Certificates stay on the host; they are not copied into an image.

## Persistent paths

| OCI host path | Purpose | Container path |
| --- | --- | --- |
| `/mnt/data/moodle` | Existing Moodle 5.3 checkout, read-only | `/var/www/html` |
| `/mnt/data/moodledata` | Uploaded files, caches, sessions, locks | `/var/www/moodledata` |
| `/mnt/data/postgres` | PostgreSQL 17 database files | `/var/lib/postgresql/data` |
| `./config.php` | Deployment configuration, read-only overlay | `/var/www/html/config.php` |

Apache serves **only `/var/www/html/public`**. The root `config.php` and
non-public source files are not served. Moodle 5.3 uses the `public/` layout
but keeps CLI tools outside the public directory, in `admin/cli`. The root
`lib/setup.php` is Moodle's compatibility bootstrap.

## 1. Prepare the OCI host

Install Docker Engine and the Docker Compose plugin, and enable Docker at boot.
Run all Compose commands below from this repository on the OCI host. Keep the
repository at a stable location; Compose bind-mounts its configuration.

Verify the existing checkout is a complete Moodle 5.3 release, including its
bundled dependencies:

```sh
test -f /mnt/data/moodle/public/index.php
test -f /mnt/data/moodle/admin/cli/install_database.php
test -f /mnt/data/moodle/lib/setup.php
test -f /mnt/data/moodle/vendor/autoload.php
grep 'release = ' /mnt/data/moodle/public/version.php
```

If the checkout is source-only and lacks `vendor/autoload.php`, install its
locked production dependencies before starting. The runtime image includes
Composer, so host PHP and Composer installations are not needed. Run the
following from this repository as the checkout's owner:

```sh
docker compose build --pull
docker run --rm \
    --user "$(id -u):$(id -g)" \
    --env COMPOSER_HOME=/tmp/composer \
    --mount type=bind,source=/mnt/data/moodle,target=/var/www/html \
    --entrypoint composer \
    moodle-custom:5.3 \
    install --no-dev --optimize-autoloader --no-interaction
```

This one-off container can write to the checkout and uses the same PHP
extensions as Moodle, but receives no database credentials or data mounts.
The running web and cron services keep their read-only source mounts.
Do not mount an incomplete checkout.

Create the data directories. On the Debian-based PHP image, `www-data` is
UID/GID 33; on `postgres:17-bookworm`, `postgres` is UID/GID 999. These commands
are for **new directories**; do not blindly change ownership or initialize
over existing production data.

```sh
sudo install -d -o 33 -g 33 -m 0770 /mnt/data/moodledata
sudo install -d -o 999 -g 999 -m 0700 /mnt/data/postgres
cp .env.example .env
chmod 600 .env
openssl rand -hex 32
```

Put the generated value in `POSTGRES_PASSWORD` in `.env`. Database name and
user default to `moodle`. Compose refuses to start if any database setting is
empty. The password is passed as a container environment variable: restrict
access to this repository, `.env`, the Docker socket, and host backups.

Ensure UID 33 can traverse `/mnt/data` and read the Moodle checkout and this
repository's `config.php`, but **cannot write to the source checkout**. Do not
make source files world-writable. Verify permissions as needed with
`namei -l /mnt/data/moodle/public/index.php`.

If the checkout already has a `config.php`, back it up first. The Compose
overlay hides it without modifying it. For an existing site, review and
merge any site-specific configuration into this repository's `config.php`,
and migrate the existing database and moodledata together.

The file mount target must exist inside the read-only checkout. If this is a
new checkout without `config.php`, create it before starting containers:

```sh
if [ ! -e /mnt/data/moodle/config.php ]; then
    sudo install -m 0644 config.php /mnt/data/moodle/config.php
fi
```

**Existing PostgreSQL 16 data cannot be used directly with PostgreSQL 17.**
Use a tested logical dump/restore or `pg_upgrade` migration before switching.
The initialization variables only take effect on an empty database directory;
changing `.env` does not change credentials in an existing database.

## 2. Build and start the web/database services

```sh
docker compose config --quiet
docker compose build --pull
docker compose up -d db moodle
docker compose ps
docker compose logs --tail=100 db moodle
curl --fail http://127.0.0.1:8081/healthz
```

The health endpoint checks Apache, not Moodle's database schema or installation
status. It is blocked by the public Nginx configuration.

If Compose reports `dependency db failed to start`, inspect
`docker compose logs --tail=100 db`. A repeated
`mkdir: cannot create directory '/var/lib/postgresql/data': Permission denied`
can occur if `/mnt/data/postgres` was created as root with mode `0700`.
The entrypoint changes ownership of the `pgdata` subdirectory, but PostgreSQL
also needs to traverse its parent after switching to UID 999. On the standard
rootful Docker Engine setup described here, fix the parent directory only,
without deleting or recursively changing database files:

```sh
sudo chown 999:999 /mnt/data/postgres
docker compose restart db
docker compose up -d db moodle
docker compose ps
```

Rootless Docker or user-namespace remapping requires host ownership matching
the mapped container UID instead.

## 3. Configure the host Nginx

Make sure DNS for `moodle.fcr.lat` points to the OCI host. Only publish an AAAA
record if IPv6 connectivity and the firewall are configured. Allow inbound
80/443 in OCI security lists/NSGs and the Ubuntu firewall; do not open 8081 or
5432. Confirm the certificate covers `moodle.fcr.lat`, includes any necessary
intermediate certificates, and that its private key has restricted permissions.

Review any existing virtual host for this domain to avoid duplicates, then:

```sh
sudo install -m 0644 moodle.fcr.lat.nginx /etc/nginx/sites-available/moodle.fcr.lat
sudo ln -s /etc/nginx/sites-available/moodle.fcr.lat /etc/nginx/sites-enabled/moodle.fcr.lat
sudo nginx -t
sudo systemctl reload nginx
```

Skip the symlink command if the correct link already exists. The configuration
uses the provided host certificate paths:

```nginx
ssl_certificate /etc/ssl/certs/domain-fcr.cert.pem;
ssl_certificate_key /etc/ssl/private/private-fcr.key.pem;
```

Nginx forwards the original Host and HTTPS scheme. Moodle sets `sslproxy=true`;
`reverseproxy=false` is intentional because the external Host is preserved.
Arrange certificate renewal and reload Nginx after renewal.

## 4. Initialize Moodle and start cron

For a **new, empty database**, open
`https://moodle.fcr.lat/admin/index.php` and follow the installation wizard,
accepting the license and setting the site details and administrator password.
The supplied `config.php` already contains the database settings. Restrict
access at Nginx to your administrator IP during setup so nobody else can
claim the initial administrator account.

After the installation finishes:

```sh
docker compose up -d cron
docker compose logs --tail=100 cron
curl --fail --head https://moodle.fcr.lat/login/index.php
```

Do not run the installer against an existing site. Complete initialization
before allowing public traffic.
For a migrated site, use the upgrade workflow below instead.

The cron worker runs as `www-data`, never overlaps its own invocations, and
reports task failures to container logs. It honors Moodle's cron keep-alive
setting (which may poll for tasks within one invocation); shorter invocations
are paced to once per minute. On shutdown it allows the current invocation to
finish, up to the five-minute Compose stop timeout. In Moodle, confirm
**Site administration > Server > Tasks > Scheduled tasks** shows recent runs.
Configure SMTP, backups, timezone, authentication, and other site settings in
Moodle before launch. Test a login, an upload near the required size, and a
scheduled task end-to-end.

## Operations

- Follow logs with `docker compose logs -f --tail=100 moodle cron db`. Docker
  rotates each service's logs (five files of up to 10 MB).
- PHP permits 100 MiB uploads; PHP POST and Nginx request limits are 110 MiB
  to leave room for multipart overhead. Moodle/course upload limits may be lower.
- Code and plugins are managed on the host, not installed via the web UI.
  Restart the web service after code changes to invalidate OPcache.
- Rebuild regularly for PHP/OS security updates:
  `docker compose build --pull` followed by
  `docker compose up -d --force-recreate moodle cron`.
  Tags follow supported patch releases; record image digests for controlled
  releases and test updates before deploying.
- PostgreSQL is not tuned to a specific machine size. Size OCI RAM/CPU/storage
  for the workload and tune PHP, Apache concurrency, and PostgreSQL together.
  Monitor disk space, scheduled tasks, HTTP errors, and external login checks;
  Docker health checks alone are not full application monitoring.

### Backups

Back up the database, moodledata, source revision/plugins, `config.php`, and
`.env` as one recoverable set, with encrypted off-host copies and tested
restores. Never rely on a live file copy of `/mnt/data/postgres`.

For a consistent logical backup, put Moodle into maintenance mode, stop cron,
and stop the web service after enabling maintenance (this interrupts active
requests). Then dump the database and snapshot/copy moodledata while no writers
are running:

```sh
docker compose exec --user www-data moodle php admin/cli/maintenance.php --enable
docker compose stop cron moodle
umask 077
docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > moodle.dump
# Back up /mnt/data/moodledata and configuration to your backup destination now.
docker compose up -d moodle
docker compose exec --user www-data moodle php admin/cli/maintenance.php --disable
docker compose up -d cron
```

Check the dump command succeeded before treating it as a backup. Store the
dump outside the repository and include it in your off-host backup policy.
Stop any additional external workers before taking a consistent backup.

### Moodle upgrades

Take and verify backups first. Do not automatically pull a moving Moodle
branch in production.

```sh
docker compose exec --user www-data moodle php admin/cli/maintenance.php --enable
docker compose stop cron moodle
# Update /mnt/data/moodle to a tested release and update compatible plugins.
# Keep the config.php bind target present if replacing the checkout.
docker compose up -d moodle
docker compose exec --user www-data moodle php admin/cli/upgrade.php --non-interactive
docker compose exec --user www-data moodle php admin/cli/purge_caches.php
docker compose exec --user www-data moodle php admin/cli/maintenance.php --disable
docker compose up -d cron
```

Verify HTTPS, login, file access, and scheduled tasks afterward. If an upgrade
fails, keep maintenance enabled and restore the matching database, code, and
moodledata backup; reverting code alone does not roll back a database upgrade.