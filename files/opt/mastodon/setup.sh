#!/bin/bash

PG_HOST=/var/run/postgresql
PG_PORT=5432
PG_PASS=""
PG_USER=postgres
PG_DB=postgres

# Set up postgres dbaas
if [[ "$DATABASE_PROTOCOL" == "postgresql" ]]; then

  # Wait for dbaas to become available
  echo -e "\nWaiting for your database to become available (this may take a few minutes)"
  while ! pg_isready -h "${DATABASE_HOST}" -p "${DATABASE_PORT}"; do
     printf .
     sleep 2
  done

  DATABASE_URL="postgresql://${DATABASE_USERNAME}:${DATABASE_PASSWORD}@${DATABASE_HOST}:${DATABASE_PORT}/mastodon_production?sslmode=require"

  PG_DB="${DATABASE_DB}"
  PG_HOST="${DATABASE_HOST}"
  PG_PORT="${DATABASE_PORT}"
  PG_USER="${DATABASE_USERNAME}"
  PG_PASS="${DATABASE_PASSWORD}"

  # Initialize postgres DB since dbaas does not provide it and Rails is hardcoded to use it
  PGPASSWORD=${DATABASE_PASSWORD} psql -h ${DATABASE_HOST} -p ${DATABASE_PORT} -U ${DATABASE_USERNAME} -d ${DATABASE_DB} -c "CREATE DATABASE postgres;" --set=sslmode=require
  PGPASSWORD=${DATABASE_PASSWORD} psql -h ${DATABASE_HOST} -p ${DATABASE_PORT} -U ${DATABASE_USERNAME} -d ${DATABASE_DB} -c "CREATE USER mastodon CREATEDB;" --set=sslmode=require

  echo -e "\nManaged database is configured!\n" # Should we include echo here?
else
  sudo -u postgres psql -c "CREATE USER mastodon CREATEDB;"
fi

export PATH="/home/mastodon/.rbenv/versions/3.0.4/bin:$PATH"

sudo -i -u mastodon bash << EOF
  export PATH="/home/mastodon/.rbenv/versions/3.0.4/bin:$PATH" &&
  cd /home/mastodon/live

  if [[ "$DATABASE_URL" == "" ]]; then
    RAILS_ENV=production DB_HOST=/var/run/postgresql SECRET_KEY_BASE=precompile_placeholder OTP_SECRET=precompile_placeholder SAFETY_ASSURED=1 bin/rails db:create db:schema:load assets:precompile DISABLE_DATABASE_ENVIRONMENT_CHECK=1
  else
    RAILS_ENV=production SECRET_KEY_BASE=precompile_placeholder OTP_SECRET=precompile_placeholder SAFETY_ASSURED=1 bin/rails db:create db:schema:load assets:precompile DATABASE_URL=${DATABASE_URL} DISABLE_DATABASE_ENVIRONMENT_CHECK=1
  fi
EOF

PG_DB="mastodon_production"
PG_USER="mastodon" # While using local database we need to change user back to mastodon (this step cannot be done before)

echo "Booting Mastodon's first-time setup wizard..." &&
  su - mastodon -c "cd /home/mastodon/live && export DB_NAME=$PG_DB && export DB_PASS=$PG_PASS && export DB_PORT=$PG_PORT && export DB_USER=$PG_USER && export DB_HOST=$PG_HOST && \
  if [[ \"$DATABASE_URL\" == \"\" ]]; then RAILS_ENV=production /home/mastodon/.rbenv/shims/bundle exec rake digitalocean:setup; else RAILS_ENV=production /home/mastodon/.rbenv/shims/bundle exec rake digitalocean:setup DATABASE_URL=${DATABASE_URL}; fi;" &&
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
