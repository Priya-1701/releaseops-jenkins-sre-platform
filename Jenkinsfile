pipeline {
    agent any

    options {
        timestamps()

        ansiColor('xterm')

        disableConcurrentBuilds()

        buildDiscarder(
            logRotator(
                numToKeepStr: '20'
            )
        )

        timeout(
            time: 60,
            unit: 'MINUTES'
        )

        skipDefaultCheckout(true)
    }

    environment {
        APP_NAME = 'incident-api'

        PYTHON_VENV = '.venv'

        DOCKER_IMAGE_LOCAL = 'incident-api'

        DOCKERHUB_REPOSITORY =
            'docker.io/priyanka1701/incident-api'

        CI_REPORT_DIR =
            'reports/ci'

        CD_REPORT_DIR =
            'reports/cd'

        RELIABILITY_REPORT_DIR =
            'reports/reliability'

        DEV_NAMESPACE =
            'incident-dev'

        STAGING_NAMESPACE =
            'incident-staging'

        MONITORING_NAMESPACE =
            'monitoring'

        MONITORING_RELEASE =
            'releaseops-monitoring'

        MIN_AVAILABILITY_PERCENT =
            '100'

        MIN_READY_REPLICAS_PERCENT =
            '100'

        MAX_HTTP_5XX_PERCENT =
            '5'

        MAX_P95_LATENCY_SECONDS =
            '1'

        MAX_CONTAINER_RESTARTS =
            '0'

        MAX_FIRING_CRITICAL_ALERTS =
            '0'

        TRIVY_DISABLE_VEX_NOTICE =
            'true'
    }

    stages {
        stage('Checkout Source') {
            steps {
                cleanWs()

                checkout scm

                script {
                    env.GIT_SHORT_SHA = sh(
                        script:
                            'git rev-parse --short HEAD',
                        returnStdout:
                            true
                    ).trim()

                    env.IMAGE_TAG =
                        "ci-${env.BUILD_NUMBER}-${env.GIT_SHORT_SHA}"

                    env.LOCAL_IMAGE =
                        "${env.DOCKER_IMAGE_LOCAL}:${env.IMAGE_TAG}"

                    env.REGISTRY_IMAGE =
                        "${env.DOCKERHUB_REPOSITORY}:${env.IMAGE_TAG}"

                    env.REGISTRY_IMAGE_LATEST =
                        "${env.DOCKERHUB_REPOSITORY}:latest"
                }

                sh '''
                    set -e

                    echo "Current workspace:"
                    pwd

                    echo "Git commit:"
                    git rev-parse --short HEAD

                    echo "Versioned release image:"
                    echo "${REGISTRY_IMAGE}"

                    echo "Repository files:"
                    ls -la
                '''
            }
        }

        stage('Prepare Python Environment') {
            steps {
                sh '''
                    set -e

                    rm -rf \
                      "${PYTHON_VENV}"

                    python3 \
                      -m venv \
                      "${PYTHON_VENV}"

                    . \
                      "${PYTHON_VENV}/bin/activate"

                    python \
                      -m pip \
                      install \
                      --upgrade \
                      pip

                    python \
                      -m pip \
                      install \
                      -r app/requirements-dev.txt

                    python \
                      -m pip \
                      freeze
                '''
            }
        }

        stage('Lint Code') {
            steps {
                sh '''
                    set -e

                    . \
                      "${PYTHON_VENV}/bin/activate"

                    python \
                      -m ruff \
                      check \
                      app
                '''
            }
        }

        stage('Run Unit Tests') {
            steps {
                sh '''
                    set -e

                    . \
                      "${PYTHON_VENV}/bin/activate"

                    mkdir -p \
                      "${CI_REPORT_DIR}"

                    python \
                      -m pytest \
                      app/tests \
                      --junitxml="${CI_REPORT_DIR}/pytest-results.xml"
                '''
            }

            post {
                always {
                    junit(
                        allowEmptyResults:
                            false,

                        testResults:
                            'reports/ci/pytest-results.xml'
                    )
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    set -e

                    docker build \
                      -f docker/Dockerfile \
                      -t "${LOCAL_IMAGE}" \
                      .

                    docker image inspect \
                      "${LOCAL_IMAGE}" \
                      >/dev/null

                    echo \
                      "Docker image built successfully."

                    echo \
                      "Local image: ${LOCAL_IMAGE}"
                '''
            }
        }

        stage('Scan Docker Image') {
            steps {
                sh '''
                    set -e

                    mkdir -p \
                      "${CI_REPORT_DIR}"

                    echo \
                      "Generating the complete HIGH and CRITICAL vulnerability report..."

                    trivy image \
                      --exit-code 0 \
                      --severity HIGH,CRITICAL \
                      --no-progress \
                      --format json \
                      --output \
                      "${CI_REPORT_DIR}/trivy-image-report.json" \
                      "${LOCAL_IMAGE}"

                    echo \
                      "Running the blocking CRITICAL vulnerability gate..."

                    trivy image \
                      --scanners vuln \
                      --ignore-unfixed \
                      --exit-code 1 \
                      --severity CRITICAL \
                      --no-progress \
                      --format table \
                      "${LOCAL_IMAGE}"

                    echo \
                      "Docker image security gate passed."
                '''
            }
        }

        stage('Tag DockerHub Images') {
            steps {
                sh '''
                    set -e

                    docker tag \
                      "${LOCAL_IMAGE}" \
                      "${REGISTRY_IMAGE}"

                    docker tag \
                      "${LOCAL_IMAGE}" \
                      "${REGISTRY_IMAGE_LATEST}"

                    docker image ls \
                      "${DOCKERHUB_REPOSITORY}"

                    echo \
                      "DockerHub image tags created."

                    echo \
                      "Immutable image: ${REGISTRY_IMAGE}"

                    echo \
                      "Convenience image: ${REGISTRY_IMAGE_LATEST}"
                '''
            }
        }

        stage('Push Docker Image to DockerHub') {
            steps {
                retry(3) {
                    withCredentials([
                        usernamePassword(
                            credentialsId:
                                'dockerhub-creds',

                            usernameVariable:
                                'DOCKERHUB_USERNAME',

                            passwordVariable:
                                'DOCKERHUB_TOKEN'
                        )
                    ]) {
                        sh '''
                            set +x

                            set -e

                            export DOCKER_CONFIG=\
"${WORKSPACE}/.docker"

                            rm -rf \
                              "${DOCKER_CONFIG}"

                            mkdir -p \
                              "${DOCKER_CONFIG}"

                            cleanup_docker_auth() {
                              docker logout \
                                docker.io \
                                >/dev/null \
                                2>&1 \
                                || true

                              rm -rf \
                                "${DOCKER_CONFIG}"
                            }

                            trap \
                              cleanup_docker_auth \
                              EXIT

                            echo \
                              "${DOCKERHUB_TOKEN}" \
                            | docker login \
                                docker.io \
                                -u \
                                "${DOCKERHUB_USERNAME}" \
                                --password-stdin

                            docker push \
                              "${REGISTRY_IMAGE}"

                            docker push \
                              "${REGISTRY_IMAGE_LATEST}"

                            echo \
                              "DockerHub push completed successfully."
                        '''
                    }
                }
            }
        }

        stage('Validate Kubernetes Access') {
            steps {
                withCredentials([
                    file(
                        credentialsId:
                            'releaseops-kubeconfig',

                        variable:
                            'KUBECONFIG_FILE'
                    )
                ]) {
                    sh '''
                        set -e

                        export KUBECONFIG=\
"${KUBECONFIG_FILE}"

                        echo \
                          "Checking dev deployment access..."

                        DEV_ACCESS="$(
                          kubectl auth can-i \
                            patch deployments.apps \
                            -n "${DEV_NAMESPACE}"
                        )"

                        test \
                          "${DEV_ACCESS}" \
                          = \
                          "yes"

                        echo \
                          "Checking staging deployment access..."

                        STAGING_ACCESS="$(
                          kubectl auth can-i \
                            patch deployments.apps \
                            -n "${STAGING_NAMESPACE}"
                        )"

                        test \
                          "${STAGING_ACCESS}" \
                          = \
                          "yes"

                        echo \
                          "Confirming production deployment access is denied..."

                        PROD_ACCESS="$(
                          kubectl auth can-i \
                            patch deployments.apps \
                            -n incident-prod \
                            || true
                        )"

                        test \
                          "${PROD_ACCESS}" \
                          = \
                          "no"

                        echo \
                          "Checking monitoring Service access..."

                        MONITORING_SERVICE_ACCESS="$(
                          kubectl auth can-i \
                            get services \
                            -n "${MONITORING_NAMESPACE}"
                        )"

                        test \
                          "${MONITORING_SERVICE_ACCESS}" \
                          = \
                          "yes"

                        echo \
                          "Checking monitoring Pod access..."

                        MONITORING_POD_ACCESS="$(
                          kubectl auth can-i \
                            list pods \
                            -n "${MONITORING_NAMESPACE}"
                        )"

                        test \
                          "${MONITORING_POD_ACCESS}" \
                          = \
                          "yes"

                        echo \
                          "Checking monitoring port-forward access..."

                        MONITORING_PORT_FORWARD_ACCESS="$(
                          kubectl auth can-i \
                            create pods/portforward \
                            -n "${MONITORING_NAMESPACE}"
                        )"

                        test \
                          "${MONITORING_PORT_FORWARD_ACCESS}" \
                          = \
                          "yes"

                        echo \
                          "Confirming monitoring Secret access is denied..."

                        MONITORING_SECRET_ACCESS="$(
                          kubectl auth can-i \
                            get secrets \
                            -n "${MONITORING_NAMESPACE}" \
                            || true
                        )"

                        test \
                          "${MONITORING_SECRET_ACCESS}" \
                          = \
                          "no"

                        kubectl \
                          -n "${DEV_NAMESPACE}" \
                          get deployment \
                          "${APP_NAME}"

                        kubectl \
                          -n "${STAGING_NAMESPACE}" \
                          get deployment \
                          "${APP_NAME}"

                        kubectl \
                          -n "${MONITORING_NAMESPACE}" \
                          get services

                        echo \
                          "Kubernetes least-privilege access validation passed."
                    '''
                }
            }
        }

        stage('Deploy to Dev') {
            steps {
                withCredentials([
                    file(
                        credentialsId:
                            'releaseops-kubeconfig',

                        variable:
                            'KUBECONFIG_FILE'
                    )
                ]) {
                    sh '''
                        set -e

                        export KUBECONFIG=\
