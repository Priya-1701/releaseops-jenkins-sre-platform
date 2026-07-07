from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health_endpoint_returns_healthy_status():
    response = client.get("/health")

    assert response.status_code == 200

    body = response.json()

    assert body["status"] == "healthy"
    assert body["service"] == "incident-api"


def test_ready_endpoint_returns_ready_status():
    response = client.get("/ready")

    assert response.status_code == 200

    body = response.json()

    assert body["status"] == "ready"
    assert body["service"] == "incident-api"


def test_metrics_endpoint_exposes_prometheus_metrics():
    response = client.get("/metrics")

    assert response.status_code == 200
    assert "incident_api_app_info" in response.text
    assert "incident_api_open_incidents" in response.text


def test_list_incidents_returns_seed_incident():
    response = client.get("/incidents")

    assert response.status_code == 200

    body = response.json()

    assert isinstance(body, list)
    assert len(body) >= 1
    assert body[0]["status"] == "open"


def test_create_incident_returns_created_incident():
    payload = {
        "service": "payment-api",
        "severity": "SEV2",
        "summary": "Payment API error rate crossed alert threshold.",
    }

    response = client.post("/incidents", json=payload)

    assert response.status_code == 201

    body = response.json()

    assert body["service"] == "payment-api"
    assert body["severity"] == "SEV2"
    assert body["status"] == "open"
    assert "id" in body


def test_simulate_error_returns_500():
    response = client.get("/simulate/error")

    assert response.status_code == 500

    body = response.json()

    assert "Simulated application error" in body["detail"]


def test_simulate_latency_returns_success():
    response = client.get("/simulate/latency?seconds=0.1")

    assert response.status_code == 200

    body = response.json()

    assert body["status"] == "completed"
    assert body["induced_latency_seconds"] == 0.1
