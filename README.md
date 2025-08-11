# 1. Установка StackGres Operator.

[Официальная документация.](https://stackgres.io/doc/latest/install/helm/)

```bash
helm repo add stackgres-charts https://stackgres.io/downloads/stackgres-k8s/stackgres/helm/
helm install --create-namespace --namespace stackgres stackgres-operator stackgres-charts/stackgres-operator --version <version>
```
Версии можно посмотреть [здесь](https://stackgres.io/doc/latest/intro/versions/), в официальной документации.
Или здесь, в [CHANGELOG.md](https://github.com/ongres/stackgres/blob/main/CHANGELOG.md) их репозитория в GitHub.

Если необходима установка с полным стеком мониторинга, подробнее тут – [Установка с мониторингом](https://stackgres.io/doc/latest/install/helm/#installation-with-monitoring).

Команда, чтобы дождаться готовности оператора StackGres к использованию:
```bash
kubectl wait -n stackgres deployment -l group=stackgres.io --for=condition=Available
```

## 1.1 Подключение к кластеру StackGres [тут](https://stackgres.io/doc/latest/administration/cluster/connection/).

# 2. Создание кластера

[Официальная документация.](https://stackgres.io/doc/latest/administration/cluster-creation/)

## 2.1 Ресурсы:

[SGInstanceProfile](https://stackgres.io/doc/latest/reference/crd/sginstanceprofile/) - определяет ресурсы процессора (CPU) и оперативной памяти (memory), выделенные для каждого пода в кластере PostgreSQL.

Пример:
```yaml
apiVersion: stackgres.io/v1
kind: SGInstanceProfile
metadata:
  namespace: demo
  name: size-small
spec:
  cpu: "4"
  memory: "8Gi"
```

[SGPostgresConfig](https://stackgres.io/doc/latest/reference/crd/sgpostgresconfig/) - представляет собой конфигурацию PostgreSQL. Он используется для настройки параметров PostgreSQL, таких как postgresVersion, shared_buffers или password_encryption.
Именно тут очень важно установить *shared_preload_libraries: timescaledb*, чтобы в дальнейшем можно установить TimescaleDB extension.

Пример:
```yaml
apiVersion: stackgres.io/v1
kind: SGPostgresConfig
metadata:
  name: postgresconf
spec:
  postgresVersion: '14'
  postgresql.conf:
    shared_preload_libraries: timescaledb,pg_stat_statements
    password_encryption: 'scram-sha-256'
    random_page_cost: '1.5'
    shared_buffers: '256MB'
    wal_compression: 'on'
```

[SGPoolingConfig](https://stackgres.io/doc/latest/administration/configuration/pool/) - обеспечивает масштабируемость соединений.

Пример:
```yaml
apiVersion: stackgres.io/v1
kind: SGPoolingConfig
metadata:
  name: pgbouncerconf
spec:
  pgBouncer:
    pgbouncer.ini:
      pgbouncer:
        max_client_conn: '2000'
        default_pool_size: '50'
      databases:
        foodb:
          max_db_connections: 1000
          pool_size: 20
          dbname: 'bardb'
          reserve_pool: 5
      users:
        user1:
          pool_mode: transaction
          max_user_connections: 50
        user2:
          pool_mode: session
          max_user_connections: '100'
```

[SGObjectStorage](https://stackgres.io/doc/latest/reference/crd/sgobjectstorage/) - позволяет настроить место, где будут храниться резервные копии.
Самое главное в этой части - обеспечить доступ к бакету в клауде (сервис аккаунты, роли).

Пример с AWS S3:
```yaml
apiVersion: stackgres.io/v1beta1
kind: SGObjectStorage
metadata:
  name: objectstorage
spec:
  type: s3Compatible
  s3Compatible:
    bucket: stackgres
    region: k8s
    enablePathStyleAddressing: true
    endpoint: http://my-cluster-minio:9000
    awsCredentials:
      secretKeySelectors:
        accessKeyId:
          key: accesskey
          name: my-cluster-minio
        secretAccessKey:
          key: secretkey
          name: my-cluster-minio
```

[SGScript](https://stackgres.io/doc/latest/administration/cluster-creation/#configuring-scripts) - используется при необходимости запуска скрипта сразу же после развертывания кластера.

***Все вышеперечисленное (как и некоторые другие CRDs) необходимо применять до создания SGCluster!***

*P.s. Все используемые и настроенные мною CRDs лежат в папке *[configuration-stackgres/](https://github.com/ekaterinayefimovich/stackgres-configuration/tree/main/configuration-stackgres).**

**Все CRDs, которые можно использовать с данным оператором [можно найти тут](https://stackgres.io/doc/latest/reference/crd/).**

## 2.2 SGCluster

[Создание кластера](https://stackgres.io/doc/latest/administration/cluster-creation/#creating-the-cluster).
Только после всех вспомогательных ресурсов!

Именно в данной конфигурации указываем конкретную версию Postgres, TimescaleDB extension, подключаем SGInstanceProfile, SGPostgresConfig, SGObjectStorage (тут же происходит настройка частоты резервных копирований и установка их срока хранения) и др.
Тут же включаем *prometheusAutobind: true* для подключения Prometheus exporter.

**Пример конфигурации:**

```yaml
apiVersion: stackgres.io/v1
kind: SGCluster
metadata:
  name: timescale-db
  namespace: timescale-db-namespace
spec:
  instances: 3
  postgres:
    version: '14.15'
    extensions:
      - name: timescaledb
        version: '2.17.2'
  sgInstanceProfile: "size-small"
  configurations:
    sgPostgresConfig: "timescaledb-config"
    observability:
      prometheusAutobind: true
    backups:
      - sgObjectStorage: "gcs-backup-config"
        cronSchedule: "0 0 * * *"
        retention: 7
  managedSql:
    scripts:
    - sgScript: db-setup
  pods:
    persistentVolume:
      size: "5Gi"
      storageClass: "standard-rwo"
```

Как только кластер будет полностью развернут и доступен, необходимо подключиться к Мастеру и установить [extension TimescaleDB](https://stackgres.io/doc/latest/administration/extensions/).

Установка происходит при помощи plsql команды:
```sql
CREATE EXTENSION timescaledb;
```

Чтобы обновить TimescaleDB до новой версии, необходимо в конфигурации SGCluster указать новую версии TimescaleDB, затем перезапустить кластер (смотреть ниже про рестарт кластера).
После того, как кластер перезапуститься, необходимо так же подключиться к Мастеру и прогнать команду:
```sql
ALTER EXTENSION timescaledb UPDATE;
```
**Версии TimescaleDB, поддерживаемые определенными версиями PosgreSQL, а так же [список всех остальных расширений смотреть тут](https://stackgres.io/doc/latest/intro/extensions/).**

# 3. Мануальные бэкапы или принудительный рестарт кластера

## 3.1 Мануальный бэкап

[Официальная документация.](https://stackgres.io/doc/latest/administration/backups/#creating-a-manual-backup)

Реализуется при помощи CRD [SGBackup](https://stackgres.io/doc/latest/reference/crd/sgbackup/).
Мануальный бэкап должен ссылаться на кластер и указывать, будет ли у него управляемый жизненный цикл (будет ли он удален по истечении срока хранения).

Пример:
```yaml
apiVersion: stackgres.io/v1
kind: SGBackup
metadata:
  name: backup
spec:
  sgCluster: stackgres
  managedLifecycle: true
status:
  internalName: base_00000002000000000000000E
  sgBackupConfig:
    compression: lz4
    storage:
      s3Compatible:
        awsCredentials:
          secretKeySelectors:
            accessKeyId:
              key: accesskey
              name: minio
            secretAccessKey:
              key: secretkey
              name: minio
        endpoint: http://minio:9000
        enablePathStyleAddressing: true
        bucket: stackgres
        region: k8s
      type: s3Compatible
  process:
    status: Completed
    jobPod: backup-backup-q79zq
    managedLifecycle: true
    timing:
      start: "2020-01-22T10:17:24.983902Z"
      stored: "2020-01-22T10:17:27.183Z"
      end: "2020-01-22T10:17:27.165204Z"
  backupInformation:
    hostname: stackgres-1
    systemIdentifier: "6784708504968245298"
    postgresVersion: "110006"
    pgData: /var/lib/postgresql/data
    size:
      compressed: 6691164
      uncompressed: 24037844
    lsn:
      start: "234881064"
      end: "234881272"
    startWalFile: 00000002000000000000000E
```

## 3.2 Принудительный рестарт кластера

[Официальная документация.](https://stackgres.io/doc/latest/administration/manual-restart/)

Реализуется при помощи CRD [SGDbOps](https://stackgres.io/doc/1.17/reference/crd/sgdbops/).

В конфигурации так же можно указать:
```yaml
apiVersion: stackgres.io/v1
kind: SGDbOps
metadata:
  namespace: timescale-db-namespace
  name: restart-cluster-1
spec:
  sgCluster: timescale-db
  op: restart
  restart:
    method: InPlace
```
Что будет означать, что перезапуск будет выполнен "на месте" (in-place), без создания дополнительных ресурсов. Для этого каждый под будет перезапущен по очереди.
