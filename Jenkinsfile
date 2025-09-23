// Jenkinsfile — GKE Blue/Green Deployment 
pipeline {
  agent any

  environment {
    PROJECT   = 'gke-demo-project-2025'
    CLUSTER   = 'demo-gke'
    ZONE      = 'asia-south1-a'
    NAMESPACE = 'demo'
    USE_GKE_GCLOUD_AUTH_PLUGIN = 'True'

    GAR_REGION = 'asia-south1'
    GAR_REPO   = 'demo-repo'
    IMAGE_NAME = 'web'
    IMAGE_URI  = "${GAR_REGION}-docker.pkg.dev/${PROJECT}/${GAR_REPO}/${IMAGE_NAME}"

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
          env.IMAGE_TAG = sh(returnStdout: true, script: "git rev-parse --short=12 HEAD || date +%Y%m%d%H%M%S").trim()
          echo "IMAGE_TAG=${env.IMAGE_TAG}"
        }
      }
    }

    stage('GCP Auth + Kube Context') {
      steps {
        withCredentials([file(credentialsId: "${GCP_SA_CRED_ID}", variable: 'GOOGLE_APPLICATION_CREDENTIALS')]) {
          sh '''#!/bin/bash -l
            set -euxo pipefail
            gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
            gcloud config set project "$PROJECT"
            gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT"
            kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"
            gcloud auth configure-docker "$GAR_REGION-docker.pkg.dev" --quiet
          '''
        }
      }
    }

    stage('Build & Push Image') {
      steps {
        sh '''#!/bin/bash -l
          set -euxo pipefail
          docker build -t "$IMAGE_URI:$IMAGE_TAG" ./app
          docker push "$IMAGE_URI:$IMAGE_TAG"
        '''
      }
    }

    stage('Decide Target Color') {
      steps {
        script {
          def currentColor = sh(
            returnStdout: true,
            script: '''
              kubectl -n "$NAMESPACE" get svc web -o jsonpath="{.spec.selector.color}" 2>/dev/null || echo ""
            '''
          ).trim()
          if (!currentColor) { currentColor = "blue" } // safe default
          env.CURRENT_COLOR = currentColor
          env.TARGET_COLOR  = (currentColor == "green") ? "blue" : "green"
          echo "CURRENT_COLOR=${env.CURRENT_COLOR}, TARGET_COLOR=${env.TARGET_COLOR}"
        }
      }
    }

    stage('Apply Target Deployment') {
      steps {
        sh '''#!/bin/bash -l
          set -euxo pipefail
          kubectl -n "$NAMESPACE" apply -f "k8s/deploy-$TARGET_COLOR.yaml"
          kubectl -n "$NAMESPACE" set image deploy/web-$TARGET_COLOR nginx="$IMAGE_URI:$IMAGE_TAG" --record
          kubectl -n "$NAMESPACE" rollout status deploy/web-$TARGET_COLOR --timeout=180s
        '''
      }
    }

    stage('Smoke Test Target (pod-local)') {
      steps {
        sh '''#!/bin/bash -l
          set -euxo pipefail
          POD=$(kubectl -n "$NAMESPACE" get pod -l app=web,color="$TARGET_COLOR" -o jsonpath='{.items[0].metadata.name}')
          echo "Testing pod: $POD (color=$TARGET_COLOR)"
          kubectl -n "$NAMESPACE" exec "$POD" -- sh -lc '
            (command -v apk >/dev/null && apk add --no-cache curl >/dev/null 2>&1) || true
            curl -fsS --max-time 5 http://127.0.0.1:80/ | head -n 10
          '
          echo "Target pod smoke test OK"
        '''
      }
    }

    stage('Ensure Service Exists') {
      steps {
        sh '''#!/bin/bash -l
          set -euxo pipefail
          kubectl -n "$NAMESPACE" get svc web >/dev/null 2>&1 || kubectl -n "$NAMESPACE" apply -f k8s/service.yaml
        '''
      }
    }

    stage('Switch Traffic -> TARGET') {
      steps {
        sh '''#!/bin/bash -l
          set -euxo pipefail
          kubectl -n "$NAMESPACE" patch service web -p '{"spec":{"selector":{"app":"web","color":"'"$TARGET_COLOR"'"}}}'
          echo "Switched Service selector to color=$TARGET_COLOR"
        '''
      }
    }

    stage('Post-Switch Verification') {
      steps {
        sh '''#!/bin/bash -l
          set -euxo pipefail
          sleep 5
          echo "Service selector:"
          kubectl -n "$NAMESPACE" get svc web -o jsonpath='{.spec.selector}' ; echo
          echo "Service endpoints:"
          kubectl -n "$NAMESPACE" get endpoints web -o jsonpath='{.subsets[*].addresses[*].ip}' ; echo

          TARGET_IPS=$(kubectl -n "$NAMESPACE" get pod -l app=web,color="$TARGET_COLOR" -o jsonpath='{.items[*].status.podIP}')
          EP_IPS=$(kubectl -n "$NAMESPACE" get endpoints web -o jsonpath='{.subsets[*].addresses[*].ip}')
          echo "TARGET_IPS: $TARGET_IPS"
          echo "EP_IPS: $EP_IPS"

          for ip in $EP_IPS; do
            echo "$TARGET_IPS" | grep -qw "$ip"
          done

          EXT_IP=$(kubectl -n "$NAMESPACE" get svc web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
          if [ -n "$EXT_IP" ]; then
            echo "External IP: $EXT_IP — curling /"
            curl -fsS --max-time 8 "http://$EXT_IP/" | head -n 20 || true
          fi
          echo "Post-switch verification passed."
        '''
      }
    }
  }

  post {
    success {
      script {
        if (env.CURRENT_COLOR && env.CURRENT_COLOR != "none") {
          sh '''#!/bin/bash -l
            set -euxo pipefail
            kubectl -n "$NAMESPACE" scale deploy/web-$CURRENT_COLOR --replicas=0 || true
            echo "Scaled down web-$CURRENT_COLOR"
          '''
        }
      }
    }
    failure {
      script {
        if (env.CURRENT_COLOR && env.CURRENT_COLOR != "none") {
          sh '''#!/bin/bash -l
            set -euxo pipefail
            echo "Pipeline failed — rolling Service back to $CURRENT_COLOR"
            kubectl -n "$NAMESPACE" patch service web -p '{"spec":{"selector":{"app":"web","color":"'"$CURRENT_COLOR"'"}}}' || true
          '''
        }
      }
    }
    always {
      sh '''#!/bin/bash -l
        echo "--- Final state ---"
        kubectl -n "$NAMESPACE" get deploy,svc,pods -o wide || true
        kubectl -n "$NAMESPACE" get hpa || true
      '''
    }
  }
}
