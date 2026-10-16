# Multi-user Fontra

Fontra for a team. Everyone logs in with their own account. The fonts are
saved in a database, and everyone sees each other's changes within a few
seconds.

> Just for yourself? The [single-user version](../README.md) is simpler.

## Start it

You need Docker with Compose. Run everything from this `multiuser` folder.

**Step 1: make the settings file.** This also prints the admin login.
Write it down.

```sh
./init-env.sh
```

**Step 2: start it.** Pick one option.

Option A: download the ready-made images (fastest)

```sh
docker compose up -d
```

Option B: build the images yourself (takes a few minutes)

```sh
echo "COMPOSE_FILE=docker-compose.yml:docker-compose.build.yml" >> .env
docker compose up --build -d
```

**Step 3: wait 1 to 2 minutes** the first time, while the database sets
itself up.

**Step 4: open it.** Your browser will warn about the certificate the first
time. That's expected, so click through it.

| What | Address |
|---|---|
| Fontra (the editor) | https://localhost:8443/ |
| Export page (download fonts) | https://localhost:8443/export/ |
| Admin site (users and projects) | https://localhost:9443/admin/ |

**Step 5: add a font.** The list is empty at first. Import one:

```sh
./import-font.sh ~/fonts/MyFont.designspace "My Project"
```

Log in to Fontra as admin, and the font is there.

## The files

| File | What it is for |
|---|---|
| [`docker-compose.yml`](docker-compose.yml) | Runs the ready-made images. Option A uses only this. |
| [`docker-compose.build.yml`](docker-compose.build.yml) | Adds the build steps. Option B turns it on. |
| [`.env.example`](.env.example) | All settings. `init-env.sh` turns it into `.env`. |
| [`init-env.sh`](init-env.sh) | Creates `.env` with random passwords |
| [`import-font.sh`](import-font.sh) | Puts a font into the database |
| [`export-font.sh`](export-font.sh) | Gets a font out of the database, from the command line |
| [`certs/`](certs/) | Your own HTTPS certificate, if you have one |

## Add people

People only see projects they belong to. In the admin site:

1. **Add a user:** Authentication and Authorization → Users → Add.
2. **Give them a project:** RoboCJK → Projects → pick the project → add
   them under **Designers**.
3. **Optional, limit what they can do:**
   - In the group **Reviewers**, they can only look.
   - In the group **DummyDesigners**, they can edit, but nothing is saved.

You can also make an empty project there. It asks for a "Repo URL". Any
made-up value like `git@github.com:me/test.git` is fine.

## Get fonts out

Open the export page, log in, pick a format and click **Download**.

| Format | What you get |
|---|---|
| Designspace + UFO, UFO, Fontra | Source files in a `.zip` |
| OpenType, TrueType, Webfont | `.otf`, `.ttf` or `.woff2`, ready to install |

Fonts with several masters become variable fonts. If a glyph can't be
exported, the zip has a file `export-problems.txt` that lists it.

From the command line:

```sh
./export-font.sh "My Project/MyFont" exports/MyFont.designspace
```

## What gets lost

The database was made for Chinese, Japanese and Korean fonts. So:

- **Kerning is not saved.**
- **Designspace rules are dropped** when you import.
- **Glyphs with slanted (skewed) components can't be imported.** Add
  `--skip-bad-glyphs` to import everything else.

Keep your original font files.

## Put it on a real server

1. Make the settings with your domain: `./init-env.sh fonts.example.com`
2. Put your certificate in `certs/` as `fullchain.pem` and `privkey.pem`,
   then run `docker compose restart proxy`.
3. Optional: set `FONTRA_PORT=443` in `.env`, so people don't need to type a
   port.
4. Only admins need port 9443. You can block it in your firewall.

## Backup

Save the database to a file:

```sh
docker compose exec -T db sh -c 'exec mysqldump --single-transaction -uroot -p"$MYSQL_ROOT_PASSWORD" robocjk' > backup.sql
```

Load it back:

```sh
docker compose exec -T db sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" robocjk' < backup.sql
```

Keep a copy of `.env` with your backup. The data doesn't work without its
passwords.

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
