pipeline {
  agent any

  environment {
    // ==== EDIT THESE ====
    PROJECT = 'gke-demo-project-2025'
    CLUSTER = 'demo-gke'
    ZONE    = 'asia-south1-a'             // or your region/zone
    NAMESPACE = 'demo'
    // Jenkins Credentials ID for your uploaded JSON key:
    GCP_SA_CRED_ID = 'gcp-sa'             // <-- the ID you set in Jenkins
    // Force kubectl to use the plugin:
    USE_GKE_GCLOUD_AUTH_PLUGIN = 'True'
  }

  options {
    timestamps()
  }

  stages {

    stage('Tooling check') {
      steps {
        sh '''
          set -euxo pipefail
          gcloud --version
          kubectl version --client=true --output=yaml || true
          which gke-gcloud-auth-plugin || echo "NOTE: plugin not in PATH - gcloud will still find it if installed via apt."
        '''
      }
    }

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('GCP Auth') {
      steps {
        withCredentials([file(credentialsId: "${GCP_SA_CRED_ID}", variable: 'GCLOUD_KEY')]) {
          sh '''
            set -euxo pipefail
            gcloud auth activate-service-account \
              jenkins-deployer@${PROJECT}.iam.gserviceaccount.com \
              --key-file="${GCLOUD_KEY}"

            gcloud config set project ${PROJECT}
          '''
        }
      }
    }

    stage('Get GKE Credentials') {
      steps {
        sh '''
          set -euxo pipefail
          # If your cluster is regional use --region instead of --zone
          gcloud container clusters get-credentials ${CLUSTER} --zone ${ZONE} --project ${PROJECT}
          kubectl get nodes
        '''
      }
    }

    stage('Ensure namespace & base svc') {
      steps {
        sh '''
          set -euxo pipefail
          # Safe upserts
          kubectl apply -f k8s/namespace.yaml
          kubectl -n ${NAMESPACE} apply -f k8s/service.yaml
        '''
      }
    }

    stage('Deploy GREEN (parallel stack)') {
      steps {
        sh '''
          set -euxo pipefail
          kubectl -n ${NAMESPACE} apply -f k8s/deploy-green.yaml
          # Optional HPA for green if you keep HPA resource bound to "web-green":
          if [ -f k8s/hpa.yaml ]; then
            # If your HPA references "web-blue", you can sed-rewrite on the fly for green cutover demo:
            sed 's/web-blue/web-green/g' k8s/hpa.yaml | kubectl -n ${NAMESPACE} apply -f -
          fi

          # Wait until green is fully ready
          kubectl -n ${NAMESPACE} rollout status deploy/web-green --timeout=5m
          kubectl -n ${NAMESPACE} get deploy,pods -l app=web,color=green -o wide
        '''
      }
    }

    stage('Smoke test GREEN') {
      steps {
        sh '''
          set -euxo pipefail

          # Try an internal curl via a throwaway pod (works even before switching service)
          kubectl -n ${NAMESPACE} run curl --image=curlimages/curl:8.10.1 -i --restart=Never --rm -- \
            sh -c "curl -sS http://web-green.${NAMESPACE}.svc.cluster.local/ | head -n 5" || true

          # Or probe one green pod directly:
          POD=$(kubectl -n ${NAMESPACE} get pod -l app=web,color=green -o jsonpath='{.items[0].metadata.name}')
          kubectl -n ${NAMESPACE} exec "$POD" -- wget -qO- localhost:80 | head -n 5 || true
        '''
      }
    }

    stage('Switch Service to GREEN (cutover)') {
      steps {
        sh '''
          set -euxo pipefail
          # Patch the service selector to route to green
          kubectl -n ${NAMESPACE} patch service web \
            -p '{"spec":{"selector":{"app":"web","color":"green"}}}'

          # Show where it's pointing now:
          kubectl -n ${NAMESPACE} get svc web -o jsonpath='{.spec.selector}'; echo
          kubectl -n ${NAMESPACE} get endpoints web
        '''
      }
    }

    stage('Post-cutover verification') {
      steps {
        sh '''
          set -euxo pipefail
          kubectl -n ${NAMESPACE} get deploy,pods -l app=web -o wide

          # If your Service is type LoadBalancer, curl the external IP:
          EXTERNAL_IP=$(kubectl -n ${NAMESPACE} get svc web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
          if [ -n "$EXTERNAL_IP" ]; then
            echo "Hitting http://$EXTERNAL_IP/"
            curl -sS --max-time 5 "http://$EXTERNAL_IP/" | head -n 10 || true
          fi
        '''
      }
    }

    stage('Decommission BLUE (optional clean-up)') {
      when { expression { return true } }  // set to false if you want to keep blue around
      steps {
        sh '''
          set -euxo pipefail
          kubectl -n ${NAMESPACE} rollout status deploy/web-green --timeout=2m
          kubectl -n ${NAMESPACE} delete deploy/web-blue --ignore-not-found=true

          # If you swapped HPA to green, you may delete/restore blue’s HPA similarly
          # kubectl -n ${NAMESPACE} delete hpa web-blue-hpa --ignore-not-found=true
        '''
      }
    }
  }

  post {
    always {
      sh '''
        echo "--- Final state ---"
        kubectl -n ${NAMESPACE} get deploy,svc,pods -o wide || true
        kubectl -n ${NAMESPACE} get hpa || true
      '''
      archiveArtifacts artifacts: 'k8s/**/*.yaml', fingerprint: true, onlyIfSuccessful: false
    }
  }
}

