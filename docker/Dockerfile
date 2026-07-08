FROM python:3.12-slim-bookworm

LABEL org.opencontainers.image.title="incident-api"
LABEL org.opencontainers.image.description="SRE-focused FastAPI workload for ReleaseOps Jenkins CI/CD platform"
LABEL org.opencontainers.image.source="releaseops-jenkins-sre-platform"
LABEL org.opencontainers.image.vendor="ReleaseOps"
LABEL org.opencontainers.image.version="0.1.0"

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV APP_NAME=incident-api
ENV APP_VERSION=0.1.0
ENV APP_ENV=container
ENV PORT=8000

WORKDIR /service

RUN addgroup --system appgroup \
    && adduser --system --ingroup appgroup --home /service appuser

COPY app/requirements.txt /service/app/requirements.txt

RUN python -m pip install --no-cache-dir --upgrade pip \
    && python -m pip install --no-cache-dir -r /service/app/requirements.txt

COPY app /service/app

RUN chown -R appuser:appgroup /service

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)" || exit 1

CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
