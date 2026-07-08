pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 30, unit: 'MINUTES')
        skipDefaultCheckout(true)
    }

    environment {
        APP_NAME = 'incident-api'
        PYTHON_VENV = '.venv'
        DOCKER_IMAGE_LOCAL = 'incident-api'
        DOCKERHUB_REPOSITORY = 'docker.io/priyanka1701/incident-api'
        CI_REPORT_DIR = 'reports/ci'
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

                    env.IMAGE_TAG = "ci-${env.BUILD_NUMBER}-${env.GIT_SHORT_SHA}"
                    env.LOCAL_IMAGE = "${env.DOCKER_IMAGE_LOCAL}:${env.IMAGE_TAG}"
                    env.REGISTRY_IMAGE = "${env.DOCKERHUB_REPOSITORY}:${env.IMAGE_TAG}"
                    env.REGISTRY_IMAGE_LATEST = "${env.DOCKERHUB_REPOSITORY}:latest"
                }

                sh '''
                    echo "Current workspace:"
                    pwd

                    echo "Git branch:"
                    git branch --show-current || true

                    echo "Git commit:"
                    git rev-parse --short HEAD

                    echo "Local Docker image:"
                    echo "${LOCAL_IMAGE}"

                    echo "Registry Docker image:"
                    echo "${REGISTRY_IMAGE}"

                    echo "Latest Docker image:"
                    echo "${REGISTRY_IMAGE_LATEST}"

                    echo "Repository files:"
                    ls -la
                '''
            }
        }

        stage('Prepare Python Environment') {
            steps {
                sh '''
                    set -e

                    echo "Python version:"
                    python3 --version

                    echo "Removing any old virtual environment..."
                    rm -rf ${PYTHON_VENV}

                    echo "Creating virtual environment..."
                    python3 -m venv ${PYTHON_VENV}

                    echo "Activating virtual environment and installing dependencies..."
                    . ${PYTHON_VENV}/bin/activate

                    python -m pip install --upgrade pip
                    python -m pip install -r app/requirements-dev.txt

                    echo "Installed Python packages:"
                    python -m pip freeze
                '''
            }
        }

        stage('Lint Code') {
            steps {
                sh '''
                    set -e

                    . ${PYTHON_VENV}/bin/activate

                    echo "Running ruff lint check..."
                    python -m ruff check app
                '''
            }
        }

        stage('Run Unit Tests') {
            steps {
                sh '''
                    set -e

                    . ${PYTHON_VENV}/bin/activate

                    mkdir -p ${CI_REPORT_DIR}

                    echo "Running pytest..."
                    python -m pytest app/tests \
                      --junitxml=${CI_REPORT_DIR}/pytest-results.xml
                '''
            }

            post {
                always {
                    junit allowEmptyResults: false, testResults: 'reports/ci/pytest-results.xml'
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    set -e

                    echo "Building Docker image..."
                    docker build \
                      -f docker/Dockerfile \
                      -t ${LOCAL_IMAGE} \
                      .

                    echo "Docker image built:"
                    docker image ls ${DOCKER_IMAGE_LOCAL}
                '''
            }
        }

        stage('Scan Docker Image') {
            steps {
                sh '''
                    set -e

                    mkdir -p ${CI_REPORT_DIR}

                    echo "Generating full Trivy JSON report for HIGH and CRITICAL findings..."
                    trivy image \
                      --exit-code 0 \
                      --severity HIGH,CRITICAL \
                      --no-progress \
                      --format json \
                      --output ${CI_REPORT_DIR}/trivy-image-report.json \
                      ${LOCAL_IMAGE}

                    echo "Running blocking Trivy scan for fixable CRITICAL vulnerabilities..."
                    trivy image \
                      --scanners vuln \
                      --ignore-unfixed \
                      --exit-code 1 \
                      --severity CRITICAL \
                      --no-progress \
                      --format table \
                      ${LOCAL_IMAGE}
                '''
            }
        }

        stage('Tag DockerHub Images') {
            steps {
                sh '''
                    set -e

                    echo "Tagging local image for DockerHub..."
                    docker tag ${LOCAL_IMAGE} ${REGISTRY_IMAGE}
                    docker tag ${LOCAL_IMAGE} ${REGISTRY_IMAGE_LATEST}

                    echo "DockerHub image tags prepared:"
                    docker image ls ${DOCKERHUB_REPOSITORY}
                '''
            }
        }

        stage('Push Docker Image to DockerHub') {
            steps {
                retry(3) {
                    withCredentials([usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKERHUB_USERNAME',
                        passwordVariable: 'DOCKERHUB_TOKEN'
                    )]) {
                        sh '''
                            set +x
                            set -e

                            export DOCKER_CONFIG="${WORKSPACE}/.docker"

                            rm -rf "${DOCKER_CONFIG}"
                            mkdir -p "${DOCKER_CONFIG}"

                            cleanup_docker_auth() {
                              docker logout docker.io >/dev/null 2>&1 || true
                              rm -rf "${DOCKER_CONFIG}"
                            }

                            trap cleanup_docker_auth EXIT

                            echo "Logging in to DockerHub as ${DOCKERHUB_USERNAME}..."
                            echo "${DOCKERHUB_TOKEN}" | docker login docker.io -u "${DOCKERHUB_USERNAME}" --password-stdin

                            echo "Pushing versioned image: ${REGISTRY_IMAGE}"
                            docker push ${REGISTRY_IMAGE}

                            echo "Pushing latest image: ${REGISTRY_IMAGE_LATEST}"
                            docker push ${REGISTRY_IMAGE_LATEST}

                            echo "DockerHub push completed successfully."
                        '''
                    }
                }
            }
        }

        stage('Archive CI Metadata') {
            steps {
                sh '''
                    set -e

                    mkdir -p ${CI_REPORT_DIR}

                    cat > ${CI_REPORT_DIR}/build-metadata.json <<JSON
{
  "application": "${APP_NAME}",
  "jenkins_build_number": "${BUILD_NUMBER}",
  "git_commit_short": "${GIT_SHORT_SHA}",
  "local_image": "${LOCAL_IMAGE}",
  "registry_image": "${REGISTRY_IMAGE}",
  "latest_image": "${REGISTRY_IMAGE_LATEST}",
  "dockerhub_repository": "${DOCKERHUB_REPOSITORY}",
  "pipeline_type": "ci-registry",
  "result": "success"
}
JSON

                    echo "Build metadata:"
                    cat ${CI_REPORT_DIR}/build-metadata.json | jq
                '''
            }
        }
    }

    post {
        success {
            echo 'CI registry pipeline completed successfully.'
        }

        failure {
            echo 'CI registry pipeline failed. Check the failed stage and console output.'
        }

        always {
            sh '''
                echo "Final workspace status:"
                ls -la

                echo "Docker images for incident-api:"
                docker image ls incident-api || true

                echo "DockerHub tagged images:"
                docker image ls ${DOCKERHUB_REPOSITORY} || true
            '''

            archiveArtifacts artifacts: 'reports/ci/*', fingerprint: true, allowEmptyArchive: true
        }
    }
}
