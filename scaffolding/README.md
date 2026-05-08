# scaffolding/

New-project starter templates. Each subdirectory is one template (`go-service/`, `python-service/`, `next-frontend/`) containing the minimum file set a new project under `projects/` should start with — `CLAUDE.md` template, `.markdownlint.json`, `.gitignore`, `tasks/lessons.md` stub, etc.

**What goes here:** `<template-name>/` directories with the files a new project should start with. A `<template-name>/MANIFEST.md` documents what the template provides and how to instantiate it.

**What does NOT go here:** working code (templates are for greenfield project bootstrap, not shared libraries); per-language style guides (those belong in `docs/` or the language's own tooling).

**Deployment:** future spec (`dev-platform-extensions-spec.md`, R4 on the roadmap). Templates will be instantiated by a `scripts/new-project.sh <template>` helper that copies the template into `projects/<name>/` and runs the project's first-time setup. For now this directory exists as a contract.
