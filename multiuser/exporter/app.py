"""A small web app for exporting fonts from the multi-user database.

People log in with their django-robo-cjk account, the same one they use for
Fontra, and see the fonts of their projects. Each export runs export_job.py
in its own process, so a slow fontmake build doesn't block other users.
"""

import asyncio
import html
import io
import os
import pathlib
import secrets
import sys
import tempfile
import time
import zipfile
from urllib.parse import quote

from aiohttp import web
from fontra_rcjk.client_async import RCJKClientAsync

ROBOCJK_URL = os.environ.get("ROBOCJK_URL", "https://proxy:9443/")
PREFIX = "/export"
COOKIE = "fontra-export-session"
SESSION_SECONDS = 12 * 60 * 60
JOB_TIMEOUT = 30 * 60
JOB_SCRIPT = pathlib.Path(__file__).with_name("export_job.py")

FORMATS = {
    "designspace": "Designspace + UFO (.zip)",
    "ufo": "UFO (.zip)",
    "fontra": "Fontra (.zip)",
    "otf": "OpenType (.otf)",
    "ttf": "TrueType (.ttf)",
    "woff2": "Webfont (.woff2)",
}
FOLDER_FORMATS = {"designspace", "ufo", "fontra"}

sessions: dict[str, dict] = {}
jobSlots = asyncio.Semaphore(int(os.environ.get("EXPORT_PARALLEL_JOBS", "2")))

STYLE = """
:root { color-scheme: light dark; --accent: #3b6fd8; }
body { font: 15px/1.5 system-ui, sans-serif; max-width: 46rem; margin: 3rem auto;
       padding: 0 1rem; }
h1 { font-size: 1.4rem; }
form.login { display: grid; gap: .6rem; max-width: 18rem; }
input, select, button { font: inherit; padding: .35rem .5rem; }
button { background: var(--accent); color: white; border: 0; border-radius: 4px;
         cursor: pointer; }
table { border-collapse: collapse; width: 100%; }
td { padding: .45rem .3rem; border-bottom: 1px solid #8884; }
td.actions { text-align: right; white-space: nowrap; }
.error { color: #d33; }
.top { display: flex; justify-content: space-between; align-items: center; }
.hint { opacity: .7; font-size: .9em; }
"""


def page(title, body):
    return web.Response(
        content_type="text/html",
        text=(
            "<!doctype html><html><head><meta charset='utf-8'>"
            "<meta name='viewport' content='width=device-width, initial-scale=1'>"
            f"<title>{html.escape(title)}</title><style>{STYLE}</style></head>"
            f"<body>{body}</body></html>"
        ),
    )


def currentSession(request):
    session = sessions.get(request.cookies.get(COOKIE, ""))
    if session is None or session["expires"] < time.time():
        return None
    return session


async def closeSession(token):
    session = sessions.pop(token, None)
    if session is not None:
        await session["client"].close()


def loginPage(error=""):
    errorHTML = f"<p class='error'>{html.escape(error)}</p>" if error else ""
    return page(
        "Export fonts",
        f"""<h1>Export fonts</h1>
<p>Log in with your Fontra account.</p>{errorHTML}
<form class="login" method="post" action="{PREFIX}/login">
  <input name="username" placeholder="Username" autocomplete="username" required>
  <input name="password" type="password" placeholder="Password"
         autocomplete="current-password" required>
  <button>Log in</button>
</form>""",
    )


async def fontNames(session):
    mapping = await session["client"].get_project_font_uid_mapping()
    return sorted(f"{project}/{font}" for project, font in mapping)


async def index(request):
    session = currentSession(request)
    if session is None:
        return loginPage()
    names = await fontNames(session)
    options = "".join(
        f"<option value='{key}'>{html.escape(label)}</option>"
        for key, label in FORMATS.items()
    )
    rows = "".join(
        f"""<tr><td>{html.escape(name)}</td><td class="actions">
<form method="get" action="{PREFIX}/download">
<input type="hidden" name="font" value="{html.escape(name, quote=True)}">
<select name="format">{options}</select> <button>Download</button></form></td></tr>"""
        for name in names
    )
    if not rows:
        rows = "<tr><td>No fonts yet. Ask an admin to add you to a project.</td></tr>"
    return page(
        "Export fonts",
        f"""<div class="top"><h1>Export fonts</h1>
<form method="post" action="{PREFIX}/logout">{html.escape(session["user"])}
<button>Log out</button></form></div>
<table>{rows}</table>
<p class="hint">Building .otf, .ttf and .woff2 files can take a minute.
The database stores no kerning and no designspace rules, so exports have none.
If some glyphs can't be exported, the .zip lists them in export-problems.txt.</p>""",
    )


