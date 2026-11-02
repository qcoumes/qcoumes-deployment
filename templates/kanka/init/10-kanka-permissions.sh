#!/bin/sh

mkdir -p /app/www/bootstrap/cache
chown -R abc:users /app/www/bootstrap/cache
chmod -R ug+rwX /app/www/bootstrap/cache
