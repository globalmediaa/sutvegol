FROM composer:2 AS dependencies
WORKDIR /build
COPY backend/composer.json backend/composer.lock ./
RUN composer install --no-dev --classmap-authoritative --no-interaction --prefer-dist

FROM php:8.4-apache
RUN apt-get update && apt-get install -y --no-install-recommends libonig-dev \
    && docker-php-ext-install pdo_mysql mbstring opcache \
    && a2enmod rewrite headers remoteip \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /var/www
COPY backend/src ./backend/src
COPY --from=dependencies /build/vendor ./backend/vendor
COPY backend/admin ./backend/admin
COPY docs ./html
COPY backend/public ./html/api
COPY deploy/apache.conf /etc/apache2/sites-available/000-default.conf
COPY deploy/php.ini /usr/local/etc/php/conf.d/sutvegol.ini
COPY backend/public/index.php ./backend/public/index.php
RUN apache2ctl -t
RUN printf '<?php require dirname(__DIR__, 2)."/backend/public/index.php";\n' > /var/www/html/api/index.php \
    && printf 'RewriteEngine On\nRewriteCond %%{REQUEST_FILENAME} !-f\nRewriteCond %%{REQUEST_FILENAME} !-d\nRewriteRule ^api/(.*)$ api/index.php [QSA,L]\nRewriteRule ^privacy/?$ privacy.html [L]\nRewriteRule ^account-deletion/?$ account-deletion.html [L]\n' > /var/www/html/.htaccess \
    && chown -R www-data:www-data /var/www/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s CMD php -r 'exit(@file_get_contents("http://127.0.0.1/api/health") ? 0 : 1);'