async def login(request):
    form = await request.post()
    user = form.get("username", "")
    password = form.get("password", "")
    client = RCJKClientAsync(host=ROBOCJK_URL, username=user, password=password)
    try:
        await client.connect()
    except Exception:
        await client.close()
        return loginPage("Wrong username or password.")
    token = secrets.token_urlsafe(32)
    sessions[token] = dict(
        user=user,
        password=password,
        client=client,
        expires=time.time() + SESSION_SECONDS,
    )
    response = web.HTTPFound(f"{PREFIX}/")
    response.set_cookie(
        COOKIE,
        token,
        max_age=SESSION_SECONDS,
        path=PREFIX,
        secure=True,
        httponly=True,
        samesite="Strict",
    )
    raise response


async def logout(request):
    await closeSession(request.cookies.get(COOKIE, ""))
    response = web.HTTPFound(f"{PREFIX}/")
    response.del_cookie(COOKIE, path=PREFIX)
    raise response


async def download(request):
    session = currentSession(request)
    if session is None:
        raise web.HTTPFound(f"{PREFIX}/")
    fontName = request.query.get("font", "")
    fileFormat = request.query.get("format", "")
    if fileFormat not in FORMATS or fontName not in await fontNames(session):
        raise web.HTTPNotFound()

    with tempfile.TemporaryDirectory() as tmpDir:
        outputDir = pathlib.Path(tmpDir) / "out"
        outputDir.mkdir()
        env = dict(os.environ, EXPORT_USER=session["user"], EXPORT_PASSWORD=session["password"])
        async with jobSlots:
            process = await asyncio.create_subprocess_exec(
                sys.executable, str(JOB_SCRIPT), fontName, fileFormat, str(outputDir),
                env=env,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
            )
            try:
                log, _ = await asyncio.wait_for(process.communicate(), JOB_TIMEOUT)
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()
                return errorPage(fontName, "The export took too long and was stopped.")
        print(log.decode(errors="replace"), flush=True)
        if process.returncode != 0:
            lastLines = "\n".join(log.decode(errors="replace").splitlines()[-15:])
            return errorPage(fontName, lastLines)

        baseName = fontName.split("/", 1)[1]
        if fileFormat in FOLDER_FORMATS:
            buffer = io.BytesIO()
            with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
                for path in sorted(outputDir.rglob("*")):
                    archive.write(path, path.relative_to(outputDir))
            data = buffer.getvalue()
            fileName = f"{baseName}.{fileFormat}.zip"
            contentType = "application/zip"
        else:
            fileName = f"{baseName}.{fileFormat}"
            data = (outputDir / fileName).read_bytes()
            contentType = f"font/{fileFormat}"

    return web.Response(
        body=data,
        content_type=contentType,
        headers={
            "Content-Disposition": f"attachment; filename*=UTF-8''{quote(fileName)}",
        },
    )


def errorPage(fontName, message):
    back = f"{PREFIX}/"
    return page(
        "Export failed",
        f"""<h1>Export of {html.escape(fontName)} failed</h1>
<pre>{html.escape(message)}</pre><p><a href="{back}">Back</a></p>""",
    )


async def health(request):
    return web.Response(text="ok")


async def redirectToIndex(request):
    raise web.HTTPFound(f"{PREFIX}/")


async def expireSessions(app):
    async def loop():
        while True:
            await asyncio.sleep(600)
            for token, session in list(sessions.items()):
                if session["expires"] < time.time():
                    await closeSession(token)

    task = asyncio.create_task(loop())
    yield
    task.cancel()
    for token in list(sessions):
        await closeSession(token)


def main():
    app = web.Application()
    app.cleanup_ctx.append(expireSessions)
    app.add_routes(
        [
            web.get(PREFIX, redirectToIndex),
            web.get(f"{PREFIX}/", index),
            web.post(f"{PREFIX}/login", login),
            web.post(f"{PREFIX}/logout", logout),
            web.get(f"{PREFIX}/download", download),
            web.get(f"{PREFIX}/health", health),
        ]
    )
    web.run_app(app, host="0.0.0.0", port=8000)


if __name__ == "__main__":
    main()
