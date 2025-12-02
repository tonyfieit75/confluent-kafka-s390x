#!/bin/bash
# ================================================================
# 🧪 Kafka KRaft Cluster End-to-End Test Script
# Author: Antoine
# ================================================================

NAMESPACE="confluent-platform"
TOPIC="demo-topic"
BROKER="cp-kafka-service.${NAMESPACE}.svc.cluster.local:9092"
PARTITIONS=1
REPLICATION=3
POD="cp-kafka-0"

echo "==============================================="
echo "🚀 Starting Kafka KRaft Cluster Test"
echo "==============================================="

# Step 1. Verify topic list
echo "🔍 Checking existing topics..."
oc exec -n $NAMESPACE $POD -- \
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server $BROKER --list

# Step 2. Create test topic (if not exists)
echo "📦 Creating topic '$TOPIC' (partitions=$PARTITIONS, replication=$REPLICATION)..."
oc exec -n $NAMESPACE $POD -- \
  /opt/kafka/bin/kafka-topics.sh --create \
  --topic $TOPIC \
  --partitions $PARTITIONS \
  --replication-factor $REPLICATION \
  --if-not-exists \
  --bootstrap-server $BROKER

# Step 3. Describe topic
echo "📘 Describing topic '$TOPIC'..."
oc exec -n $NAMESPACE $POD -- \
  /opt/kafka/bin/kafka-topics.sh --describe \
  --topic $TOPIC \
  --bootstrap-server $BROKER

# Step 4. Produce test messages
echo "📝 Producing test messages..."
oc exec -n $NAMESPACE $POD -- bash -c "
  echo -e 'hello kafka\nkraft mode test\nopenShift success!' | \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server $BROKER \
  --topic $TOPIC
"

# Step 5. Consume messages
echo "📬 Consuming test messages..."
oc exec -n $NAMESPACE cp-kafka-1 -- \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server $BROKER \
  --topic $TOPIC \
  --from-beginning \
  --timeout-ms 5000

# Step 6. Verify ISR status
echo "🧩 Checking in-sync replicas (ISR)..."
oc exec -n $NAMESPACE $POD -- \
  /opt/kafka/bin/kafka-topics.sh --describe \
  --topic $TOPIC \
  --bootstrap-server $BROKER | grep -E "Isr|Leader|Replicas"

# Step 7. Result summary
echo "==============================================="
echo "✅ Kafka KRaft Test Completed Successfully"
echo "Topic: $TOPIC"
echo "Broker: $BROKER"
echo "Namespace: $NAMESPACE"
echo "==============================================="

