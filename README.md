# fontra-docker

Run [Fontra](https://github.com/fontra/fontra), a font editor in your web
browser, with Docker.

Your fonts live in the [`fonts`](fonts/) folder. Fontra saves every change
straight into those files.

> Need logins for several people? Use the
> [multi-user version](multiuser/README.md) instead.

## Start it

You need Docker with Compose.

**Option A: download the ready-made image (fastest)**

```sh
docker compose up -d
```

**Option B: build the image yourself (takes a few minutes)**

```sh
echo "COMPOSE_FILE=docker-compose.yml:docker-compose.build.yml" >> .env
docker compose up --build -d
```

Then open **http://localhost:8000/** and click `default.designspace`.

To stop it: `docker compose down`

## The files

| File | What it is for |
|---|---|
| [`docker-compose.yml`](docker-compose.yml) | Runs the ready-made image. Option A uses only this. |
| [`docker-compose.build.yml`](docker-compose.build.yml) | Adds the build steps. Option B turns it on. |
| [`.env.example`](.env.example) | All settings. Copy it to `.env` to change them. |
| [`fonts/`](fonts/) | Your fonts. |
| [`patches/`](patches/) | Small changes to Fontra, made when the image is built. |

## Fonts

- Put your fonts in the `fonts` folder. Subfolders work too.
- You can edit `.designspace`, `.ufo`, `.fontra` and `.rcjk` files.
- You can open `.ttf`, `.otf`, `.woff`, `.woff2` and `.ttx` files, but not
  change them.
- If the folder is empty, you get an empty font called
  `default.designspace`.
- It comes with a folder called `default_Regular.ufo`. Keep it, because
  that's where the glyphs are stored.

To make another new font:

```sh
docker compose run --rm fontra new /fonts/MyFont.designspace
```

## Settings

Change these in `.env`, then run `docker compose up -d` again.

| Setting | Default | What it does |
|---|---|---|
| `FONTRA_PORT` | `8000` | The port in your browser address |
| `FONTRA_VERSION` | `latest` | Which Fontra release, for example `2026.10.0` |
| `FONTRA_DEFAULT_FONT` | `default.designspace` | The empty font to make. Leave it empty to turn this off. |
| `COMPOSE_FILE` | not set | Set it as in option B to build the image yourself |
| `FONTRA_UID`, `FONTRA_GID` | `1000` | Option B only: which user owns the files Fontra saves |

To only look at fonts, without editing, create a file called
`docker-compose.override.yml`:

```yaml
services:
  fontra:
    command: ["filesystem", "/fonts", "--read-only"]
```

## Update

Option A:

```sh
docker compose pull
docker compose up -d
```

Option B:

```sh
docker compose build --pull --no-cache
docker compose up -d
```

To see which Fontra version you have:
`docker compose run --rm fontra --version`

## Good to know

- This image builds Fontra straight from its newest release on GitHub,
  with the changes in [`patches/`](patches/). Each patch says at the top
  what it does and why. A patch that no longer fits a newer Fontra is left
  out, with a warning in the build log, and the image is built without it.
- The image also has [fontra-rcjk](https://github.com/fontra/fontra-rcjk)
  for the multi-user version, and
  [fontra-compile](https://github.com/fontra/fontra-compile) for making
  `.otf` and `.ttf` files.
- The ready-made images are built by
  [the GitHub workflow](.github/workflows/docker.yml). It runs on every
  push and checks daily for a new Fontra release. You can find the images
  at `ghcr.io/pigwin-3/fontra-docker`.

## License

This packaging is provided as-is. Fontra, fontra-rcjk, fontra-compile and
django-robo-cjk use the GNU GPL v3 license.
