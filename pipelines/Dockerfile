# Image of the P6-39 reference pipeline. One image serves both Cloud Run jobs
# (<business>-ingest and <business>-build); the job's args choose the stage.
FROM python:3.13-slim

# uv from its official image, pinned to the version that wrote uv.lock.
COPY --from=ghcr.io/astral-sh/uv:0.12.16 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    DDA_PIPELINE_HOME=/app

WORKDIR /app

# Dependencies first, for layer caching.
COPY pyproject.toml uv.lock .python-version README.md ./
RUN uv sync --frozen --no-dev --no-install-project

COPY src ./src
COPY steps.yaml config.yaml ./
COPY sql ./sql
COPY lineage ./lineage
RUN uv sync --frozen --no-dev

# Run as a non-root user.
RUN useradd --uid 10001 --no-create-home pipeline
USER 10001

ENTRYPOINT ["/app/.venv/bin/dda-pipeline"]
CMD ["--help"]
