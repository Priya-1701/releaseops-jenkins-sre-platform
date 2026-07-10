#!/usr/bin/env bash

set -Eeuo pipefail

PROMETHEUS_URL="${PROMETHEUS_URL:-http://127.0.0.1:19090}"

RELIABILITY_NAMESPACE="${RELIABILITY_NAMESPACE:-incident-staging}"

APP_NAME="${APP_NAME:-incident-api}"

REPORT_DIR="${REPORT_DIR:-reports/reliability}"

MIN_AVAILABILITY_PERCENT="${MIN_AVAILABILITY_PERCENT:-100}"

MIN_READY_REPLICAS_PERCENT="${MIN_READY_REPLICAS_PERCENT:-100}"

MAX_HTTP_5XX_PERCENT="${MAX_HTTP_5XX_PERCENT:-5}"

MAX_P95_LATENCY_SECONDS="${MAX_P95_LATENCY_SECONDS:-1}"

MAX_CONTAINER_RESTARTS="${MAX_CONTAINER_RESTARTS:-0}"

MAX_FIRING_CRITICAL_ALERTS="${MAX_FIRING_CRITICAL_ALERTS:-0}"

mkdir -p \
"${REPORT_DIR}"

LOG_FILE="${REPORT_DIR}/reliability-gate.log"

STATUS_FILE="${REPORT_DIR}/reliability-gate-status.txt"

SUMMARY_FILE="${REPORT_DIR}/reliability-gate-summary.json"

: > \
"${LOG_FILE}"

exec \
> >(
    tee \
    -a \
    "${LOG_FILE}"
  ) \
2>&1

log() {
  printf \
    '[%s] %s\n' \
    "$(
      date \
      -u \
      '+%Y-%m-%dT%H:%M:%SZ'
    )" \
    "$*" \
    >&2
}

fail_gate() {
  local MESSAGE="$1"

  echo \
    "FAILED" \
    > \
    "${STATUS_FILE}"

  log \
    "ERROR: ${MESSAGE}"

  exit 1
}

unexpected_error() {
  local EXIT_CODE=$?

  trap \
    - \
    ERR

  if \
    [ -f "${STATUS_FILE}" ] \
    && \
    [ "$(
      cat \
      "${STATUS_FILE}"
    )" = "FAILED" ]
  then
    exit \
      "${EXIT_CODE}"
  fi

  echo \
    "FAILED" \
    > \
    "${STATUS_FILE}"

  log \
    "Reliability gate stopped unexpectedly."

  exit \
    "${EXIT_CODE}"
}

require_command() {
  local COMMAND_NAME="$1"

  if ! command \
    -v \
    "${COMMAND_NAME}" \
    >/dev/null \
    2>&1
  then
    fail_gate \
      "Required command is missing: ${COMMAND_NAME}"
  fi
}

query_value() {
  local QUERY_NAME="$1"

  local PROMQL_QUERY="$2"

  local RESPONSE_FILE="${REPORT_DIR}/${QUERY_NAME}.json"

  local RESULT_COUNT

  local QUERY_RESULT

  log \
    "Evaluating ${QUERY_NAME}."

  if ! curl \
    --fail \
    --silent \
    --show-error \
    --get \
    "${PROMETHEUS_URL}/api/v1/query" \
    --data-urlencode \
    "query=${PROMQL_QUERY}" \
    > \
    "${RESPONSE_FILE}"
  then
    fail_gate \
      "Unable to query Prometheus for ${QUERY_NAME}."
  fi

  if ! jq \
    -e \
    '.status == "success"' \
    "${RESPONSE_FILE}" \
    >/dev/null
  then
    fail_gate \
      "Prometheus query failed: ${QUERY_NAME}"
  fi

  RESULT_COUNT="$(
    jq \
      '.data.result | length' \
      "${RESPONSE_FILE}"
  )"

  if \
    [ "${RESULT_COUNT}" -ne 1 ]
  then
    fail_gate \
      "Expected exactly one value for ${QUERY_NAME}, but received ${RESULT_COUNT}."
  fi

  QUERY_RESULT="$(
    jq \
      -r \
      '.data.result[0].value[1]' \
      "${RESPONSE_FILE}"
  )"

  if ! printf \
    '%s\n' \
    "${QUERY_RESULT}" \
    | grep \
      -Eq \
      '^-?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$'
  then
    fail_gate \
      "Prometheus returned a non-numeric value for ${QUERY_NAME}: ${QUERY_RESULT}"
  fi

  log \
    "${QUERY_NAME}=${QUERY_RESULT}"

  printf \
    '%s\n' \
    "${QUERY_RESULT}"
}

