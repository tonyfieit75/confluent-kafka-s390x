#!/usr/bin/env bash

set -e

NAMESPACE="confluent-platform"

echo "🔥 Uninstalling cp-kafka KRaft from namespace: ${NAMESPACE}"
echo ""

###############################################
# 1. Delete StatefulSet
###############################################
echo "📦 Deleting StatefulSet 'cp-kafka'..."
oc delete statefulset cp-kafka -n ${NAMESPACE} --ignore-not-found

###############################################
# 2. Delete cp-kafka Service
###############################################
echo "📡 Deleting cp-kafka headless service..."
oc delete svc cp-kafka-service -n ${NAMESPACE} --ignore-not-found

###############################################
# 3. Delete Secret
###############################################
echo "🔐 Deleting cp-kafka-cluster-id secret..."
oc delete secret cp-kafka-cluster-id -n ${NAMESPACE} --ignore-not-found

###############################################
# 4. Force-remove PVCs (StatefulSet PVCs)
###############################################
echo "🗂  Listing PVCs..."
PVC_LIST=$(oc get pvc -n ${NAMESPACE} -l app=cp-kafka -o name)

if [[ -n "$PVC_LIST" ]]; then
  echo "🧹 Removing PVC finalizers (if stuck)..."
  for pvc in $PVC_LIST; do
    echo "➡ Fixing $pvc"
    oc patch $pvc -n ${NAMESPACE} -p '{"metadata":{"finalizers":null}}' --type=merge || true
  done

  echo "🗑  Deleting PVCs..."
  oc delete pvc -n ${NAMESPACE} -l app=cp-kafka --ignore-not-found
else
  echo "ℹ No PVCs found for cp-kafka."
fi

###############################################
# 5. Delete PVs bound to cp-kafka PVCs
###############################################
echo "🧭 Cleaning PVs bound to cp-kafka PVCs..."

PV_LIST=$(oc get pv --no-headers | grep "confluent-platform" | grep "datadir-cp-kafka-" | awk '{print $1}')

if [[ -n "$PV_LIST" ]]; then
  for pv in $PV_LIST; do
    echo "➡ Removing finalizers from PV $pv"
    oc patch pv $pv -p '{"metadata":{"finalizers":null}}' --type=merge || true

    echo "🗑  Deleting PV $pv..."
    oc delete pv $pv --ignore-not-found
  done
else
  echo "ℹ No PVs found for cp-kafka."
fi

###############################################
# 6. Delete leftover pods (if any)
###############################################
echo "🧨 Cleaning leftover cp-kafka pods..."
oc delete pod -n ${NAMESPACE} -l app=cp-kafka --force --grace-period=0 --ignore-not-found

###############################################
# 7. Verification
###############################################
echo ""
echo "🔍 Verification:"
oc get all -n ${NAMESPACE} | grep cp-kafka || echo "✔ No cp-kafka resources left."

###############################################
# 8. OPTIONAL: Delete namespace
###############################################
READ_NAMESPACE_DELETE=N

read -p "❓ Delete entire namespace '${NAMESPACE}'? (y/N): " READ_NAMESPACE_DELETE

if [[ "$READ_NAMESPACE_DELETE" == "y" || "$READ_NAMESPACE_DELETE" == "Y" ]]; then
  echo "🗑  Removing namespace ${NAMESPACE}..."
  oc delete ns ${NAMESPACE}
else
  echo "⏭  Namespace preserved."
fi

echo ""
echo "🎉 cp-kafka KRaft uninstall completed successfully."

