# syntax=docker/dockerfile:1

# django-robo-cjk: the Django server that keeps fonts in a MySQL database and
# manages user accounts for Fontra's multi-user mode (via fontra-rcjk).
# It has no releases, so the image is built from a git ref (default: master).

# Upstream pins Django 5.0, which supports Python 3.10 to 3.12.
ARG PYTHON_VERSION=3.12
FROM python:${PYTHON_VERSION}-slim-trixie

# git and ssh are used by the optional export to GitHub (manage.py export_rcjk).
RUN apt-get update \
    && apt-get install -y --no-install-recommends git openssh-client \
    && rm -rf /var/lib/apt/lists/*

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

ARG ROBOCJK_REPO=https://github.com/fontra/django-robo-cjk.git
ARG ROBOCJK_VERSION=master

RUN git clone --quiet --filter=blob:none --no-checkout "$ROBOCJK_REPO" /srv/robocjk/src \
    && git -C /srv/robocjk/src -c advice.detachedHead=false checkout --quiet "$ROBOCJK_VERSION" \
    && git -C /srv/robocjk/src log -1 --format='django-robo-cjk %H (%cs)' | tee /srv/robocjk/REVISION \
    && rm -rf /srv/robocjk/src/.git

# The pinned fonttools imports pkg_resources (through the `fs` package),
# which setuptools removed in version 82.
RUN pip install --no-cache-dir -r /srv/robocjk/src/requirements.txt "setuptools<82"
ENV PYTHONWARNINGS="ignore:pkg_resources is deprecated:UserWarning"

# app/settings.py requires all of these. Secrets and site-specific values
# are set in docker-compose.yml.
ENV DATABASE_ENGINE=django.db.backends.mysql \
    DATABASE_NAME=robocjk \
    DATABASE_USER=robocjk \
    DATABASE_HOST=db \
    DATABASE_PORT=3306 \
    GIT_REPOSITORIES_PATH=/data/git \
    GIT_USER_NAME=RoboCJK \
    GIT_USER_EMAIL=robocjk@localhost \
    MEDIA_ROOT=/data/media/ \
    STATIC_ROOT=/srv/robocjk/static/ \
    ALLOWED_HOSTS=localhost \
    CSRF_TRUSTED_ORIGINS=https://localhost \
    ADMIN_NAME=admin \
    ADMIN_EMAIL=admin@localhost \
    EMAIL_HOST=localhost \
    EMAIL_HOST_USER= \
    EMAIL_HOST_PASSWORD= \
    TEST_API_HOST= \
    TEST_API_USERNAME= \
    TEST_API_PASSWORD= \
    DEBUG=False

ARG UID=1000
ARG GID=1000

# settings.py writes logs and its file cache next to the source checkout
# (/srv/robocjk/logs and /srv/robocjk/cache). Both point into the /data
# volume, which also holds uploads and the git export checkouts.
WORKDIR /srv/robocjk/src
RUN groupadd -g "${GID}" robocjk \
    && useradd -m -u "${UID}" -g "${GID}" -s /bin/bash robocjk \
    && mkdir -p /data/logs /data/cache /data/media /data/git \
    && ln -s /data/logs /srv/robocjk/logs \
    && ln -s /data/cache /srv/robocjk/cache \
    && SECRET_KEY=build JWT_SECRET=build HASHIDS_SALT=build DATABASE_PASSWORD=build \
        python manage.py collectstatic --noinput --verbosity 0 \
    && rm -rf /data/logs/* /data/cache/* \
    && chown -R robocjk:robocjk /data

COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY bootstrap.py gunicorn.conf.py healthcheck.py import_font.py /srv/robocjk/

USER robocjk
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD ["python", "/srv/robocjk/healthcheck.py"]

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["gunicorn", "--config", "/srv/robocjk/gunicorn.conf.py", "app.wsgi:application"]