"${KUBECONFIG_FILE}"

                        mkdir -p \
                          "${CD_REPORT_DIR}"

                        PREVIOUS_IMAGE="$(
                          kubectl \
                            -n "${DEV_NAMESPACE}" \
                            get deployment \
                            "${APP_NAME}" \
                            -o jsonpath=\
'{.spec.template.spec.containers[0].image}'
                        )"

                        echo \
                          "${PREVIOUS_IMAGE}" \
                        > \
"${CD_REPORT_DIR}/dev-previous-image.txt"

                        echo \
                          "Previous dev image: ${PREVIOUS_IMAGE}"

                        kubectl \
                          -n "${DEV_NAMESPACE}" \
                          annotate deployment \
                          "${APP_NAME}" \
                          releaseops.io/build-number=\
"${BUILD_NUMBER}" \
                          releaseops.io/git-sha=\
"${GIT_SHORT_SHA}" \
                          releaseops.io/image-tag=\
"${IMAGE_TAG}" \
                          --overwrite

                        kubectl \
                          -n "${DEV_NAMESPACE}" \
                          set image \
                          deployment/"${APP_NAME}" \
                          "${APP_NAME}"=\
"${REGISTRY_IMAGE}"

                        kubectl \
                          -n "${DEV_NAMESPACE}" \
                          rollout status \
                          deployment/"${APP_NAME}" \
                          --timeout=180s

                        ACTUAL_IMAGE="$(
                          kubectl \
                            -n "${DEV_NAMESPACE}" \
                            get deployment \
                            "${APP_NAME}" \
                            -o jsonpath=\
