# Container health check: Django answers the API ping without redirecting.
import sys
import urllib.request

request = urllib.request.Request(
    "http://127.0.0.1:8000/api/ping/",
    data=b"",
    headers={"Host": "localhost", "X-Forwarded-Proto": "https"},
)
try:
    with urllib.request.urlopen(request, timeout=5) as response:
        sys.exit(0 if response.status == 200 else 1)
except Exception as error:
    print(error)
    sys.exit(1)
