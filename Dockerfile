# syntax=docker/dockerfile:1

# Fontra stopped publishing to PyPI after 0.5.2 (September 2024), so this
# image builds Fontra from its git repository instead.
#
# FONTRA_VERSION picks what to build:
#   latest      the newest release tag (default), looked up at build time
#   2026.10.0   a specific release tag
#   main        the development branch (any branch, tag or commit works)
#
# The image also contains two plugins: fontra-rcjk adds the `rcjk` subcommand
# used by the multi-user setup in multiuser/ and lets the filesystem mode open
# .rcjk projects; fontra-compile builds .otf/.ttf files with fontmake, as
# Fontra Pak's export does.

ARG PYTHON_VERSION=3.14
ARG NODE_VERSION=24
ARG DEBIAN_RELEASE=trixie

# ---------------------------------------------------------------------------
# Build stage: wheels for fontra, fontra-rcjk and fontra-compile.
# Their build hooks bundle the browser client with npm and webpack, so this
# stage needs Node.js next to Python. The resulting wheels are pure Python,
# so the stage runs on the build machine's own platform.
# ---------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM node:${NODE_VERSION}-${DEBIAN_RELEASE}-slim AS node

FROM --platform=$BUILDPLATFORM python:${PYTHON_VERSION}-slim-${DEBIAN_RELEASE} AS wheels

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

ARG FONTRA_REPO=https://github.com/fontra/fontra.git
ARG FONTRA_VERSION=latest
ARG FONTRA_RCJK_REPO=https://github.com/fontra/fontra-rcjk.git
ARG FONTRA_RCJK_VERSION=main
ARG FONTRA_COMPILE_REPO=https://github.com/fontra/fontra-compile.git
ARG FONTRA_COMPILE_VERSION=main

WORKDIR /build

# Blobless clones keep the commit and tag history that hatch-vcs needs to
# derive the package version, without downloading every old file revision.
# fontra-rcjk bundles its login page against Fontra's JS sources, which it
# pins as a git submodule.
RUN set -eu; \
    ref="$FONTRA_VERSION"; \
    if [ "$ref" = latest ]; then \
        ref="$(git ls-remote --tags --refs --sort=-v:refname "$FONTRA_REPO" \
            | sed -n 's#^.*refs/tags/##p' \
            | grep -E '^[0-9]+(\.[0-9]+)+$' \
            | head -n 1)"; \
        test -n "$ref" || { echo "No Fontra release tag found in $FONTRA_REPO" >&2; exit 1; }; \
    fi; \
    echo "Building Fontra $ref"; \
    git clone --quiet --filter=blob:none --no-checkout "$FONTRA_REPO" fontra; \
    git -C fontra -c advice.detachedHead=false checkout --quiet "$ref"; \
    git clone --quiet --filter=blob:none --no-checkout "$FONTRA_RCJK_REPO" fontra-rcjk; \
    git -C fontra-rcjk -c advice.detachedHead=false checkout --quiet "$FONTRA_RCJK_VERSION"; \
    git -C fontra-rcjk submodule --quiet update --init --filter=blob:none; \
    git clone --quiet --filter=blob:none --no-checkout "$FONTRA_COMPILE_REPO" fontra-compile; \
    git -C fontra-compile -c advice.detachedHead=false checkout --quiet "$FONTRA_COMPILE_VERSION"

# Upstream pins tested dependency versions in requirements.txt. pip refuses
# extras in a constraints file, so they are stripped first. fontra-compile
# adds its fontmake and fontc pins.
RUN --mount=type=cache,target=/root/.npm \
    --mount=type=cache,target=/root/.cache/pip \
    pip wheel --no-deps --wheel-dir /wheels ./fontra ./fontra-rcjk ./fontra-compile \
    && sed -E 's/\[[^]]*\]//' fontra/requirements.txt > /wheels/constraints.txt \
    && grep -E '^(fontmake|fontc)==' fontra-compile/requirements.txt >> /wheels/constraints.txt \
    && ls /wheels && cat /wheels/constraints.txt

# ---------------------------------------------------------------------------
# Runtime image
# ---------------------------------------------------------------------------
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_RELEASE} AS runtime

ARG UID=1000
ARG GID=1000

ENV PATH=/opt/fontra/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN --mount=type=bind,from=wheels,source=/wheels,target=/wheels \
    python -m venv /opt/fontra \
    && pip install --no-cache-dir --constraint /wheels/constraints.txt /wheels/*.whl \
    && fontra --version

RUN groupadd -g "${GID}" fontra \
    && useradd -m -u "${UID}" -g "${GID}" -s /bin/bash fontra \
    && mkdir -p /fonts /home/fontra/cache \
    && chown fontra:fontra /fonts /home/fontra/cache

# Starts Fontra. In filesystem mode it first creates this font when the
# fonts folder is empty; set FONTRA_DEFAULT_FONT to "" to turn that off.
COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
ENV FONTRA_DEFAULT_FONT=default.designspace

WORKDIR /fonts
USER fontra

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/', timeout=3)" || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["filesystem", "/fonts"]

# ---------------------------------------------------------------------------
# Export page for the multi-user setup (multiuser/exporter). Build it with
# --target exporter.
# ---------------------------------------------------------------------------
FROM runtime AS exporter

COPY multiuser/exporter/app.py multiuser/exporter/export_job.py /app/

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/export/health', timeout=3)" || exit 1

ENTRYPOINT ["python", "/app/app.py"]
CMD []

# ---------------------------------------------------------------------------
# The default build target is the plain Fontra image.
# ---------------------------------------------------------------------------
FROM runtime