'{.spec.template.spec.containers[0].image}'
                        )"

                        test \
                          "${ACTUAL_IMAGE}" \
                          = \
                          "${REGISTRY_IMAGE}"

                        echo \
                          "${ACTUAL_IMAGE}" \
                        > \
"${CD_REPORT_DIR}/dev-deployed-image.txt"

                        kubectl \
                          -n "${DEV_NAMESPACE}" \
                          get deployment \
                          "${APP_NAME}" \
                          -o yaml \
                        > \
"${CD_REPORT_DIR}/dev-deployment.yaml"

                        kubectl \
                          -n "${DEV_NAMESPACE}" \
                          get pods \
                          -o wide \
                        > \
"${CD_REPORT_DIR}/dev-pods.txt"

                        kubectl \
                          -n "${DEV_NAMESPACE}" \
                          rollout history \
                          deployment/"${APP_NAME}" \
                        > \
"${CD_REPORT_DIR}/dev-rollout-history.txt"

                        echo \
                          "Dev deployed image: ${ACTUAL_IMAGE}"

                        echo \
                          "Dev deployment completed successfully."
                    '''
                }
            }
        }

        stage('Smoke Test Dev') {
            steps {
                withCredentials([
                    file(
                        credentialsId:
                            'releaseops-kubeconfig',

                        variable:
                            'KUBECONFIG_FILE'
                    )
                ]) {
                    sh '''
                        set -e

                        export KUBECONFIG=\
