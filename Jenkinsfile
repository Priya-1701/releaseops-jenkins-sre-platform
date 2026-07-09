pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 60, unit: 'MINUTES')
        skipDefaultCheckout(true)
    }

    environment {
        APP_NAME = 'incident-api'
        PYTHON_VENV = '.venv'

        DOCKER_IMAGE_LOCAL = 'incident-api'
        DOCKERHUB_REPOSITORY = 'docker.io/priyanka1701/incident-api'

        CI_REPORT_DIR = 'reports/ci'
        CD_REPORT_DIR = 'reports/cd'

        DEV_NAMESPACE = 'incident-dev'
        STAGING_NAMESPACE = 'incident-staging'

        TRIVY_DISABLE_VEX_NOTICE = 'true'
    }

    stages {
        stage('Checkout Source') {
            steps {
                cleanWs()
                checkout scm

                script {
                    env.GIT_SHORT_SHA = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
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

                    rm -rf "${PYTHON_VENV}"

                    python3 -m venv "${PYTHON_VENV}"

                    . "${PYTHON_VENV}/bin/activate"

                    python -m pip install --upgrade pip

                    python -m pip install \
                      -r app/requirements-dev.txt

                    python -m pip freeze
                '''
            }
        }

        stage('Lint Code') {
            steps {
                sh '''
                    set -e

                    . "${PYTHON_VENV}/bin/activate"

                    python -m ruff check app
                '''
            }
        }

        stage('Run Unit Tests') {
            steps {
                sh '''
                    set -e

                    . "${PYTHON_VENV}/bin/activate"

                    mkdir -p "${CI_REPORT_DIR}"

                    python -m pytest \
                      app/tests \
                      --junitxml="${CI_REPORT_DIR}/pytest-results.xml"
                '''
            }

            post {
                always {
                    junit(
                        allowEmptyResults: false,
                        testResults: 'reports/ci/pytest-results.xml'
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
                '''
            }
        }

        stage('Scan Docker Image') {
            steps {
                sh '''
                    set -e

                    mkdir -p "${CI_REPORT_DIR}"

                    trivy image \
                      --exit-code 0 \
                      --severity HIGH,CRITICAL \
                      --no-progress \
                      --format json \
                      --output \
                      "${CI_REPORT_DIR}/trivy-image-report.json" \
                      "${LOCAL_IMAGE}"

                    trivy image \
                      --scanners vuln \
                      --ignore-unfixed \
                      --exit-code 1 \
                      --severity CRITICAL \
                      --no-progress \
                      --format table \
                      "${LOCAL_IMAGE}"
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
                '''
            }
        }

        stage('Push Docker Image to DockerHub') {
            steps {
                retry(3) {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'dockerhub-creds',
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
                          = "yes"

                        echo \
                          "Checking staging deployment access..."

                        STAGING_ACCESS="$(
                          kubectl auth can-i \
                            patch deployments.apps \
                            -n "${STAGING_NAMESPACE}"
                        )"

                        test \
                          "${STAGING_ACCESS}" \
                          = "yes"

                        echo \
                          "Confirming production access is denied..."

                        PROD_ACCESS="$(
                          kubectl auth can-i \
                            patch deployments.apps \
                            -n incident-prod \
                          || true
                        )"

                        test \
                          "${PROD_ACCESS}" \
                          = "no"

                        kubectl \
                          -n "${DEV_NAMESPACE}" \
                          get deployment \
                          "${APP_NAME}"

                        kubectl \
                          -n "${STAGING_NAMESPACE}" \
                          get deployment \
                          "${APP_NAME}"

                        echo \
                          "Kubernetes access validation passed."
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
                          "${CD_REPORT_DIR}"

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

                        cat > \
"${CI_REPORT_DIR}/build-metadata.json" \
<<JSON
{
  "application": "${APP_NAME}",
  "jenkins_build_number": "${BUILD_NUMBER}",
  "git_commit_short": "${GIT_SHORT_SHA}",
  "local_image": "${LOCAL_IMAGE}",
  "registry_image": "${REGISTRY_IMAGE}",
  "latest_image": "${REGISTRY_IMAGE_LATEST}",
  "pipeline_type": "ci-cd",
  "result": "success"
}
JSON

                        cat > \
"${CD_REPORT_DIR}/release-metadata.json" \
<<JSON
{
  "application": "${APP_NAME}",
  "jenkins_build_number": "${BUILD_NUMBER}",
  "git_commit_short": "${GIT_SHORT_SHA}",
  "promoted_image": "${REGISTRY_IMAGE}",
  "dev_namespace": "${DEV_NAMESPACE}",
  "dev_image": "${DEV_IMAGE}",
  "dev_smoke_test": "passed",
  "staging_namespace": "${STAGING_NAMESPACE}",
  "staging_image": "${STAGING_IMAGE}",
  "staging_smoke_test": "passed",
  "production_deployed": false,
  "result": "success"
}
JSON

                        echo \
                          "Release metadata:"

                        jq . \
"${CD_REPORT_DIR}/release-metadata.json"
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
- Docker security scanning
- DockerHub publication
- Dev deployment
- Dev smoke testing
- Staging deployment
- Staging smoke testing
'''
        }

        failure {
            echo '''
ReleaseOps CI/CD pipeline failed.

The pipeline stopped before further promotion.
Review the failed stage and archived evidence.
'''
        }

        always {
            archiveArtifacts(
                artifacts:
                    'reports/ci/*,reports/cd/*',
                fingerprint: true,
                allowEmptyArchive: true
            )
        }
    }
}
