---
name: forge-map-events
description: "Generate the event/message-bus map. Dispatched by /forge-map."
argument-hint: "[--scope <path>] [--out <file>] [--refresh] [--quiet]"
triggers:
  - "forge map events"
  - "map message bus"
  - "scan pubsub"
  - "map kafka topics"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
user-invocable: false
---

# /forge-map-events — generate the event / message-bus map

Generator dispatched by `/forge-map`. Scans the host repo for pub/sub producers

- consumers across Kafka, NATS, RabbitMQ, AWS SQS/SNS, GCP Pub/Sub, Azure
  Service Bus, Redis Streams / Pub/Sub, MQTT, Kinesis, ZeroMQ, and in-process
  event buses; writes `$FORGE_HOME/maps/main/events.json` plus a `[maps.events]`
  entry in `$FORGE_HOME/forge.toml`. Shared envelope + write/registry contract:
  see `/forge-map` § "Shared JSON envelope".

Not user-invocable — go through `/forge-map events`.

## Inputs

| Input            | Required | Notes                                                              |
| ---------------- | -------- | ------------------------------------------------------------------ |
| `--scope <path>` | optional | Restrict scan to a subtree. Default `<repo-root>`.                 |
| `--out <file>`   | optional | Override output path. Default `$FORGE_HOME/maps/main/events.json`. |
| `--refresh`      | optional | No-op — every run rewrites. Accepted for API parity.               |
| `--quiet`        | optional | Suppress one-line summary.                                         |

## Detection signals

| Transport         | Signal                                                                                                                                         |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Kafka             | `kafkajs`, `confluent-kafka`, `sarama`, `kafka-python`, `spring-kafka`. Calls: `producer.send`, `consumer.subscribe / .run`, `@KafkaListener`. |
| NATS              | `nats.connect`, `nc.publish`, `nc.subscribe`, JetStream `js.publish / sub`.                                                                    |
| RabbitMQ (amqp)   | `amqplib`, `pika`, `streadway/amqp`. Calls: `channel.publish`, `channel.consume`, queue + exchange declarations.                               |
| AWS SQS           | `sqs.sendMessage`, `sqs.receiveMessage`, `@SqsListener`, queue URLs / names.                                                                   |
| AWS SNS           | `sns.publish`, topic ARNs / names.                                                                                                             |
| AWS Kinesis       | `kinesis.putRecord(s)`, `kinesis.getRecords`, KCL consumers.                                                                                   |
| GCP Pub/Sub       | `topic.publish`, `subscription.on('message')`, `pubsub.publisher / subscriber`.                                                                |
| Azure Service Bus | `sender.sendMessages`, `receiver.receiveMessages`, `ServiceBusClient`.                                                                         |
| Redis Streams     | `XADD`, `XREAD`, `XREADGROUP`.                                                                                                                 |
| Redis Pub/Sub     | `PUBLISH`, `SUBSCRIBE`, `PSUBSCRIBE`.                                                                                                          |
| MQTT              | `client.publish(topic, …)`, `client.subscribe(topic, …)`.                                                                                      |
| ZeroMQ            | `socket.send` / `socket.recv` on `PUB` / `SUB` / `PUSH` / `PULL` socket types.                                                                 |
| In-process bus    | Node `EventEmitter`, NestJS `EventEmitterModule`, `event-bus` libs, Go channels exposed as a bus. Flagged `in_process: true`.                  |

Schema sources (best-effort, joined to events when discoverable): `**/*.avsc`
(Avro), `**/*.proto` (Protobuf — message types only; service RPCs stay out of
scope here), `schemas/**/*.json`.

Unknown transport → emit gap `{reason: unsupported-transport, detail: <files>}`.
Multiple transports coexist — parse each, attribute each event.

## Process

1. **Resolve repo root + scope.**

   ```bash
   root="$(git rev-parse --show-toplevel)"
   scope="${SCOPE:-$root}"
   out="${OUT:-$FORGE_HOME/maps/main/events.json}"
   mkdir -p "$(dirname "$out")"
   ```

   Not a git repo → halt `MAP_BLOCKED reason not-a-repo`.

2. **Enumerate signals.** Grep + glob the scope per the table. Build
   `source_files[]` from every contributing file. Empty → write envelope
   `items: []` + gap `{reason: no-event-signal, detail: <scope>}`, jump to
   step 6.