check_minimum() {
  local CHECK_NAME="$1"

  local ACTUAL_VALUE="$2"

  local MINIMUM_VALUE="$3"

  if jq \
    -e \
    -n \
    --argjson actual \
    "${ACTUAL_VALUE}" \
    --argjson minimum \
    "${MINIMUM_VALUE}" \
    '$actual >= $minimum' \
    >/dev/null
  then
    log \
      "PASS: ${CHECK_NAME}=${ACTUAL_VALUE}; required minimum=${MINIMUM_VALUE}"
  else
    log \
      "FAIL: ${CHECK_NAME}=${ACTUAL_VALUE}; required minimum=${MINIMUM_VALUE}"

    FAILURES=$((FAILURES + 1))
  fi
}

check_maximum() {
  local CHECK_NAME="$1"

  local ACTUAL_VALUE="$2"

  local MAXIMUM_VALUE="$3"

  if jq \
    -e \
    -n \
    --argjson actual \
    "${ACTUAL_VALUE}" \
    --argjson maximum \
    "${MAXIMUM_VALUE}" \
    '$actual <= $maximum' \
    >/dev/null
  then
    log \
      "PASS: ${CHECK_NAME}=${ACTUAL_VALUE}; allowed maximum=${MAXIMUM_VALUE}"
  else
    log \
      "FAIL: ${CHECK_NAME}=${ACTUAL_VALUE}; allowed maximum=${MAXIMUM_VALUE}"

    FAILURES=$((FAILURES + 1))
  fi
}

require_command \
curl

require_command \
jq

echo \
"RUNNING" \
> \
"${STATUS_FILE}"

EVALUATED_AT="$(
  date \
  -u \
  '+%Y-%m-%dT%H:%M:%SZ'
)"

log \
"Starting the ReleaseOps SRE Reliability Gate."

log \
"Prometheus URL: ${PROMETHEUS_URL}"

log \
"Reliability namespace: ${RELIABILITY_NAMESPACE}"

log \
"Application: ${APP_NAME}"

AVAILABILITY_QUERY="
100
*
avg(
  up{
    job=\"${APP_NAME}\",
    namespace=\"${RELIABILITY_NAMESPACE}\"
  }
)
"

READY_REPLICAS_QUERY="
100
*
max(
  kube_deployment_status_replicas_available{
    namespace=\"${RELIABILITY_NAMESPACE}\",
    deployment=\"${APP_NAME}\"
  }
)
/
clamp_min(
  max(
    kube_deployment_spec_replicas{
      namespace=\"${RELIABILITY_NAMESPACE}\",
      deployment=\"${APP_NAME}\"
    }
  ),
  1
)
"

HTTP_5XX_QUERY="
100
*
(
  (
    sum(
      rate(
        incident_api_http_requests_total{
          namespace=\"${RELIABILITY_NAMESPACE}\",
          http_status=~\"5..\"
        }[5m]
      )
    )
    or
    vector(0)
  )
  /
  clamp_min(
    (
      sum(
        rate(
          incident_api_http_requests_total{
            namespace=\"${RELIABILITY_NAMESPACE}\"
          }[5m]
        )
      )
      or
      vector(0)
    ),
    0.000001
  )
)
"

P95_LATENCY_QUERY="
histogram_quantile(
  0.95,
  sum by (
    le
  ) (
    rate(
      incident_api_http_request_duration_seconds_bucket{
        namespace=\"${RELIABILITY_NAMESPACE}\"
      }[5m]
    )
  )
)
"

CONTAINER_RESTARTS_QUERY="
sum(
  increase(
    kube_pod_container_status_restarts_total{
      namespace=\"${RELIABILITY_NAMESPACE}\",
      pod=~\"${APP_NAME}-.*\",
      container=\"${APP_NAME}\"
    }[5m]
  )
)
or
vector(0)
"

CRITICAL_ALERTS_QUERY="
sum(
  ALERTS{
    alertstate=\"firing\",
    severity=\"critical\",
    service=\"${APP_NAME}\",
    namespace=\"${RELIABILITY_NAMESPACE}\"
  }
)
or
vector(0)
"

AVAILABILITY_PERCENT="$(
  query_value \
    "availability" \
    "${AVAILABILITY_QUERY}"
)"

READY_REPLICAS_PERCENT="$(
  query_value \
    "ready-replicas" \
    "${READY_REPLICAS_QUERY}"
)"

HTTP_5XX_PERCENT="$(
  query_value \
    "http-5xx-rate" \
    "${HTTP_5XX_QUERY}"
)"

