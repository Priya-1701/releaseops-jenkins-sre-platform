import asyncio
import os
import time
import uuid
from typing import Literal

from fastapi import FastAPI, HTTPException, Query, Request, Response, status
from pydantic import BaseModel, Field
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest


APP_NAME = os.getenv("APP_NAME", "incident-api")
APP_VERSION = os.getenv("APP_VERSION", "0.1.0")
APP_ENV = os.getenv("APP_ENV", "local")
START_TIME = time.time()


app = FastAPI(
    title="incident-api",
    description="SRE-focused workload used by ReleaseOps Jenkins CI/CD pipeline.",
    version=APP_VERSION,
)


REQUEST_COUNT = Counter(
    "incident_api_http_requests_total",
    "Total HTTP requests handled by incident-api.",
    ["method", "endpoint", "http_status"],
)

REQUEST_LATENCY = Histogram(
    "incident_api_http_request_duration_seconds",
    "HTTP request latency in seconds for incident-api.",
    ["method", "endpoint"],
)

OPEN_INCIDENTS = Gauge(
    "incident_api_open_incidents",
    "Number of currently open incidents.",
)

APP_INFO = Gauge(
    "incident_api_app_info",
    "Application information exposed as a Prometheus metric.",
    ["app_name", "version", "environment"],
)

APP_INFO.labels(
    app_name=APP_NAME,
    version=APP_VERSION,
    environment=APP_ENV,
).set(1)


class IncidentCreate(BaseModel):
    service: str = Field(..., min_length=2, max_length=80)
    severity: Literal["SEV1", "SEV2", "SEV3", "SEV4"]
    summary: str = Field(..., min_length=5, max_length=200)


class Incident(BaseModel):
    id: str
    service: str
    severity: Literal["SEV1", "SEV2", "SEV3", "SEV4"]
    summary: str
    status: Literal["open", "resolved"]
    created_at_epoch: float


INCIDENTS: list[Incident] = [
    Incident(
        id="seed-incident-001",
        service="checkout-api",
        severity="SEV2",
        summary="Elevated latency detected on checkout-api.",
        status="open",
        created_at_epoch=time.time(),
    )
]


def refresh_open_incident_metric() -> None:
    open_count = sum(1 for incident in INCIDENTS if incident.status == "open")
    OPEN_INCIDENTS.set(open_count)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start_time = time.perf_counter()
    status_code = 500

    route = request.scope.get("route")
    endpoint = getattr(route, "path", request.url.path)

    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    finally:
        duration = time.perf_counter() - start_time

        REQUEST_COUNT.labels(
            method=request.method,
            endpoint=endpoint,
            http_status=str(status_code),
        ).inc()

        REQUEST_LATENCY.labels(
            method=request.method,
            endpoint=endpoint,
        ).observe(duration)


@app.get("/")
def root():
    return {
        "service": APP_NAME,
        "version": APP_VERSION,
        "environment": APP_ENV,
        "message": "incident-api is running",
    }


@app.get("/health")
def health():
    return {
        "status": "healthy",
        "service": APP_NAME,
        "version": APP_VERSION,
        "environment": APP_ENV,
        "uptime_seconds": round(time.time() - START_TIME, 2),
    }


@app.get("/ready")
def ready():
    force_unready = os.getenv("FORCE_UNREADY", "false").lower()

    if force_unready == "true":
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Application is not ready to receive traffic.",
        )

    return {
        "status": "ready",
        "service": APP_NAME,
        "checks": {
            "configuration_loaded": True,
            "incident_store_available": True,
        },
    }


@app.get("/metrics")
def metrics():
    refresh_open_incident_metric()
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST,
    )


@app.get("/incidents", response_model=list[Incident])
def list_incidents():
    return INCIDENTS


@app.post("/incidents", response_model=Incident, status_code=status.HTTP_201_CREATED)
def create_incident(payload: IncidentCreate):
    incident = Incident(
        id=str(uuid.uuid4()),
        service=payload.service,
        severity=payload.severity,
        summary=payload.summary,
        status="open",
        created_at_epoch=time.time(),
    )

    INCIDENTS.append(incident)
    refresh_open_incident_metric()

    return incident


@app.get("/simulate/error")
def simulate_error():
    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Simulated application error for release validation testing.",
    )


@app.get("/simulate/latency")
async def simulate_latency(
    seconds: float = Query(default=1.0, ge=0.1, le=5.0)
):
    await asyncio.sleep(seconds)

    return {
        "status": "completed",
        "message": "Simulated latency completed.",
        "induced_latency_seconds": seconds,
    }
