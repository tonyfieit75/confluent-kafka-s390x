#!/usr/bin/env bash

set -e

NAMESPACE="confluent-platform"
IMAGE="quay.io/tonyfieit75/kafka-kraft:s390x-4.1.0-fixed"

echo "🔥 Installing cp-kafka KRaft into namespace: ${NAMESPACE}"
echo ""

###############################################
# 1. Ensure namespace exists
###############################################
echo "📁 Checking namespace..."
oc get ns ${NAMESPACE} >/dev/null 2>&1 || oc create ns ${NAMESPACE}
echo "✅ Namespace ready."
echo ""

###############################################
# 2. Apply Kafka headless service
###############################################
echo "📡 Creating cp-kafka headless service..."

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: cp-kafka-service
  namespace: ${NAMESPACE}
  labels:
    app: cp-kafka
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector:
    app: cp-kafka
  ports:
    - name: broker
      port: 9092
      targetPort: 9092
    - name: controller
      port: 9093
      targetPort: 9093
EOF

echo "✅ Headless service applied."
echo ""

###############################################
# 3. Generate Cluster ID and create secret
###############################################
echo "🔑 Generating Kafka Cluster ID..."
CLUSTER_ID=$(uuidgen | tr -d '-')
echo "ClusterID: $CLUSTER_ID"

echo "🔐 Creating secret cp-kafka-cluster-id..."
oc delete secret cp-kafka-cluster-id -n ${NAMESPACE} >/dev/null 2>&1 || true

oc create secret generic cp-kafka-cluster-id \
  -n ${NAMESPACE} \
  --from-literal=clusterId="$CLUSTER_ID"

echo "✅ Secret created."
echo ""

###############################################
# 3b. Create ServiceAccount + RBAC
###############################################
echo "🔐 Creating ServiceAccount and RBAC..."

cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cp-kafka
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cp-kafka-role
  namespace: ${NAMESPACE}
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "endpoints", "services"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: ["apps"]
    resources: ["statefulsets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cp-kafka-rolebinding
  namespace: ${NAMESPACE}
subjects:
  - kind: ServiceAccount
    name: cp-kafka
    namespace: ${NAMESPACE}
roleRef:
  kind: Role
  name: cp-kafka-role
  apiGroup: rbac.authorization.k8s.io
EOF

echo "✅ ServiceAccount + RBAC ready."
echo ""

###############################################
# 4. Deploy cp-kafka StatefulSet
###############################################
echo "📦 Deploying cp-kafka StatefulSet..."

cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: cp-kafka
  namespace: ${NAMESPACE}
spec:
  serviceName: cp-kafka-service
  replicas: 3
  selector:
    matchLabels:
      app: cp-kafka
  podManagementPolicy: Parallel
  updateStrategy:
    type: RollingUpdate

  template:
    metadata:
      labels:
        app: cp-kafka

    spec:
      serviceAccountName: cp-kafka
      terminationGracePeriodSeconds: 300

      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault

      initContainers:
        - name: fix-permissions
          image: ${IMAGE}
          command:
            - /bin/bash
            - -c
            - |
              echo "📂 Preparing /var/lib/kafka/data directory..."
              mkdir -p /var/lib/kafka/data
              chmod -R g+rwX /var/lib/kafka/data || true
              echo "UID: \$(id -u)  GID: \$(id -g)"
              echo "✅ Data directory ready."
          securityContext:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: datadir
              mountPath: /var/lib/kafka

        - name: network-check
          image: registry.access.redhat.com/ubi8/ubi:8.9
          command:
            - /bin/bash
            - -c
            - |
              echo "🌐 Checking connectivity..."
              peers="cp-kafka-0.cp-kafka-service.${NAMESPACE}.svc.cluster.local cp-kafka-1.cp-kafka-service.${NAMESPACE}.svc.cluster.local cp-kafka-2.cp-kafka-service.${NAMESPACE}.svc.cluster.local"
              for host in \$peers; do
                for port in 9092 9093; do
                  echo "Testing \$host:\$port"
                  for i in {1..10}; do
                    if timeout 2 bash -c "echo > /dev/tcp/\$host/\$port" 2>/dev/null; then
                      echo "✅ \$host:\$port reachable"
                      break
                    else
                      echo "⏳ waiting for \$host:\$port..."
                      sleep 2
                    fi
                  done
                done
              done
              echo "✅ Network check completed."
          securityContext:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            capabilities:
              drop: ["ALL"]

      containers:
        - name: cp-kafka
          image: ${IMAGE}
          imagePullPolicy: IfNotPresent

          securityContext:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            capabilities:
              drop: ["ALL"]

          ports:
            - containerPort: 9092
              name: broker
            - containerPort: 9093
              name: controller

          command:
            - /bin/bash
            - -lc
            - |
              ORDINAL="\${POD_NAME##*-}"
              export KAFKA_NODE_ID="\${ORDINAL}"
              echo "🧩 Starting cp-kafka node \${KAFKA_NODE_ID}..."
              exec /usr/local/bin/run-kafka.sh

          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name

            - name: KAFKA_LISTENERS
              value: "PLAINTEXT://:9092,CONTROLLER://:9093"

            - name: KAFKA_CONTROLLER_LISTENER_NAMES
              value: "CONTROLLER"

            - name: KAFKA_INTER_BROKER_LISTENER_NAME
              value: "PLAINTEXT"

            - name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
              value: "PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT"

            - name: KAFKA_CONTROLLER_QUORUM_LISTENERS
              value: "CONTROLLER://:9093"

            - name: KAFKA_ADVERTISED_LISTENERS
              value: "PLAINTEXT://\$(POD_NAME).cp-kafka-service.${NAMESPACE}.svc.cluster.local:9092"

            - name: KAFKA_CONTROLLER_QUORUM_VOTERS
              value: "0@cp-kafka-0.cp-kafka-service.${NAMESPACE}.svc.cluster.local:9093,1@cp-kafka-1.cp-kafka-service.${NAMESPACE}.svc.cluster.local:9093,2@cp-kafka-2.cp-kafka-service.${NAMESPACE}.svc.cluster.local:9093"

            - name: KAFKA_CLUSTER_ID
              valueFrom:
                secretKeyRef:
                  name: cp-kafka-cluster-id
                  key: clusterId

            - name: KAFKA_LOG_DIRS
              value: "/var/lib/kafka/data"

          volumeMounts:
            - name: datadir
              mountPath: /var/lib/kafka

      volumes: []
      
  volumeClaimTemplates:
    - metadata:
        name: datadir
        labels:
          app: cp-kafka
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: managed-nfs-storage
        resources:
          requests:
            storage: 5Gi
EOF

echo "✅ StatefulSet applied."
echo ""

###############################################
# 5. Wait for pods to start
###############################################
echo "⏳ Waiting for cp-kafka pods..."

sleep 5
oc get pods -n ${NAMESPACE}

echo ""
echo "🎉 Installation complete!"
echo "Run: oc logs -n ${NAMESPACE} cp-kafka-0 -f"

