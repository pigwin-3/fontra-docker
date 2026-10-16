# Defaults for the robocjk container. Override any of them with the
# GUNICORN_CMD_ARGS environment variable, e.g. "--workers 8".
import os

bind = "0.0.0.0:8000"
workers = int(os.environ.get("GUNICORN_WORKERS", "3"))
worker_class = "gthread"
threads = int(os.environ.get("GUNICORN_THREADS", "8"))
timeout = 300

# Only the nginx container can reach this port. Trusting its X-Forwarded-Proto
# header lets Django see that the original request used https, which the
# upstream settings require (SECURE_SSL_REDIRECT).
forwarded_allow_ips = "*"

accesslog = "-"
errorlog = "-"
