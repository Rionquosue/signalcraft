# plugins

Addon directory. In a deployment this is `/var/www/signalcraft/plugins`.

Each addon is one Ruby gem in its own subdirectory, named after the addon id:

```
plugins/
  bluesky/
    signalcraft_plugin.yml   manifest (design specifications/04, Manifest and discovery)
    bluesky.gemspec
    lib/...
```

How addons are installed:

1. Place the reviewed, pinned addon gem directory here.
2. Rebuild the image. The `Gemfile` loads every `plugins/*/*.gemspec`, Bundler
   resolves them, and `bin/plugin-lock` records a fingerprint of this
   directory in `.lock.json`.
3. Deploy. The migrate role runs `bin/rails signalcraft:plugins:sync`, which
   records each addon and any manifest problems in the database.
4. A workspace owner enables the addon in Settings → Plugins.

The directory may be mounted read-only from the host so operators can see
what is installed. If its contents no longer match the image build, the
container refuses to start (`bin/docker-entrypoint`), because addon code is
only ever loaded from what was bundled at build time. Nothing is installed at
runtime.

Addon specifications: sheets 02-1 to 02-10 in `design specifications/`.
No addons are implemented yet.
