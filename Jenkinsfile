pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        APP_NAME = 'incident-api'
        PYTHON_VENV = '.venv'
        DOCKER_IMAGE_LOCAL = 'incident-api'
        IMAGE_TAG = "ci-${BUILD_NUMBER}-${GIT_COMMIT.take(7)}"
        CI_REPORT_DIR = 'reports/ci'
    }

    stages {
        stage('Checkout Source') {
            steps {
                checkout scm

                sh '''
                    echo "Current workspace:"
                    pwd

                    echo "Git branch:"
                    git branch --show-current || true

                    echo "Git commit:"
                    git rev-parse --short HEAD

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

                    echo "Running Trivy vulnerability scan..."
                    trivy image \
                      --exit-code 1 \
                      --severity CRITICAL \
                      --no-progress \
                      --format table \
                      ${DOCKER_IMAGE_LOCAL}:${IMAGE_TAG}

                    echo "Generating Trivy JSON report..."
                    trivy image \
                      --exit-code 0 \
                      --severity HIGH,CRITICAL \
                      --no-progress \
                      --format json \
                      --output ${CI_REPORT_DIR}/trivy-image-report.json \
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
  "git_commit": "${GIT_COMMIT}",
  "image": "${DOCKER_IMAGE_LOCAL}:${IMAGE_TAG}",
  "pipeline_type": "ci",
  "result": "success"
}
JSON

                    echo "Build metadata:"
                    cat ${CI_REPORT_DIR}/build-metadata.json | jq
                '''

                archiveArtifacts artifacts: 'reports/ci/*', fingerprint: true
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
        }
    }
}