"${KUBECONFIG_FILE}"

                        mkdir -p \
                          "${CD_REPORT_DIR}"

                        kubectl \
                          -n "${DEV_NAMESPACE}" \
                          port-forward \
                          service/"${APP_NAME}" \
                          18080:80 \
                        > \
"${CD_REPORT_DIR}/dev-port-forward.log" \
                          2>&1 &

                        PORT_FORWARD_PID=$!

                        cleanup_port_forward() {
                          kill \
                            "${PORT_FORWARD_PID}" \
                            >/dev/null \
                            2>&1 \
                            || true

                          wait \
                            "${PORT_FORWARD_PID}" \
                            2>/dev/null \
                            || true
                        }

                        trap \
                          cleanup_port_forward \
                          EXIT INT TERM

                        DEV_HEALTHY=false

                        for ATTEMPT in \
                          $(seq 1 30)
                        do
                          if curl \
                            --fail \
                            --silent \
                            --show-error \
                            --connect-timeout 2 \
                            --max-time 5 \
                            -o \
"${CD_REPORT_DIR}/dev-health.json" \
                            http://127.0.0.1:18080/health
                          then
                            DEV_HEALTHY=true

                            break
                          fi

                          echo \
                            "Waiting for dev application. Attempt ${ATTEMPT}/30"

                          sleep 2
                        done

                        if \
                          [ "${DEV_HEALTHY}" != "true" ]
                        then
                          cat \
"${CD_REPORT_DIR}/dev-port-forward.log"

                          exit 1
                        fi

                        curl \
                          --fail \
                          --silent \
                          --show-error \
                          --max-time 10 \
                          -o \
"${CD_REPORT_DIR}/dev-ready.json" \
                          http://127.0.0.1:18080/ready

                        curl \
                          --fail \
                          --silent \
                          --show-error \
                          --max-time 10 \
                          -o \
"${CD_REPORT_DIR}/dev-incidents.json" \
                          http://127.0.0.1:18080/incidents

                        curl \
                          --fail \
                          --silent \
                          --show-error \
                          --max-time 10 \
                          -o \
"${CD_REPORT_DIR}/dev-metrics.txt" \
                          http://127.0.0.1:18080/metrics

                        grep \
                          -q \
                          "incident_api_app_info" \
"${CD_REPORT_DIR}/dev-metrics.txt"

                        echo \
                          "Dev health response:"

                        jq . \
"${CD_REPORT_DIR}/dev-health.json"

                        echo \
                          "Dev readiness response:"

                        jq . \
"${CD_REPORT_DIR}/dev-ready.json"

                        echo \
                          "Dev smoke test passed."
                    '''
                }
            }
        }

        stage('Deploy to Staging') {
            steps {
                withCredentials([
                    file(
                        credentialsId:
                            'releaseops-kubeconfig',

                        variable:
                            'KUBECONFIG_FILE'
                    )
                ]) {
                    sh '''
                        set -e

                        export KUBECONFIG=\
"${KUBECONFIG_FILE}"

                        mkdir -p \
                          "${CD_REPORT_DIR}"

                        PREVIOUS_IMAGE="$(
                          kubectl \
                            -n "${STAGING_NAMESPACE}" \
                            get deployment \
                            "${APP_NAME}" \
                            -o jsonpath=\
'{.spec.template.spec.containers[0].image}'
                        )"

                        echo \
                          "${PREVIOUS_IMAGE}" \
                        > \
"${CD_REPORT_DIR}/staging-previous-image.txt"

                        echo \
                          "Previous staging image: ${PREVIOUS_IMAGE}"

                        kubectl \
                          -n "${STAGING_NAMESPACE}" \
                          annotate deployment \
                          "${APP_NAME}" \
                          releaseops.io/build-number=\
"${BUILD_NUMBER}" \
                          releaseops.io/git-sha=\
"${GIT_SHORT_SHA}" \
                          releaseops.io/image-tag=\
