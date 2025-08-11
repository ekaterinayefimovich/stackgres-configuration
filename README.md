# 1. Установка StackGres Operator.

```bash
helm repo add stackgres-charts https://stackgres.io/downloads/stackgres-k8s/stackgres/helm/
helm install --create-namespace --namespace stackgres stackgres-operator stackgres-charts/stackgres-operator --version <version>
```

Необходима установка с полным стеком мониторинга, подробнее тут – [Установка с мониторингом](https://stackgres.io/doc/latest/install/helm/#installation-with-monitoring).

Команда, чтобы дождаться готовности оператора StackGres к использованию:
```bash
kubectl wait -n stackgres deployment -l group=stackgres.io --for=condition=Available
```

## 1.1 Подключение к кластеру StackGres [тут](https://stackgres.io/doc/latest/administration/cluster/connection/).

# 2. Создание кластера

[Официальная документация](https://stackgres.io/doc/latest/administration/cluster-creation/)

## 2.1 Ресурсы:

[SGInstanceProfile](https://stackgres.io/doc/latest/reference/crd/sginstanceprofile/) - определяет ресурсы процессора (CPU) и оперативной памяти (memory), выделенные для каждого пода в кластере PostgreSQL.

[SGPostgresConfig](https://stackgres.io/doc/latest/reference/crd/sgpostgresconfig/) - представляет собой конфигурацию PostgreSQL. Он используется для настройки параметров PostgreSQL, таких как postgresVersion, shared_buffers или password_encryption.
Именно тут очень важно установить *shared_preload_libraries: timescaledb*, чтобы в дальнейшем можно установить TimescaleDB extension.

[SGPoolingConfig](https://stackgres.io/doc/latest/administration/configuration/pool/) - обеспечивает масштабируемость соединений.

[SGObjectStorage](https://stackgres.io/doc/latest/reference/crd/sgobjectstorage/) - позволяет настроить место, где будут храниться резервные копии.
Главное - настройка доступа к бакету.

[SGScript](https://stackgres.io/doc/latest/administration/cluster-creation/#configuring-scripts) - используется при необходимости запуска скрипта сразу же после развертывания кластера.

***Все вышеперечисленное (как и некоторые другие CRDs) необходимо применять до создания SGCluster!***

*P.s. Все используемые и настроенные мною CRDs лежат в папке *[configuration-stackgres/](https://github.com/ekaterinayefimovich/stackgres-configuration/tree/main/configuration-stackgres).**

## 2.2 SGCluster

[Создание кластера](https://stackgres.io/doc/latest/administration/cluster-creation/#creating-the-cluster).

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

Как только кластер будет полностью развернут и доступен, необходимо подключиться к Мастеру и установить [extension TimescaleDB](https://stackgres.io/doc/1.16/administration/extensions/).

Установка происходит при помощи plsql команды:
```sql
CREATE EXTENSION timescaledb;
```

Чтобы обновить TimescaleDB до новой версии, необходимо в конфигурации SGCluster указать новую версии TimescaleDB, затем перезапустить кластер (смотреть ниже про рестарт кластера).
После того, как кластер перезапуститься, необходимо так же подключиться к Мастеру и прогнать команду:
```sql
ALTER EXTENSION timescaledb UPDATE;
```

# 3. Мануальные бэкапы или принудительный рестарт кластера

## 3.1 Мануальный бэкап

[Официальная документация.](https://stackgres.io/doc/latest/administration/backups/#creating-a-manual-backup)

Реализуется при помощи CRD [SGBackup](https://stackgres.io/doc/latest/reference/crd/sgbackup/).
Мануальный бэкап должен ссылаться на кластер и указывать, будет ли у него управляемый жизненный цикл (будет ли он удален по истечении срока хранения).

## 3.2 Принудительный рестарт кластера

[Официальная документация.](https://stackgres.io/doc/latest/administration/manual-restart/)

Реализуется при помощи CRD [SGDbOps](https://stackgres.io/doc/1.16/reference/crd/sgdbops/).

В конфигурации так же можно указать:
```yaml
restart:
    method: InPlace
```
Что будет означать, что перезапуск будет выполнен "на месте" (in-place), без создания дополнительных ресурсов. Для этого каждый под будет перезапущен по очереди.
