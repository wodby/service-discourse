# Discourse service for Kubernetes on Wodby

Run [Discourse](https://www.discourse.org/) on Kubernetes with Wodby.

The service runs the prebuilt [wodby/discourse](https://github.com/wodby/discourse) image: one Discourse release on the official `discourse/base` web-only image, with its frontend and compressed assets. There is no repository and no build.

## Versions

- Discourse `2026.10`, the monthly release (default)
- Discourse `2026.7`, the extended support release (ESR)

A new image revision of a release line brings its patch releases.

## Plugins and themes

Plugins bundled with Discourse, such as chat, AI, solved, assign, reactions and voting, are available. Themes and theme components are installed from the administration interface. Other plugins need a custom build and are not supported.

## Upgrading from 1.x

Version 1.x built Discourse from a connected repository. Existing applications keep 1.x and its builds, because a new major version is never applied automatically. To move to the prebuilt image, create a new application from the Discourse stack and restore a Discourse backup into it.

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

Discourse is upgraded by a newer image: a new revision of the same release line, or a newer release line. Do not install `docker_manager` or run an in-place application upgrade from the Discourse administration interface.
