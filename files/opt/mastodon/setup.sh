#!/bin/bash

PG_HOST=/var/run/postgresql
PG_PORT=5432
PG_PASS=""
PG_USER=postgres
PG_DB=postgres

# Set up postgres dbaas
if [[ -z "${DATABASE_PROTOCOL}" ]]; then

  # Wait for dbaas to become available
  echo -e "\nWaiting for your database to become available (this may take a few minutes)"
  while ! pg_isready -h "${DATABASE_HOST}" -p "${DATABASE_PORT}"; do
     printf .
     sleep 2
  done

  export DATABASE_URL="postgresql://${DATABASE_USERNAME}:${DATABASE_PASSWORD}@${DATABASE_HOST}:${DATABASE_PORT}/mastodon_production?sslmode=require"
  echo "test old"
  echo ${DATABASE_URL}
  # Export variables for future rake script (TODO: Check if old ENV can be reused)
  PG_DB=mastodon_production
  PG_HOST="${DATABASE_HOST}"
  PG_PORT="${DATABASE_PORT}"
  PG_USER="${DATABASE_USERNAME}"
  PG_PASS="${DATABASE_PASSWORD}"

  # Initialize postgres DB since dbaas does not provide it and Rails is hardcoded to use it
  PGPASSWORD=${DATABASE_PASSWORD} psql -h ${DATABASE_HOST} -p ${DATABASE_PORT} -U ${DATABASE_USERNAME} -d ${DATABASE_DB} -c "CREATE DATABASE postgres;" --set=sslmode=require

  echo -e "\nDatabase available!\n" # Should we include echo here?

fi

PGPASSWORD=$PG_PASS psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d $PG_DB -c "CREATE USER mastodon CREATEDB;" --set=sslmode=require

export PATH="/home/mastodon/.rbenv/versions/3.0.3/bin:$PATH"

sudo -i -u mastodon DATABASE_URL=${DATABASE_URL} bash << EOF
export PATH="/home/mastodon/.rbenv/versions/3.0.3/bin:$PATH"

echo "Test"
echo ${DATABASE_URL}

cd /home/mastodon/live &&
  RAILS_ENV=production SECRET_KEY_BASE=precompile_placeholder OTP_SECRET=precompile_placeholder SAFETY_ASSURED=1 bin/rails db:create db:schema:load assets:precompile DATABASE_URL=${DATABASE_URL}
EOF

echo "Booting Mastodon's first-time setup wizard..." &&
  su - mastodon -c "cd /home/mastodon/live && export DBAAS_DB_HOST=$DBAAS_DB_HOST && echo $DBAAS_DB_HOST && export DBAAS_DB_PORT=$DBAAS_DB_PORT && export DBAAS_DB_USER=$DBAAS_DB_USER && export DBAAS_DB_NAME=$DBAAS_DB_NAME && export DBAAS_DB_PASS=$DBAAS_DB_PASS && RAILS_ENV=production /home/mastodon/.rbenv/shims/bundle exec rake digitalocean:setup" &&
  export $(grep '^LOCAL_DOMAIN=' /home/mastodon/live/.env.production | xargs) &&
  echo "Launching Let's Encrypt utility to obtain SSL certificate..." &&
  systemctl stop nginx &&
  certbot certonly --standalone --agree-tos -d $LOCAL_DOMAIN &&
  cp /home/mastodon/live/dist/nginx.conf /etc/nginx/sites-available/mastodon &&
  sed -i -- "s/example.com/$LOCAL_DOMAIN/g" /etc/nginx/sites-available/mastodon &&
  ln -sfn /etc/nginx/sites-available/mastodon /etc/nginx/sites-enabled/mastodon &&
  sed -i -- "s/  # ssl_certificate/  ssl_certificate/" /etc/nginx/sites-available/mastodon &&
  systemctl start nginx &&
  systemctl enable mastodon-web && systemctl start mastodon-web &&
  systemctl enable mastodon-streaming && systemctl start mastodon-streaming &&
  systemctl enable mastodon-sidekiq && systemctl start mastodon-sidekiq &&
  cp -f /etc/skel/.bashrc /root/.bashrc &&
  rm /home/mastodon/live/lib/tasks/digital_ocean.rake &&
  echo "Setup is complete! Login at https://$LOCAL_DOMAIN"
