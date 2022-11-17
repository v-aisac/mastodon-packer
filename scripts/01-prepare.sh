#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

PG_HOST=/var/run/postgresql
PG_PORT=5432
PG_PASS=""
PG_USER=postgres
PG_DB=postgres

# Set up postgres dbaas
if [ -f "/root/.digitalocean_dbaas_credentials" ] && [ "$(sed -n "s/^db_protocol=\"\(.*\)\"$/\1/p" /root/.digitalocean_dbaas_credentials)" = "postgresql" ];
then
  # grab all the data from the dbaas credentials file
  PG_HOST=$(sed -n "s/^db_host=\"\(.*\)\"$/\1/p" /root/.digitalocean_dbaas_credentials)
  PG_PORT=$(sed -n "s/^db_port=\"\(.*\)\"$/\1/p" /root/.digitalocean_dbaas_credentials)
  PG_USER=$(sed -n "s/^db_username=\"\(.*\)\"$/\1/p" /root/.digitalocean_dbaas_credentials)
  PG_DB=$(sed -n "s/^db_database=\"\(.*\)\"$/\1/p" /root/.digitalocean_dbaas_credentials)
  PG_PASS=$(sed -n "s/^db_password=\"\(.*\)\"$/\1/p" /root/.digitalocean_dbaas_credentials)

  # wait for db to become available
  echo -e "\nWaiting for your database to become available (this may take a few minutes)"
  while ! pg_isready -h "$PG_HOST" -p "$PG_PORT"; do
     printf .
     sleep 2
  done

  echo -e "\nDatabase available!\n" # Should we include echo here?
fi

cloud-init status --wait \
  && apt -qqy update \
  && apt -qqy -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' full-upgrade \
  && apt -qqy install fail2ban iptables-persistent wget gnupg apt-transport-https lsb-release ca-certificates \
  && curl -sL https://deb.nodesource.com/setup_16.x | bash - \
  && wget -O /usr/share/keyrings/postgresql.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  && echo "deb [signed-by=/usr/share/keyrings/postgresql.asc] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/postgresql.list \
  && apt -qqy update \
  && apt -qqy install imagemagick ffmpeg libpq-dev libxml2-dev libxslt1-dev file git-core \
    g++ libprotobuf-dev protobuf-compiler pkg-config nodejs gcc autoconf \
    bison build-essential libssl-dev libyaml-dev libreadline6-dev \
    zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev \
    nginx redis-server redis-tools postgresql postgresql-contrib \
    certbot python3-certbot-nginx libidn11-dev libicu-dev libjemalloc-dev \
  && corepack enable \
  && yarn set version stable \
  && adduser --disabled-login --gecos '' mastodon \
  && sudo -u PGPASSWORD=$PG_PASS psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d $PG_DB "CREATE USER mastodon CREATEDB;" --set=sslmode=require
