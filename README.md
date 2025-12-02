# Confluent Kafka KRaft on OpenShift (s390x)

This repository contains a lightweight, fully–portable deployment of **Kafka KRaft mode** on Red Hat OpenShift (s390x).  
It includes everything required to install, test, and uninstall a 3‑node Kafka KRaft cluster without ZooKeeper.

---

## 📌 Repository Structure

```
confluent-kafka/
├── install-kafka-kraft.sh        # Automated installer (recommended)
├── uninstall-kafka-kraft.sh      # Automated uninstaller (clean removal)
├── kafka-kraft-ocp.yaml          # Single-file OCP deployment manifest
├── kafka-headless.yaml           # Headless service for StatefulSet DNS
├── kafka-service.yaml            # NodePort/ClusterIP access service
├── test_kafka_cluster.sh         # Smoke test (produce & consume)
└── README.md                     # This file
```

---

# 🚀 Overview

This Kafka deployment is designed for:
- IBM LinuxONE / s390x
- OpenShift 4.x
- KRaft mode (no ZooKeeper)
- Simple, reproducible cluster creation
- Fully self-contained images and manifests

The deployment sets up:
- **3‑node Kafka KRaft cluster**
- **Headless service + StatefulSet**
- **Automatic cluster UUID generation**
- **Persistent storage (PVCs)**

You can install Kafka using **two deployment options**.

---

# ✅ Option 1 — Deploy Using a Single Manifest (Simple & Declarative)

Apply the combined manifest:

```bash
oc apply -f kafka-kraft-ocp.yaml
```

This will automatically:
- Create the headless service  
- Create the StatefulSet  
- Deploy 1–3 cp-Kafka pods  
- Create all volumes  
- Start Kafka cluster in KRaft mode  

To scale:

```bash
oc scale sts cp-kafka --replicas=3
```

To verify:

```bash
./test_kafka_cluster.sh
```

---

# 🔧 Option 2 — Deploy Using the Installer Script (Automated)

Run:

```bash
chmod +x install-kafka-kraft.sh
./install-kafka-kraft.sh
```

This script will:
- Create the namespace (if missing)
- Generate a Kafka cluster ID
- Create the secret `kafka-cluster-id`
- Apply the headless service
- Apply the StatefulSet
- Wait for all pods to become Ready
- Run a smoke test

This is the easiest option if you want:
✔ repeatable deployments  
✔ automatic checks  
✔ no manual steps  

---

# 🧪 Test the Cluster

Use the test script:

```bash
./test_kafka_cluster.sh
```

It performs:
- Topic creation
- Message production
- Message consumption
- KRaft metadata test

Expected output: **SUCCESS**.

---

# 🧹 Uninstall (Full Cleanup)

Run:

```bash
chmod +x uninstall-kafka-kraft.sh
./uninstall-kafka-kraft.sh
```

The script removes:
- StatefulSet  
- Services  
- Pods  
- PVCs + PV finalizers  
- kafka-cluster-id secret  

You may optionally delete the entire namespace.

---

# 📞 Support

For IBM LinuxONE / s390x enablement or custom builds, contact your platform support team or maintainer of this repo.

---

# 🙌 Credits

This deployment was optimized and validated on:
- Red Hat OpenShift on IBM LinuxONE
- Custom Kafka image: `quay.io/tonyfieit75/kafka-kraft:s390x-4.1.0-fixed`

