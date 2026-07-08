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
                }

                sh '''
                    echo "Current workspace:"
                    pwd

                    echo "Git branch:"
                    git branch --show-current || true

                    echo "Git commit:"
                    git rev-parse --short HEAD

                    echo "Docker image tag:"
                    echo "${DOCKER_IMAGE_LOCAL}:${IMAGE_TAG}"

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
                      -t ${DOCKER_IMAGE_LOCAL}:${IMAGE_TAG} \
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
                      ${DOCKER_IMAGE_LOCAL}:${IMAGE_TAG}

                    echo "Running blocking Trivy scan for fixable CRITICAL vulnerabilities..."
                    trivy image \
                      --scanners vuln \
                      --ignore-unfixed \
                      --exit-code 1 \
                      --severity CRITICAL \
                      --no-progress \
                      --format table \
                      ${DOCKER_IMAGE_LOCAL}:${IMAGE_TAG}
                '''
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
  "image": "${DOCKER_IMAGE_LOCAL}:${IMAGE_TAG}",
  "pipeline_type": "ci",
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
            echo 'CI pipeline completed successfully.'
        }

        failure {
            echo 'CI pipeline failed. Check the failed stage and console output.'
        }

        always {
            sh '''
                echo "Final workspace status:"
                ls -la

                echo "Docker images for incident-api:"
                docker image ls incident-api || true
            '''

            archiveArtifacts artifacts: 'reports/ci/*', fingerprint: true, allowEmptyArchive: true
        }
    }
}
