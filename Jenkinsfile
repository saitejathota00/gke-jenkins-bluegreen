pipeline {
  agent any

  environment {
    PROJECT   = 'gke-demo-project-2025'
    CLUSTER   = 'demo-gke'
    ZONE      = 'asia-south1-a'
    NAMESPACE = 'demo'
    USE_GKE_GCLOUD_AUTH_PLUGIN = 'True'

    GAR_REGION   = 'asia-south1'
    GAR_REPO     = 'demo-repo'
    IMAGE_NAME   = 'web'
    IMAGE_URI    = "${GAR_REGION}-docker.pkg.dev/${PROJECT}/${GAR_REPO}/${IMAGE_NAME}"

    GCP_SA_CRED_ID = 'gcp-sa'
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '20'))
    disableConcurrentBuilds()
    timestamps()
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Set Build Vars') {
      steps {
        script {
          env.IMAGE_TAG = sh(returnStdout: true, script: "git rev-parse --short=12 HEAD").trim()
          echo "IMAGE_TAG=${env.IMAGE_TAG}"
        }
      }
    }

    stage('GCP Auth + Kube Context') {
      steps {
        withCredentials([file(credentialsId: "${GCP_SA_CRED_ID}", variable: 'GOOGLE_APPLICATION_CREDENTIALS')]) {
          sh """#!/bin/bash -l
            set -euxo pipefail
            gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
            gcloud config set project "$PROJECT"
            gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT"
            kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}"
            gcloud auth configure-docker ${GAR_REGION}-docker.pkg.dev --quiet
          """
        }
      }
    }

    stage('Build & Push Image') {
      steps {
        sh """#!/bin/bash -l
          set -euxo pipefail
          docker build -t "${IMAGE_URI}:${IMAGE_TAG}" ./app
          docker push "${IMAGE_URI}:${IMAGE_TAG}"
        """
      }
    }

    stage('Decide Target Color') {
      steps {
        script {
          def currentColor = sh(
            returnStdout: true,
            script: """
              kubectl -n "${NAMESPACE}" get svc web -o jsonpath="{.spec.selector.color}" 2>/dev/null || echo "none"
            """
          ).trim()
          env.CURRENT_COLOR = currentColor
          env.TARGET_COLOR  = (currentColor == "green") ? "blue" : "green"
          echo "CURRENT_COLOR=${env.CURRENT_COLOR}, TARGET_COLOR=${env.TARGET_COLOR}"
        }
      }
    }

    stage('Apply Target Deployment') {
      steps {
        sh """#!/bin/bash -l
          set -euxo pipefail
          # Apply static YAML for the target color
          kubectl -n "${NAMESPACE}" apply -f k8s/deploy-${TARGET_COLOR}.yaml
          # Update the image dynamically
          kubectl -n "${NAMESPACE}" set image deploy/web-${TARGET_COLOR} nginx=${IMAGE_URI}:${IMAGE_TAG} --record
          # Wait for rollout
          kubectl -n "${NAMESPACE}" rollout status deploy/web-${TARGET_COLOR} --timeout=180s
        """
      }
    }

    stage('Smoke Test Target') {
      steps {
        sh """#!/bin/bash -l
          set -euxo pipefail
          COLOR="${TARGET_COLOR}"
          kubectl -n "${NAMESPACE}" run curl-smoke --rm -i --restart=Never \
            --image=curlimages/curl:8.10.1 --command -- \
            sh -lc "curl -fsS --max-time 5 http://web/ | head -n 5"
        """
      }
    }

    stage('Switch Traffic') {
      steps {
        sh """#!/bin/bash -l
          set -euxo pipefail
          COLOR="${TARGET_COLOR}"

          # Create LB service if it doesn’t exist (defaults to blue)
          kubectl -n "${NAMESPACE}" get svc web >/dev/null 2>&1 || kubectl -n "${NAMESPACE}" apply -f k8s/service.yaml

          # Switch selector atomically
          kubectl -n "${NAMESPACE}" patch service web \
            -p '{"spec":{"selector":{"app":"web","color":"'"${COLOR}"'"}}}'
          echo "Switched traffic to ${COLOR}"
        """
      }
    }

    stage('Post-Switch Verification') {
      steps {
        sh """#!/bin/bash -l
          kubectl -n "${NAMESPACE}" get deploy,svc,pods -o wide
        """
      }
    }
  }

  post {
    success {
      script {
        if (env.CURRENT_COLOR && env.CURRENT_COLOR != "none") {
          sh """#!/bin/bash -l
            kubectl -n "${NAMESPACE}" scale deploy/web-${CURRENT_COLOR} --replicas=0 || true
          """
        }
      }
    }
    failure {
      script {
        if (env.CURRENT_COLOR && env.CURRENT_COLOR != "none") {
          sh """#!/bin/bash -l
            kubectl -n "${NAMESPACE}" patch service web \
              -p '{"spec":{"selector":{"app":"web","color":"${CURRENT_COLOR}"}}}' || true
          """
        }
      }
    }
    always {
      sh """#!/bin/bash -l
        echo "--- Final state ---"
        kubectl -n "${NAMESPACE}" get deploy,svc,pods -o wide || true
        kubectl -n "${NAMESPACE}" get hpa || true
      """
    }
  }
}
