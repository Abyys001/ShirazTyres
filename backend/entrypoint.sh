#!/usr/bin/env bash
set -euo pipefail

python manage.py migrate --noinput
python manage.py collectstatic --noinput
# Driver photos and documents are written here; the volume may be empty on first boot.
mkdir -p "${MEDIA_ROOT:-/app/media}"

exec "$@"