"${IMAGE_TAG}" \
                          --overwrite

                        kubectl \
                          -n "${STAGING_NAMESPACE}" \
                          set image \
                          deployment/"${APP_NAME}" \
                          "${APP_NAME}"=\
"${REGISTRY_IMAGE}"

                        kubectl \
                          -n "${STAGING_NAMESPACE}" \
                          rollout status \
                          deployment/"${APP_NAME}" \
                          --timeout=180s

                        ACTUAL_IMAGE="$(
                          kubectl \
                            -n "${STAGING_NAMESPACE}" \
                            get deployment \
                            "${APP_NAME}" \
                            -o jsonpath=\
'{.spec.template.spec.containers[0].image}'
                        )"

                        test \
                          "${ACTUAL_IMAGE}" \
                          = \
                          "${REGISTRY_IMAGE}"

                        echo \
                          "${ACTUAL_IMAGE}" \
                        > \
"${CD_REPORT_DIR}/staging-deployed-image.txt"

                        kubectl \
                          -n "${STAGING_NAMESPACE}" \
                          get deployment \
                          "${APP_NAME}" \
                          -o yaml \
                        > \
"${CD_REPORT_DIR}/staging-deployment.yaml"

                        kubectl \
                          -n "${STAGING_NAMESPACE}" \
                          get pods \
                          -o wide \
                        > \
"${CD_REPORT_DIR}/staging-pods.txt"

                        kubectl \
                          -n "${STAGING_NAMESPACE}" \
                          rollout history \
                          deployment/"${APP_NAME}" \
                        > \
"${CD_REPORT_DIR}/staging-rollout-history.txt"

                        echo \
                          "Staging deployed image: ${ACTUAL_IMAGE}"

                        echo \
                          "Staging deployment completed successfully."
                    '''
                }
            }
        }

        stage('Smoke Test Staging') {
            steps {
                withCredentials([
                    file(
                        credentialsId:
                            'releaseops-kubeconfig',

                        variable:
                            'KUBECONFIG_FILE'
                    )
                ]) {
                    sh '''
                        set -e

                        export KUBECONFIG=\
"${KUBECONFIG_FILE}"

                        mkdir -p \
                          "${CD_REPORT_DIR}"

                        kubectl \
                          -n "${STAGING_NAMESPACE}" \
                          port-forward \
                          service/"${APP_NAME}" \
                          18081:80 \
                        > \
"${CD_REPORT_DIR}/staging-port-forward.log" \
                          2>&1 &

                        PORT_FORWARD_PID=$!

                        cleanup_port_forward() {
                          kill \
                            "${PORT_FORWARD_PID}" \
                            >/dev/null \
                            2>&1 \
                            || true

                          wait \
                            "${PORT_FORWARD_PID}" \
                            2>/dev/null \
                            || true
                        }

                        trap \
                          cleanup_port_forward \
                          EXIT INT TERM

                        STAGING_HEALTHY=false

                        for ATTEMPT in \
                          $(seq 1 30)
                        do
                          if curl \
                            --fail \
                            --silent \
                            --show-error \
                            --connect-timeout 2 \
                            --max-time 5 \
                            -o \
"${CD_REPORT_DIR}/staging-health.json" \
                            http://127.0.0.1:18081/health
                          then
                            STAGING_HEALTHY=true

                            break
                          fi

                          echo \
                            "Waiting for staging application. Attempt ${ATTEMPT}/30"

                          sleep 2
                        done

                        if \
                          [ "${STAGING_HEALTHY}" != "true" ]
                        then
                          cat \
"${CD_REPORT_DIR}/staging-port-forward.log"

                          exit 1
                        fi

                        curl \
                          --fail \
                          --silent \
                          --show-error \
                          --max-time 10 \
                          -o \
"${CD_REPORT_DIR}/staging-ready.json" \
                          http://127.0.0.1:18081/ready

                        curl \
                          --fail \
                          --silent \
                          --show-error \
                          --max-time 10 \
                          -o \
"${CD_REPORT_DIR}/staging-incidents.json" \
                          http://127.0.0.1:18081/incidents

                        curl \
                          --fail \
                          --silent \
                          --show-error \
                          --max-time 10 \
                          -o \
"${CD_REPORT_DIR}/staging-metrics.txt" \
                          http://127.0.0.1:18081/metrics

                        grep \
                          -q \
                          "incident_api_app_info" \
"${CD_REPORT_DIR}/staging-metrics.txt"

                        echo \
                          "Staging health response:"

                        jq . \
