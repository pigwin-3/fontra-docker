"""Import a zipped .rcjk font, creating its project and font if needed.

Used by multiuser/import-font.sh:  python import_font.py PROJECT FONT ZIPFILE
"""

import os
import sys
import uuid

sys.path.insert(0, "/srv/robocjk/src")
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "app.settings")

import django  # noqa: E402

django.setup()

from django.contrib.auth import get_user_model  # noqa: E402
from django.core.management import call_command  # noqa: E402

from robocjk.models import Font, Project  # noqa: E402


def saveBy(obj, user):
    if user is not None:
        obj.save_by(user)  # also adds the user as designer of a project
    else:
        obj.save()


def main():
    projectName, fontName, zipPath = sys.argv[1:]
    for label, value in [("project", projectName), ("font", fontName)]:
        if not 0 < len(value) <= 50:
            sys.exit(f"The {label} name must be 1 to 50 characters long.")

    admin = (
        get_user_model()
        .objects.filter(username=os.environ.get("DJANGO_SUPERUSER_USERNAME"))
        .first()
    )

    project = Project.objects.filter(name=projectName).first()
    if project is None:
        # Exporting to git needs a real repository URL. Replace this one on
        # the project's admin page before running manage.py export_rcjk.
        repoURL = f"git@github.com:change-me/{uuid.uuid4().hex}.git"
        project = Project(name=projectName, repo_url=repoURL)
        saveBy(project, admin)
        print(f"Created project {projectName!r}")

    font = Font.objects.filter(project=project, name=fontName).first()
    if font is None:
        font = Font(project=project, name=fontName)
        saveBy(font, admin)
        print(f"Created font {fontName!r}")

    call_command(
        "import_rcjk", filepath=zipPath, font_uid=str(font.uid), font_clear=True
    )
    print(f"Imported into {projectName}/{fontName}")


main()
