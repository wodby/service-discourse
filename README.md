# Discourse service for Kubernetes on Wodby

Build and run [Discourse](https://www.discourse.org/) applications on Kubernetes with Wodby.

This service uses the same connected-build model as other Wodby application services. Wodby CI clones the selected Discourse source, builds it on the official `discourse/base` web-only image, and deploys the resulting application image. Wodby does not maintain a separate Discourse runtime image.

## Build sources

The service offers two upstream build boilerplates:

- Discourse `2026.8` stable
- Discourse `2026.7` ESR

Each boilerplate uses the pipeline in this repository. A compatible fork or custom Discourse source can also be connected directly.

The build installs the selected source's Ruby and JavaScript dependencies, precompiles application assets, and adds the runtime lifecycle required by Wodby. The final image remains derived from the official Discourse base image.

## Runtime model

The service runs one stateful Discourse pod containing nginx, Unicorn, and Sidekiq. It requires PostgreSQL, Redis, and SMTP links. Persistent storage is mounted at `/shared` for uploads, backups, logs, and runtime state.

The service deliberately does not support multiple replicas. Horizontal scaling requires separate web and Sidekiq workloads plus shared upload storage and coordinated migrations.

## Configuration

`Administrator email addresses` is required and initializes Discourse developer access. `Notification email address` is optional; when omitted, Discourse derives a default from the primary hostname.

Additional upstream `DISCOURSE_*` settings can be supplied with a variable integration. Database, Redis, and SMTP connection values are owned by service links.

The SMTP link targets an internal mail transfer agent. STARTTLS is disabled only for that private in-cluster hop; the relay remains responsible for securing and authenticating its external connection.

## PostgreSQL

The linked PostgreSQL database must provide `hstore`, `pg_trgm`, `unaccent`, and `vector`. The Discourse stack configures the standard Wodby PostgreSQL service to create them.

## Storage and backups

The default `/shared` volume is 20 GiB. The native Discourse backup includes the database and local uploads in one `tar.gz` artifact.

## Upgrades

Upgrade by rebuilding from a newer supported Discourse Git ref. Do not install `docker_manager` or run an in-place application upgrade from the Discourse administration interface.