"${CD_REPORT_DIR}/staging-health.json"

                        echo \
                          "Staging readiness response:"

                        jq . \
"${CD_REPORT_DIR}/staging-ready.json"

                        echo \
                          "Staging smoke test passed."
                    '''
                }
            }
        }

        stage('SRE Reliability Gate') {
            steps {
                withCredentials([
                    file(
                        credentialsId:
                            'releaseops-kubeconfig',

                        variable:
                            'KUBECONFIG_FILE'
                    )
                ]) {
                    sh '''
                        set -e

                        export KUBECONFIG=\
"${KUBECONFIG_FILE}"

                        rm -rf \
                          "${RELIABILITY_REPORT_DIR}"

                        mkdir -p \
                          "${RELIABILITY_REPORT_DIR}"

                        echo \
                          "Discovering the Prometheus Service..."

                        PROMETHEUS_SERVICE="$(
                          kubectl \
                            -n "${MONITORING_NAMESPACE}" \
                            get service \
                            -l \
"release=${MONITORING_RELEASE}" \
                            -o json \
                          | jq \
                            -r '
                              .items[]

                              | select(
                                  any(
                                    .spec.ports[]?;
                                    .port == 9090
                                  )
                                )

                              | .metadata.name
                            ' \
                          | head -n 1
                        )"

                        test \
                          -n \
                          "${PROMETHEUS_SERVICE}"

                        echo \
                          "Prometheus Service: ${PROMETHEUS_SERVICE}"

                        PROMETHEUS_PORT_FORWARD_PID=""

                        STAGING_PORT_FORWARD_PID=""

                        cleanup_reliability_gate() {
                          if \
                            [ -n "${PROMETHEUS_PORT_FORWARD_PID}" ]
                          then
                            kill \
                              "${PROMETHEUS_PORT_FORWARD_PID}" \
                              >/dev/null \
                              2>&1 \
                              || true

                            wait \
                              "${PROMETHEUS_PORT_FORWARD_PID}" \
                              2>/dev/null \
                              || true
                          fi

                          if \
                            [ -n "${STAGING_PORT_FORWARD_PID}" ]
                          then
                            kill \
                              "${STAGING_PORT_FORWARD_PID}" \
                              >/dev/null \
                              2>&1 \
                              || true

                            wait \
                              "${STAGING_PORT_FORWARD_PID}" \
                              2>/dev/null \
                              || true
                          fi
                        }

                        trap \
                          cleanup_reliability_gate \
                          EXIT INT TERM

                        echo \
                          "Starting the Jenkins-to-Prometheus port-forward..."

                        kubectl \
                          -n "${MONITORING_NAMESPACE}" \
                          port-forward \
                          service/"${PROMETHEUS_SERVICE}" \
                          19090:9090 \
                        > \
"${RELIABILITY_REPORT_DIR}/prometheus-port-forward.log" \
                          2>&1 &

                        PROMETHEUS_PORT_FORWARD_PID=$!

                        PROMETHEUS_READY=false

                        for ATTEMPT in \
                          $(seq 1 30)
                        do
                          if curl \
                            --fail \
                            --silent \
                            --show-error \
                            --connect-timeout 2 \
                            --max-time 5 \
                            http://127.0.0.1:19090/-/ready \
                            >/dev/null
                          then
                            PROMETHEUS_READY=true

                            break
                          fi

                          echo \
                            "Waiting for Prometheus. Attempt ${ATTEMPT}/30"

                          sleep 2
                        done

                        if \
                          [ "${PROMETHEUS_READY}" != "true" ]
                        then
                          echo \
                            "Prometheus did not become ready."

                          cat \
"${RELIABILITY_REPORT_DIR}/prometheus-port-forward.log"

                          exit 1
                        fi

                        echo \
                          "Prometheus is ready."

                        echo \
                          "Starting the staging validation port-forward..."

                        kubectl \
                          -n "${STAGING_NAMESPACE}" \
                          port-forward \
                          service/"${APP_NAME}" \
                          18082:80 \
                        > \
"${RELIABILITY_REPORT_DIR}/staging-validation-port-forward.log" \
                          2>&1 &

                        STAGING_PORT_FORWARD_PID=$!

                        STAGING_READY=false

                        for ATTEMPT in \
                          $(seq 1 30)
                        do
                          if curl \
                            --fail \
                            --silent \
                            --show-error \
                            --connect-timeout 2 \
                            --max-time 5 \
                            http://127.0.0.1:18082/ready \
                            >/dev/null
                          then
                            STAGING_READY=true

                            break
                          fi

                          echo \
                            "Waiting for the staging validation endpoint. Attempt ${ATTEMPT}/30"

                          sleep 2
                        done

                        if \
                          [ "${STAGING_READY}" != "true" ]
                        then
                          echo \
                            "The staging validation endpoint did not become ready."

                          cat \
