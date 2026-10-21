FROM php:8.3-apache

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq-dev libicu-dev libzip-dev libpng-dev libjpeg-dev libfreetype6-dev \
        libxml2-dev libsodium-dev libonig-dev libldap2-dev \
        unzip ghostscript poppler-utils graphviz aspell cron \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd intl zip pgsql pdo_pgsql soap exif opcache sodium mbstring ldap \
    && rm -rf /var/lib/apt/lists/* \
    && a2enmod rewrite headers expires

COPY docker/php.ini /usr/local/etc/php/conf.d/moodle.ini
COPY docker/apache.conf /etc/apache2/sites-available/000-default.conf
COPY docker/cron.sh /usr/local/bin/moodle-cron

RUN chmod +x /usr/local/bin/moodle-cron

WORKDIR /var/www/html