3. **Parse per transport.** Each call site contributes one of:
   - **producer site** — file/line/symbol + transport + topic literal.
   - **consumer site** — file/line/symbol + transport + topic literal + optional
     consumer-group / subscription name.

   Topic literals:
   - String literal → record verbatim.
   - Constant / enum / config lookup → resolve when the value is statically
     discoverable in the same file or a sibling const file. Else record
     `topic: "<dynamic>"` + gap
     `{reason: dynamic-topic, detail: <file>:<line>}`.
   - Templated (`f"users.{tenant}.created"`) → record the template with
     placeholders preserved + gap `{reason: templated-topic, detail: ...}`.

   Payload type discovery (best-effort):
   - Type annotation on the publish/consume callback → record `payload.type` and
     `payload.ref` (`<file>:<line>` of the type decl).
   - Schema file (Avro `.avsc` or Protobuf `.proto`) whose declared subject name
     matches the topic → set `payload.schema_file`.
   - Else `payload: { type: "unknown" }` + gap `{reason: payload-unresolved}`.

4. **Group by topic.** Collapse all producer/consumer sites that share
   `(transport, topic)` into a single item. Order producers + consumers by
   `file:line`. Same topic on different transports → separate items + gap
   `{reason: topic-collision, detail: "<topic>: <transports>"}`.

5. **Normalize to item shape.**

   ```json
   {
     "topic": "user.created",
     "transport": "kafka",
     "producers": [
       {
         "file": "src/users/service.ts",
         "line": 88,
         "symbol": "publishUserCreated"
       }
     ],
     "consumers": [
       {
         "file": "src/notifications/worker.ts",
         "line": 24,
         "symbol": "onUserCreated",
         "group": "notifications-svc"
       }
     ],
     "payload": {
       "type": "UserCreatedEvent",
       "ref": "src/events/user-created.ts:5",
       "schema_file": "schemas/user-created.avsc"
     },
     "delivery": "at-least-once",
     "in_process": false
   }
   ```

   Field rules:
   - `topic` — string verbatim from source. Dynamic / templated values stay
     unresolved and gapped.
   - `transport` — one of the signal keys (`kafka`, `nats`, `rabbitmq`, `sqs`,
     `sns`, `kinesis`, `gcp-pubsub`, `azure-servicebus`, `redis-streams`,
     `redis-pubsub`, `mqtt`, `zeromq`, `in-process`).
   - `producers[]` / `consumers[]` — `file` / `line` mandatory; `symbol` is the
     function or method name (`<anonymous>` for inline closure);
     `consumers[].group` is the consumer group / subscription name when the
     transport has one (empty string otherwise).
   - `payload.type` / `payload.ref` — `"unknown"` / `null` when unresolved.
     `payload.schema_file` — repo-root-relative path or `null`.
   - `delivery` — best-effort: `"at-least-once"` / `"at-most-once"` /
     `"exactly-once"` / `"unknown"`. Infer from explicit config (Kafka
     `enable.idempotence`, SQS FIFO queue suffix, etc.); never guess.
   - `in_process` — `true` only for in-process bus items.

6. **Write the envelope.** Atomic tmp + `mv -f`:

   ```json
   {
     "$schema": "https://orrgal1.dev/forge-map/v1.json",
     "area": "events",
     "generator": "/forge-map-events",
     "generated_at": "<ISO-8601 UTC>",
     "repo_root": "<abs path>",
     "scope": "<scope relative to repo_root, or '.'>",
     "source_files": [
       "src/users/service.ts",
       "schemas/user-created.avsc",
       "..."
     ],
     "items": [
       /* per step 5 */
     ],
     "gaps": [
       /* per steps 2–4 */
     ]
   }
   ```

7. **Update `[maps.events]` in `$FORGE_HOME/forge.toml`.**

   ```toml
   [maps.events]
   file      = "maps/main/events.json"
   last_run  = "<ISO-8601 UTC>"
   generator = "/forge-map-events"
   ```

   Preserve `stale_after_days` and unknown keys. Atomic write.

8. **Emit summary** (unless `--quiet`):

   ```
   events: <N> topics, <K> gaps → $FORGE_HOME/maps/main/events.json
   ```

   Exit 0 on any envelope write.

## Honesty

- **Never resolve a dynamic topic by guessing.** Templated / config-driven
  topics stay literal-with-placeholders + gap.
- **Producer-only or consumer-only is valid.** Empty `consumers[]` (or
  `producers[]`) is a real signal. Never invent a counterpart.
- **Payload schemas link, not embed.** Record `schema_file` paths only.
- **Read-only on host repo.** Writes confined to
  `$FORGE_HOME/maps/main/events.json` and `$FORGE_HOME/forge.toml`.
- **Source attribution is mandatory.** Every producer / consumer carries
  `file` + `line`.