"${RELIABILITY_REPORT_DIR}/staging-validation-port-forward.log"

                          exit 1
                        fi

                        echo \
                          "Generating controlled healthy staging validation traffic..."

                        for REQUEST_NUMBER in \
                          $(seq 1 20)
                        do
                          curl \
                            --fail \
                            --silent \
                            --show-error \
                            --max-time 10 \
                            --output /dev/null \
                            http://127.0.0.1:18082/health

                          curl \
                            --fail \
                            --silent \
                            --show-error \
                            --max-time 10 \
                            --output /dev/null \
                            http://127.0.0.1:18082/ready

                          curl \
                            --fail \
                            --silent \
                            --show-error \
                            --max-time 10 \
                            --output /dev/null \
                            http://127.0.0.1:18082/incidents
                        done

                        echo \
                          "Controlled staging validation traffic completed."

                        echo \
                          "Waiting 45 seconds for Prometheus to collect fresh release samples..."

                        sleep 45

                        echo \
                          "Running the ReleaseOps SRE Reliability Gate..."

                        PROMETHEUS_URL=\
"http://127.0.0.1:19090" \
                        RELIABILITY_NAMESPACE=\
"${STAGING_NAMESPACE}" \
                        APP_NAME=\
"${APP_NAME}" \
                        REPORT_DIR=\
"${RELIABILITY_REPORT_DIR}" \
                        MIN_AVAILABILITY_PERCENT=\
"${MIN_AVAILABILITY_PERCENT}" \
                        MIN_READY_REPLICAS_PERCENT=\
"${MIN_READY_REPLICAS_PERCENT}" \
                        MAX_HTTP_5XX_PERCENT=\
"${MAX_HTTP_5XX_PERCENT}" \
                        MAX_P95_LATENCY_SECONDS=\
"${MAX_P95_LATENCY_SECONDS}" \
                        MAX_CONTAINER_RESTARTS=\
"${MAX_CONTAINER_RESTARTS}" \
                        MAX_FIRING_CRITICAL_ALERTS=\
"${MAX_FIRING_CRITICAL_ALERTS}" \
                        bash \
                          ./scripts/run_reliability_gate.sh

                        test \
                          -f \
"${RELIABILITY_REPORT_DIR}/reliability-gate-summary.json"

                        test \
                          -f \
"${RELIABILITY_REPORT_DIR}/reliability-gate-status.txt"

                        RELIABILITY_GATE_STATUS="$(
                          cat \
"${RELIABILITY_REPORT_DIR}/reliability-gate-status.txt"
                        )"

                        test \
                          "${RELIABILITY_GATE_STATUS}" \
                          = \
                          "PASSED"

                        echo \
                          "Reliability gate result:"

                        jq . \
"${RELIABILITY_REPORT_DIR}/reliability-gate-summary.json"

                        echo \
                          "SRE Reliability Gate completed successfully."
                    '''
                }
            }
        }

        stage('Archive Release Metadata') {
            steps {
                withCredentials([
                    file(
                        credentialsId:
                            'releaseops-kubeconfig',

                        variable:
                            'KUBECONFIG_FILE'
                    )
                ]) {
                    sh '''
                        set -e

                        export KUBECONFIG=\
"${KUBECONFIG_FILE}"

                        mkdir -p \
                          "${CI_REPORT_DIR}" \
                          "${CD_REPORT_DIR}" \
                          "${RELIABILITY_REPORT_DIR}"

                        DEV_IMAGE="$(
                          kubectl \
                            -n "${DEV_NAMESPACE}" \
                            get deployment \
                            "${APP_NAME}" \
                            -o jsonpath=\
'{.spec.template.spec.containers[0].image}'
                        )"

                        STAGING_IMAGE="$(
                          kubectl \
                            -n "${STAGING_NAMESPACE}" \
                            get deployment \
                            "${APP_NAME}" \
                            -o jsonpath=\
