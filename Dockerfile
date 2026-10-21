FROM php:8.3-apache-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq-dev libicu-dev libzip-dev libpng-dev libjpeg-dev libfreetype6-dev \
        libxml2-dev libsodium-dev libonig-dev libldap2-dev \
        unzip ghostscript poppler-utils graphviz aspell \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd intl zip pgsql pdo_pgsql soap exif opcache sodium mbstring ldap \
    && rm -rf /var/lib/apt/lists/* \
    && a2enmod rewrite headers expires \
    && a2enconf security \
    && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && printf 'ServerTokens Prod\nServerSignature Off\n' > /etc/apache2/conf-available/moodle-security.conf \
    && a2enconf moodle-security

COPY docker/php.ini /usr/local/etc/php/conf.d/moodle.ini
COPY docker/apache.conf /etc/apache2/sites-available/000-default.conf
COPY docker/cron.sh /usr/local/bin/moodle-cron
COPY docker/entrypoint.sh /usr/local/bin/moodle-entrypoint
COPY docker/healthz.txt /usr/local/share/moodle/healthz.txt

RUN chmod +x /usr/local/bin/moodle-cron /usr/local/bin/moodle-entrypoint

WORKDIR /var/www/html

ENTRYPOINT ["moodle-entrypoint"]
CMD ["apache2-foreground"]
