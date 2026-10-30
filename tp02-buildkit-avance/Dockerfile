# syntax=docker/dockerfile:1.7

FROM python:3.12-slim-bookworm AS builder

ARG TARGETARCH

ENV VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:${PATH}" \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN python -m venv "${VIRTUAL_ENV}"

COPY requirements.txt ./
RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf,required=true \
    --mount=type=cache,id=pip-${TARGETARCH},target=/root/.cache/pip,sharing=locked \
    python -m pip install --no-compile -r requirements.txt

COPY worker/ ./worker/

FROM builder AS test

ARG TARGETARCH

COPY requirements-dev.txt ./
COPY tests/ ./tests/
RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf,required=true \
    --mount=type=cache,id=pip-${TARGETARCH},target=/root/.cache/pip,sharing=locked \
    python -m pip install --no-compile -r requirements-dev.txt
RUN python -m pytest -q
RUN mkdir -p /test-result && touch /test-result/passed

FROM python:3.12-slim-bookworm AS runtime

ARG APP_VERSION=1.0
ARG GIT_SHA=unknown

ENV VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN --mount=type=bind,from=test,source=/test-result,target=/tmp/test-result,ro \
    test -f /tmp/test-result/passed

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app/worker ./worker/

LABEL org.opencontainers.image.title="shop-worker" \
    org.opencontainers.image.version="${APP_VERSION}" \
    org.opencontainers.image.revision="${GIT_SHA}"

EXPOSE 9100
USER 10001:10001
CMD ["python", "-m", "worker.main"]