'{.spec.template.spec.containers[0].image}'
                        )"

                        test \
                          "${DEV_IMAGE}" \
                          = \
                          "${REGISTRY_IMAGE}"

                        test \
                          "${STAGING_IMAGE}" \
                          = \
                          "${REGISTRY_IMAGE}"

                        RELIABILITY_GATE_STATUS="$(
                          jq \
                            -r \
                            '.gate_status' \
"${RELIABILITY_REPORT_DIR}/reliability-gate-summary.json"
                        )"

                        test \
                          "${RELIABILITY_GATE_STATUS}" \
                          = \
                          "PASSED"

                        jq \
                          -n \
                          --arg \
                          application \
                          "${APP_NAME}" \
                          --arg \
                          jenkins_build_number \
                          "${BUILD_NUMBER}" \
                          --arg \
                          git_commit_short \
                          "${GIT_SHORT_SHA}" \
                          --arg \
                          local_image \
                          "${LOCAL_IMAGE}" \
                          --arg \
                          registry_image \
                          "${REGISTRY_IMAGE}" \
                          --arg \
                          latest_image \
                          "${REGISTRY_IMAGE_LATEST}" \
                          '
                          {
                            application:
                              $application,

                            jenkins_build_number:
                              $jenkins_build_number,

                            git_commit_short:
                              $git_commit_short,

                            local_image:
                              $local_image,

                            registry_image:
                              $registry_image,

                            latest_image:
                              $latest_image,

                            pipeline_type:
                              "ci-cd-sre-reliability-gated",

                            result:
                              "success"
                          }
                          ' \
                        > \
"${CI_REPORT_DIR}/build-metadata.json"

                        jq \
                          -n \
                          --arg \
                          application \
                          "${APP_NAME}" \
                          --arg \
                          jenkins_build_number \
                          "${BUILD_NUMBER}" \
                          --arg \
                          git_commit_short \
                          "${GIT_SHORT_SHA}" \
                          --arg \
                          promoted_image \
                          "${REGISTRY_IMAGE}" \
                          --arg \
                          dev_namespace \
                          "${DEV_NAMESPACE}" \
                          --arg \
                          dev_image \
                          "${DEV_IMAGE}" \
                          --arg \
                          staging_namespace \
                          "${STAGING_NAMESPACE}" \
                          --arg \
                          staging_image \
                          "${STAGING_IMAGE}" \
                          --arg \
                          staging_reliability_gate \
                          "${RELIABILITY_GATE_STATUS}" \
                          --arg \
                          reliability_evidence \
"${RELIABILITY_REPORT_DIR}/reliability-gate-summary.json" \
                          '
                          {
                            application:
                              $application,

                            jenkins_build_number:
                              $jenkins_build_number,

                            git_commit_short:
                              $git_commit_short,

                            promoted_image:
                              $promoted_image,

                            dev_namespace:
                              $dev_namespace,

                            dev_image:
                              $dev_image,

                            dev_smoke_test:
                              "passed",

                            staging_namespace:
                              $staging_namespace,

                            staging_image:
                              $staging_image,

                            staging_smoke_test:
                              "passed",

                            staging_reliability_gate:
                              $staging_reliability_gate,

                            reliability_evidence:
                              $reliability_evidence,

                            production_deployed:
                              false,

                            result:
                              "success"
                          }
                          ' \
                        > \
"${CD_REPORT_DIR}/release-metadata.json"

                        echo \
                          "Build metadata:"

                        jq . \
"${CI_REPORT_DIR}/build-metadata.json"

                        echo \
                          "Release metadata:"

                        jq . \
"${CD_REPORT_DIR}/release-metadata.json"

                        echo \
                          "Release metadata archived successfully."
                    '''
                }
            }
        }
    }

    post {
        success {
            echo '''
ReleaseOps CI/CD pipeline completed successfully.

The same immutable Docker image passed:

- CI validation
- Unit testing
- Docker security scanning
- DockerHub publication
- Dev deployment
- Dev smoke testing
- Staging deployment
- Staging smoke testing
- Prometheus SRE reliability gate

The release remains blocked from production until the later
production-promotion phase is implemented.
'''
        }

        failure {
            echo '''
ReleaseOps CI/CD pipeline failed.

The pipeline stopped before further promotion.

Review:

- The failed Jenkins stage
- Console output
- CI evidence
- CD evidence
- Reliability-gate evidence
'''
        }

        always {
            archiveArtifacts(
                artifacts:
                    'reports/ci/*,reports/cd/*,reports/reliability/*',

                fingerprint:
                    true,

                allowEmptyArchive:
                    true
            )
        }
    }
}
