"""Prepare django-robo-cjk before gunicorn starts.

1. Wait until MySQL accepts connections.
2. Apply database migrations.
3. Create the admin account from DJANGO_SUPERUSER_USERNAME, _PASSWORD and
   _EMAIL, unless an account with that name exists.
4. Create the two groups that fontra-rcjk checks. Members of "Reviewers" open
   fonts read-only. Members of "DummyDesigners" can edit in the browser, but
   their edits are never saved.
"""

import os
import sys
import time

import pymysql

sys.path.insert(0, "/srv/robocjk/src")
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "app.settings")


def waitForDatabase(timeout=300):
    deadline = time.monotonic() + timeout
    while True:
        try:
            pymysql.connect(
                host=os.environ["DATABASE_HOST"],
                port=int(os.environ.get("DATABASE_PORT") or 3306),
                user=os.environ["DATABASE_USER"],
                password=os.environ["DATABASE_PASSWORD"],
                database=os.environ["DATABASE_NAME"],
                connect_timeout=5,
            ).close()
            return
        except pymysql.err.OperationalError as error:
            if time.monotonic() > deadline:
                sys.exit(f"Database still unavailable after {timeout}s: {error}")
            print(f"Waiting for the database: {error}", flush=True)
            time.sleep(3)


def main():
    waitForDatabase()

    import django
    from django.core.management import call_command

    django.setup()
    call_command("migrate", interactive=False)

    from django.contrib.auth import get_user_model
    from django.contrib.auth.models import Group

    username = os.environ.get("DJANGO_SUPERUSER_USERNAME")
    password = os.environ.get("DJANGO_SUPERUSER_PASSWORD")
    if username and password:
        User = get_user_model()
        if not User.objects.filter(username=username).exists():
            email = os.environ.get("DJANGO_SUPERUSER_EMAIL", "")
            User.objects.create_superuser(username, email, password)
            print(f"Created admin account {username!r}", flush=True)

    for name in ["Reviewers", "DummyDesigners"]:
        Group.objects.get_or_create(name=name)


main()
