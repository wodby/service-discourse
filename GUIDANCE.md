# Discourse on Wodby

What Wodby sets up for a Discourse application on this service. Check it before adding database, Redis, mail or host settings to the site settings.

## How the application is built and run

- The service runs the prebuilt [wodby/discourse](https://github.com/wodby/discourse) image of the selected release line: `2026.10` (the monthly release) or `2026.7` (the extended support release). Each image holds one Discourse release on the official `discourse/base` web-only image, with its frontend and compressed assets. There is no repository and no build.
- Plugins bundled with Discourse, such as chat, AI, solved, assign, reactions and voting, are available. Themes and theme components are installed from the administration interface. Other plugins need a custom build and are not supported.
- One container runs nginx on port 80, Unicorn and Sidekiq. The service is not scalable.
- On every start the container runs `rake db:migrate` while `MIGRATE_ON_BOOT` is `1`, and `rake themes:update assets:precompile:css maxminddb:refresh` while `PRECOMPILE_ON_BOOT` is `1`. Both are set to `1`.
- The health endpoint is `/srv/status` on port 80.

## Generated configuration

On every start the container writes `config/discourse.conf` from the environment: each `DISCOURSE_<NAME>` variable becomes the `<name>` setting. The file is rewritten on start: never edit it. A site setting that has a variable of the same name takes its value from the variable and cannot be changed in the administration interface.

## Linked services

| Link | Variables |
| --- | --- |
| PostgreSQL (required) | `DISCOURSE_DB_HOST`, `DISCOURSE_DB_PORT`, `DISCOURSE_DB_NAME`, `DISCOURSE_DB_USERNAME`, `DISCOURSE_DB_PASSWORD` |
| Redis (required) | `DISCOURSE_REDIS_HOST`, `DISCOURSE_REDIS_PORT`, `DISCOURSE_REDIS_PASSWORD` |
| Mail transfer agent (required) | `DISCOURSE_SMTP_ADDRESS`, `DISCOURSE_SMTP_PORT` |

The container waits for the database and Redis ports before it starts. Mail goes to the linked mail service without authentication and with `DISCOURSE_SMTP_ENABLE_START_TLS` set to `false`. These connection values belong to the links: do not set them elsewhere.

## Host and administrators

- `DISCOURSE_HOSTNAME` and `DISCOURSE_SMTP_DOMAIN` are the environment's primary host. `DISCOURSE_FORCE_HTTPS` is `true`.
- The setting "Administrator email addresses" sets `DISCOURSE_DEVELOPER_EMAILS`: an account registered with one of these addresses becomes an administrator. No administrator account is created otherwise.
- The optional setting "Notification email address" sets `DISCOURSE_NOTIFICATION_EMAIL`.

## Changing configuration

Set the two settings above on the service. Other upstream `DISCOURSE_*` settings are added as environment variables through the "Additional environment variables" integration. A change applies with the next deployment of the service.

## Data, backups and upgrades

- The `data` volume is mounted at `/shared`: uploads (`/shared/uploads`), backups (`/shared/backups`) and Rails logs (`/shared/log/rails`). `public/uploads` and `public/backups` in the application are links to it.
- The declared backup runs Discourse's own backup (`discourse backup`), one `tar.gz` with the database and the uploads.
- Discourse is upgraded by a newer image: a new revision of the same release line brings its patch releases, and a newer release line is a different version of the service. Do not upgrade from the administration interface or install `docker_manager`.

## Check the result

- `curl -f http://127.0.0.1/srv/status` inside the container.
- `discourse` in the container runs `script/discourse` as the `discourse` user in production mode.
