# Wodby service template

This repository is a starter for a Git-backed Wodby service. Wodby imports
`service.yml` from the selected Git ref and creates a new service revision every
time you import or update it.

The included manifest is intentionally small: it defines a buildable HTTP
service using the Wodby nginx Helm chart. Replace the example names, image,
chart, options, and settings with the service you want to publish.

## Files

- `service.yml` - the Wodby service manifest.
- `Dockerfile` - default Dockerfile content imported into the service build
  configuration.
- `.dockerignore` - default Docker ignore content imported into the service
  build configuration.

## Start here

1. Change `name`, `title`, `icon`, and `labels` in `service.yml`.
2. Replace `options` with the versions or variants your service supports.
3. Replace the container `image` and the `helm` chart information.
4. Keep workload and container names stable after users create app services from
   this service. Renaming them can break stack and app-level overrides.
5. Keep `update: manual` until you are ready for Git updates to drive dependent
   stack updates. Use `update: auto` only when automatic downstream updates are
   intentional.

## Build support

`build.connect: true` lets app services connect a Git repository and build an
image with Wodby CI. At least one workload container must have `build: true` when
the service has a `build` section.

`build.dockerfile` and `build.dockerignore` point to files in this repository.
During import, Wodby reads those files and stores their contents in the service
revision.

If you also maintain starter application repositories, add them under
`build.templates`:

```yaml
build:
  dockerfile: Dockerfile
  dockerignore: .dockerignore
  connect: true
  templates:
  - name: app
    title: Application starter
    repo: https://github.com/example/app-starter
    branch: main
    default: true
```

## Multiple services

A repository can contain multiple services. Put each service in its own
directory and add an `index.yml` at the repository root:

```yaml
services:
- api
- worker
```

Each listed directory must contain its own `service.yml`.

## References

- Service template reference: https://wodby.com/docs/2.0/services/template/
- Naming rules: https://wodby.com/docs/2.0/naming/
