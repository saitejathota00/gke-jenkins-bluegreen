pipeline {
  agent any

  environment {
    // ====== GCP / GKE ======
    PROJECT   = 'gke-demo-project-2025'
    CLUSTER   = 'demo-gke'
    ZONE      = 'asia-south1-a'
    NAMESPACE = 'demo'
    USE_GKE_GCLOUD_AUTH_PLUGIN = 'True'

    // ====== Artifact Registry ======
    GAR_REGION   = 'asia-south1'                          // change if needed
    GAR_REPO     = 'demo-repo'                            // existing AR repo
    IMAGE_NAME   = 'web'                                  // app image name
    IMAGE_URI    = "${GAR_REGION}-docker.pkg.dev/${PROJECT}/${GAR_REPO}/${IMAGE_NAME}"

    // Jenkins credentials (Secret file holding SA JSON)
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
          sh """bash -lc '
            set -euxo pipefail
            gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
            gcloud config set project "$PROJECT"
            gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT"
            kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}"
            gcloud auth configure-docker ${GAR_REGION}-docker.pkg.dev --quiet
          '"""
        }
      }
    }

    stage('Build & Push Image') {
      steps {
        sh """bash -lc '
          set -euxo pipefail
          docker build -t "${IMAGE_URI}:${IMAGE_TAG}" .
          docker push "${IMAGE_URI}:${IMAGE_TAG}"
        '"""
      }
    }

    stage('Decide Target Color') {
      steps {
        script {
          def currentColor = sh(
            returnStdout: true,
            script: """
              bash -lc 'set -e
              kubectl -n "${NAMESPACE}" get svc web -o jsonpath="{.spec.selector.color}" 2>/dev/null || echo "none"
              '
            """
          ).trim()

          env.CURRENT_COLOR = currentColor
          env.TARGET_COLOR  = (currentColor == "green") ? "blue" : "green"
          echo "CURRENT_COLOR=${env.CURRENT_COLOR}, TARGET_COLOR=${env.TARGET_COLOR}"
        }
      }
    }

    stage('Render & Apply Target Deployment') {
      steps {
        sh """bash -lc '
          set -euxo pipefail
          # Render the deployment from template with the right color, image & tag
          export COLOR="${TARGET_COLOR}"
          export IMAGE="${IMAGE_URI}"
          export TAG="${IMAGE_TAG}"
          envsubst < k8s/deployment-\$COLOR.tmpl.yaml > k8s/deployment-\$COLOR.yaml

          # Apply (create or update) the target color deployment
          kubectl -n "${NAMESPACE}" apply -f "k8s/deployment-\$COLOR.yaml"

          # Wait for rollout
          kubectl -n "${NAMESPACE}" rollout status deploy/web-\$COLOR --timeout=180s
        '"""
      }
    }

    stage('Smoke Test Target (no traffic switch yet)') {
      steps {
        sh """bash -lc '
          set -euxo pipefail
          COLOR="${TARGET_COLOR}"

          # Create / update a temporary ClusterIP service pointing to target color
          cat <<EOF | kubectl -n "${NAMESPACE}" apply -f -
          apiVersion: v1
          kind: Service
          metadata:
            name: web-smoke
          spec:
            selector:
              app: web
              color: ${TARGET_COLOR}
            ports:
            - port: 80
              targetPort: 80
              protocol: TCP
          EOF

          # Use an ephemeral curl pod inside cluster to hit the web-smoke service
          kubectl -n "${NAMESPACE}" run curl-smoke --rm -i --restart=Never \
            --image=curlimages/curl:8.10.1 --command -- \
            sh -lc "curl -fsS --max-time 5 http://web-smoke/ | head -n 5"

        '"""
      }
    }

    stage('Switch Traffic to Target Color') {
      steps {
        sh """bash -lc '
          set -euxo pipefail
          COLOR="${TARGET_COLOR}"

          # Create the main LB service if it does not exist yet (defaults to blue)
          kubectl -n "${NAMESPACE}" get svc web >/dev/null 2>&1 || cat <<EOF | kubectl -n "${NAMESPACE}" apply -f -
          apiVersion: v1
          kind: Service
          metadata:
            name: web
          spec:
            type: LoadBalancer
            selector:
              app: web
              color: blue
            ports:
            - port: 80
              targetPort: 80
              protocol: TCP
          EOF

          # Switch selector to the new color atomically
          kubectl -n "${NAMESPACE}" patch service web \
            -p "{\"spec\":{\"selector\":{\"app\":\"web\",\"color\":\"${TARGET_COLOR}\"}}}"

          echo "Switched Service to color=${TARGET_COLOR}"
          kubectl -n "${NAMESPACE}" get svc web -o wide
        '"""
      }
    }

    stage('Post-Switch Verification') {
      steps {
        sh """bash -lc '
          set -euxo pipefail
          kubectl -n "${NAMESPACE}" get deploy,svc,pods -o wide
        '"""
      }
    }
  }

  post {
    success {
      // optional: scale down the old color after success
      script {
        if (env.CURRENT_COLOR && env.CURRENT_COLOR != "none") {
          sh """bash -lc '
            set -euxo pipefail
            kubectl -n "${NAMESPACE}" scale deploy/web-${CURRENT_COLOR} --replicas=0 || true
          '"""
        }
      }
    }
    failure {
      // rollback the Service to previous color if we had one
      script {
        if (env.CURRENT_COLOR && env.CURRENT_COLOR != "none") {
          sh """bash -lc '
            set -euxo pipefail
            kubectl -n "${NAMESPACE}" patch service web \
              -p "{\"spec\":{\"selector\":{\"app\":\"web\",\"color\":\"${CURRENT_COLOR}\"}}}" || true
          '"""
        }
      }
    }
    always {
      sh """bash -lc '
        set -e
        echo "--- Final state ---"
        kubectl -n "${NAMESPACE}" get deploy,svc,pods -o wide || true
        kubectl -n "${NAMESPACE}" get hpa || true
      '"""
      archiveArtifacts artifacts: 'k8s/**/*.yaml', fingerprint: true, onlyIfSuccessful: false
    }
  }
}
