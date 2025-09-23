pipeline {
  agent any

  environment {
    PROJECT   = 'gke-demo-project-2025'
    CLUSTER   = 'demo-gke'
    ZONE      = 'asia-south1-a'
    NAMESPACE = 'demo'

    // Jenkins credential ID where you stored the GCP service account JSON
    GCP_SA_CRED_ID = 'gcp-sa'
    USE_GKE_GCLOUD_AUTH_PLUGIN = 'True'
  }

  options {
    ansiColor('xterm')
    buildDiscarder(logRotator(numToKeepStr: '20'))
    disableConcurrentBuilds()
    timestamps()
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Authenticate to GKE') {
      steps {
        withCredentials([file(credentialsId: "${GCP_SA_CRED_ID}", variable: 'GOOGLE_APPLICATION_CREDENTIALS')]) {
          sh """bash -lc '
            set -euxo pipefail

            gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
            gcloud config set project "$PROJECT"
            gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT"

            echo "Active account:"
            gcloud auth list --filter=status:ACTIVE --format="value(account)"

            echo "K8s context:"
            kubectl config current-context

            echo "RBAC check:"
            kubectl auth can-i get pods --all-namespaces
          '"""
        }
      }
    }

    stage('Blue/Green Deploy') {
      steps {
        sh """bash -lc '
          set -euxo pipefail

          # Example: apply manifests from repo
          kubectl -n "$NAMESPACE" apply -f k8s/
        '"""
      }
    }

    stage('Smoke Test') {
      steps {
        sh """bash -lc '
          set -euxo pipefail
          kubectl -n "$NAMESPACE" get deploy,svc,pods -o wide
        '"""
      }
    }
  }

  post {
    always {
      sh """bash -lc '
        set -e
        echo "--- Final state ---"
        kubectl -n "$NAMESPACE" get deploy,svc,pods -o wide || true
        kubectl -n "$NAMESPACE" get hpa || true
      '"""
      archiveArtifacts artifacts: 'k8s/**/*.yaml', fingerprint: true, onlyIfSuccessful: false
    }
  }
}