P95_LATENCY_SECONDS="$(
  query_value \
    "p95-latency" \
    "${P95_LATENCY_QUERY}"
)"

CONTAINER_RESTARTS="$(
  query_value \
    "container-restarts" \
    "${CONTAINER_RESTARTS_QUERY}"
)"

FIRING_CRITICAL_ALERTS="$(
  query_value \
    "firing-critical-alerts" \
    "${CRITICAL_ALERTS_QUERY}"
)"

FAILURES=0

check_minimum \
"availability_percent" \
"${AVAILABILITY_PERCENT}" \
"${MIN_AVAILABILITY_PERCENT}"

check_minimum \
"ready_replicas_percent" \
"${READY_REPLICAS_PERCENT}" \
"${MIN_READY_REPLICAS_PERCENT}"

check_maximum \
"http_5xx_percent" \
"${HTTP_5XX_PERCENT}" \
"${MAX_HTTP_5XX_PERCENT}"

check_maximum \
"p95_latency_seconds" \
"${P95_LATENCY_SECONDS}" \
"${MAX_P95_LATENCY_SECONDS}"

check_maximum \
"container_restarts" \
"${CONTAINER_RESTARTS}" \
"${MAX_CONTAINER_RESTARTS}"

check_maximum \
"firing_critical_alerts" \
"${FIRING_CRITICAL_ALERTS}" \
"${MAX_FIRING_CRITICAL_ALERTS}"

if \
[ "${FAILURES}" -eq 0 ]
then
  GATE_STATUS="PASSED"
else
  GATE_STATUS="FAILED"
fi

jq \
-n \
--arg \
gate_status \
"${GATE_STATUS}" \
--arg \
evaluated_at \
"${EVALUATED_AT}" \
--arg \
application \
"${APP_NAME}" \
--arg \
namespace \
"${RELIABILITY_NAMESPACE}" \
--argjson \
availability_percent \
"${AVAILABILITY_PERCENT}" \
--argjson \
ready_replicas_percent \
"${READY_REPLICAS_PERCENT}" \
--argjson \
http_5xx_percent \
"${HTTP_5XX_PERCENT}" \
--argjson \
p95_latency_seconds \
"${P95_LATENCY_SECONDS}" \
--argjson \
container_restarts \
"${CONTAINER_RESTARTS}" \
--argjson \
firing_critical_alerts \
"${FIRING_CRITICAL_ALERTS}" \
--argjson \
min_availability_percent \
"${MIN_AVAILABILITY_PERCENT}" \
--argjson \
min_ready_replicas_percent \
"${MIN_READY_REPLICAS_PERCENT}" \
--argjson \
max_http_5xx_percent \
"${MAX_HTTP_5XX_PERCENT}" \
--argjson \
max_p95_latency_seconds \
"${MAX_P95_LATENCY_SECONDS}" \
--argjson \
max_container_restarts \
"${MAX_CONTAINER_RESTARTS}" \
--argjson \
max_firing_critical_alerts \
"${MAX_FIRING_CRITICAL_ALERTS}" \
--argjson \
failures \
"${FAILURES}" \
'
{
  gate_status:
    $gate_status,

  evaluated_at:
    $evaluated_at,

  application:
    $application,

  namespace:
    $namespace,

  thresholds: {
    minimum_availability_percent:
      $min_availability_percent,

    minimum_ready_replicas_percent:
      $min_ready_replicas_percent,

    maximum_http_5xx_percent:
      $max_http_5xx_percent,

    maximum_p95_latency_seconds:
      $max_p95_latency_seconds,

    maximum_container_restarts:
      $max_container_restarts,

    maximum_firing_critical_alerts:
      $max_firing_critical_alerts
  },

  measurements: {
    availability_percent:
      $availability_percent,

    ready_replicas_percent:
      $ready_replicas_percent,

    http_5xx_percent:
      $http_5xx_percent,

    p95_latency_seconds:
      $p95_latency_seconds,

    container_restarts:
      $container_restarts,

    firing_critical_alerts:
      $firing_critical_alerts
  },

  failed_checks:
    $failures
}
' \
> \
"${SUMMARY_FILE}"

echo \
"${GATE_STATUS}" \
> \
"${STATUS_FILE}"

log \
"Reliability gate summary:"

jq . \
"${SUMMARY_FILE}"

if \
[ "${FAILURES}" -gt 0 ]
then
  log \
    "SRE RELIABILITY GATE FAILED."

  exit 1
fi

trap \
- \
ERR

log \
"SRE RELIABILITY GATE PASSED."
