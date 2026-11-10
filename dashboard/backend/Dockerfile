# Offline build: pass a mirrored base image and a wheelhouse.
#   docker build --build-arg PYTHON_IMAGE=<mirror>/python:3.12-slim-bookworm \
#     --build-arg PIP_FIND_LINKS=/wheels -f dashboard/backend/Dockerfile dashboard/backend
# The wheelhouse must contain every distribution named in requirements.lock.
# Do not add mongomock here; it is a test-only dependency.
ARG PYTHON_IMAGE=python:3.12-slim-bookworm
FROM ${PYTHON_IMAGE}

ARG PIP_FIND_LINKS=

RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin open5g

WORKDIR /app

COPY requirements.lock ./
RUN if [ -n "$PIP_FIND_LINKS" ]; then \
      python -m pip install --no-cache-dir --no-index --find-links="$PIP_FIND_LINKS" --require-hashes -r requirements.lock; \
    else \
      python -m pip install --no-cache-dir --require-hashes -r requirements.lock; \
    fi

COPY src ./src
COPY migrations ./migrations

ENV PYTHONPATH=/app/src \
    OPEN5G_BIND_HOST=0.0.0.0 \
    OPEN5G_BIND_PORT=8000

USER open5g

EXPOSE 8000

ENTRYPOINT ["python", "-m", "open5g_dashboard"]
