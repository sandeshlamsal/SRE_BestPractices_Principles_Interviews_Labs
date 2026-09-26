#!/usr/bin/env bash
# Restore the shop's Postgres from the newest (or given) pg_dump in the backups PVC.
#   scripts/db-restore.sh                 # newest backup
#   scripts/db-restore.sh <file.dump>     # a specific backup
# Prints the backup used, how old it is (-> actual RPO) and the restored order count.
set -euo pipefail
FILE="${1:-}"
cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata: { name: pg-restore, namespace: backups }
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: pg-restore
          image: postgres:18.4
          envFrom: [{ secretRef: { name: pg-backup } }]
          command: ["sh","-c"]
          args:
            - |
              set -e
              f="${FILE:+/backups/$FILE}"; f="\${f:-\$(ls -1t /backups/*.dump | head -1)}"
              echo "restoring: \$f (taken \$(stat -c %y "\$f" | cut -d. -f1) UTC)"
              until pg_isready -h astronomy-db.astronomy-shop -U postgres; do sleep 2; done
              pg_restore -h astronomy-db.astronomy-shop -U postgres -d astronomy_db --clean --if-exists --no-owner "\$f" || true
              echo "restored orders=\$(psql -h astronomy-db.astronomy-shop -U postgres -d astronomy_db -tAc 'select count(*) from accounting.order')"
          volumeMounts: [{ name: backups, mountPath: /backups }]
      volumes:
        - name: backups
          persistentVolumeClaim: { claimName: pg-backups }
YAML
kubectl -n backups wait --for=condition=complete job/pg-restore --timeout=300s >/dev/null || { kubectl -n backups logs job/pg-restore; exit 1; }
kubectl -n backups logs job/pg-restore | grep -vE "^(astronomy-db|pg_restore: warning)"
kubectl -n backups delete job pg-restore >/dev/null
