# IDMEFv2-prototype

The IDMEFv2 prototype is a Security Information & Event Manager (SIEM) compatible with the IDMEFv2 format.
Its main goal is to demonstrate building a cyber-physical SIEM using the IDMEFv2 (Incident Detection Message Exchange Format v2) standard.

This prototype, based partially on Prelude OSS (IDMEFv1), is under active development with the current version (2024) operational.

Key features include:
* A `kafka`-based communication bus
* JSON alert storage in `Elasticsearch`
* A web user interface (based on `Prewikka OSS`)
* A Python rules-based correlation engine (based on `Prelude OSS Correlator`)
* Log management and analysis with `Logstash`
* A test environment with local Linux logs and a local webserver

IDMEFv2-prototype is a contribution from the Safe4Soc (http://safe4soc.eu) Consortium towards IDMEFv2 standardization.

More information about IDMEFv2 at :
[https://www.idmefv2.org](https://www.idmefv2.org)

# Prototype of IDMEFv2 implementation

This repository provide docker files and docker-compose files for these
services:

  - Kafka
  - Zookeeper
  - Kafdrop
  - Elasticsearch
  - Logstash
  - SIEM Web Interface
  - PostgreSQL
  - NGINX test Webserver

# Prerequisite

You need :

  - podman version 4 or higher
  - podman-compose version 1 or higher

# Run the prototype

Run the following command:
```bash
make up
```

# Stop the prototype

Run the following command:
```bash
make down
```

# Clean the prototype

Run the following command:
```bash
make clean
```

# Exposed services

The following services are exposed with their primary purpose:

  - Web interface: `http://localhost` (SIEM user interface)
  - Elastic database: `http://elastic:elastic@localhost:9200` (Elasticsearch for alert & log storage)
  - Syslog input: `tcp://localhost:6514` (For receiving syslog messages)
  - IDMEFv2 input: `http://localhost:4690` (For receiving IDMEFv2 alerts)
  - Kafka status: `http://localhost:9201` (Kafdrop UI for Kafka monitoring)
  - Kafka broker: `http://localhost:9092` (Main Kafka message bus)
  - NGINX test Webserver: `http://localhost:8080` (Test webserver for generating logs)

# Test your prototype system

## Configure your system to send logs to your prototype

By default, the prototype listens on `localhost` on port `6514` for logs over TCP (no SSL) and UDP.

You can configure your local system to send logs to the prototype. For example, with `rsyslog`:
  - Edit `/etc/rsyslog.conf`.
  - Add the following line at the end of the file:
    ```
    *.* @@127.0.0.1:6514
    ```
  - Restart the `rsyslog` process:
    ```
    systemctl restart rsyslog
    ```

## Generate errors from your NGINX test webserver

A web server is available by default and is already configured to send logs to the prototype.
The `NGINX` test webserver has the following URLs:
  - `http://localhost` (returns a 200 access code)
  - `http://localhost/test_403` (returns a 403 error)
  - `http://localhost/test_404` (returns a 404 error)
  - `http://localhost/test_500` (returns a 500 error)
  - All other URLs return a 404 error.

To manage the test webserver, use the following commands:
```bash
make up-test
```
or
```bash
make down-test
```
or
```bash
make clean-test
```

## Push IDMEFv2 to your prototype

Your prototype is listening on port `4690` for IDMEFv2 alerts.

For example, if you have a file named `/tmp/test.json` with the following content:

```json
{
     "Description": "Potential bruteforce attack on root user account",
     "Priority": "Medium",
     "CreateTime": "2024-10-18T20:55:29.196408+00:00",
     "StartTime": "2021-05-10T16:55:29+00:00",
     "Category": [
       "Attempt.Login"
     ],
     "Analyzer": {
       "Name": "SIEM",
       "Hostname": "siem.acme.com",
       "Type": "Cyber",
       "Model": "Concerto SIEM 5.2",
       "Category": [
         "SIEM",
         "LOG"
       ],
       "Data": [
         "Log"
       ],
       "Method": [
         "Monitor",
         "Signature"
       ],
       "IP": "192.0.2.1"
     },
     "Sensor": [
       {
         "IP": "192.0.2.5",
         "Name": "syslog",
         "Hostname": "www.acme.com",
         "Model": "rsyslog 8.2110",
         "Location": "Server room A1, rack 10"
       }
     ],
     "Target": [
       {
         "IP": "192.0.2.2",
         "Hostname": "www.acme.com",
         "Location": "Server room A1, rack 10",
         "User": "root"
       }
     ]
 }
```

You can send this alert to the prototype using `curl`:

```bash
curl -X POST -sSv http://127.0.0.1:4690 -H "Content-Type: application/json" --data @/tmp/test.json
```

## Manually send logs to your prototype

For example, to send a log entry indicating a failed SSH login:
```
Mar  11 11:00:35 itguxweb2 sshd[24541]: Failed password for root from 12.34.56.78 port 1806
```
You can use the `netcat` tool:
```bash
echo 'Mar  11 11:00:35 itguxweb2 sshd[24541]: Failed password for root from 12.34.56.78 port 1806' | nc -N localhost 6514
```
Alternatively, use the embedded test container:
```bash
make tests_logs
```
Note: Example logs are located in the `tests/example_logs` file.

You can also send an IDMEFv2 alert using the embedded test container:
```bash
make tests_idmefv2
```
Note: Example IDMEFv2 alerts are in the `tests/example_idmefv2` file.

## Write your own parsing rule

For example, consider parsing the following log entry:
```
Mar  1 12:13:22 rhel7 sshd[70149]: Failed password for invalid user goro from 192.168.133.128 port 55662 ssh2
```

First, create a `Grok` pattern. `Grok` is similar to regex but provides a higher-level framework for parsing logs.

*   **Grok explanation**: [https://docs.mezmo.com/telemetry-pipelines/using-grok-to-parse](https://docs.mezmo.com/telemetry-pipelines/using-grok-to-parse)
*   **Logstash pre-built patterns**: [https://github.com/logstash-plugins/logstash-patterns-core/tree/main/patterns](https://github.com/logstash-plugins/logstash-patterns-core/tree/main/patterns)
*   **Grok validator**: [https://grokconstructor.appspot.com/do/match](https://grokconstructor.appspot.com/do/match)

For this example, the `Grok` pattern is:
```grok
Failed %{NOTSPACE:[Attachment][RawLog][Content][SSH][auth_method]} for (invalid|illegal) user (?=%{USERNAME:[Attachment][RawLog][Content][related][user]})%{USERNAME:[Attachment][RawLog][Content][destination][user][name]} from %{IPORHOST:[Attachment][RawLog][Content][source][address]} port %{POSINT:[Attachment][RawLog][Content][source][port]:int} ssh2
```

The expected output fields are:
  - `[Attachment][RawLog][Content][SSH][auth_method]` => `password`
  - `[Attachment][RawLog][Content][destination][user][name]` => `goro`
  - `[Attachment][RawLog][Content][source][address]` => `192.168.133.128`
  - `[Attachment][RawLog][Content][source][port]` => `55662`

Next, create a "Match" rule. Add a new YAML file (e.g., `<my_file>.yml`) in the `logstash/rulesets/` directory.
The file should follow this format:
```
ruleset:
  name: <ruleset_name>
  description: <A description of your ruleset. Generally, what does the software that generate logs you want to parse>
  field: "[Attachment][RawLog][Content][message]"
  <predicate_if_needed>
  rules:
    - id: <rule_id, must be unique in your whole SIEM installation>
      pattern: <grok_pattern>
      samples:
        - <Example of log>
```

The `predicate` part improves performance by executing the rule only on specific logs. For instance, to run the rule only if the field `[Attachment][RawLog][Content][process][name]` is `sshd`, the predicate is as follows:
```
predicate:
  operator: equal
  operands:
    - operator: variable
      operands: "[Attachment][RawLog][Content][process][name]"
    - operator: constant
      operands: "sshd"
```

For our example, the complete ruleset (`logstash/rulesets/ssh.yml`) would be:
```yaml
ruleset:
  name: ssh
  description: "SSH is a cryptographic network protocol for secure remote login and other network services over an unsecured network."
  field: "[Attachment][RawLog][Content][message]"
  predicate:
    operator: equal
    operands:
      - operator: variable
        operands: "[Attachment][RawLog][Content][process][name]"
      - operator: constant
        operands: "sshd"
  rules:
    - id: 1912 # This ID must be unique across all rulesets
      pattern: "Failed %{NOTSPACE:[Attachment][RawLog][Content][SSH][auth_method]} for (invalid|illegal) user (?=%{USERNAME:[Attachment][RawLog][Content][related][user]})%{USERNAME:[Attachment][RawLog][Content][destination][user][name]} from %{IPORHOST:[Attachment][RawLog][Content][source][address]} port %{POSINT:[Attachment][RawLog][Content][source][port]:int} ssh2"
      outcome: "failure"
      samples:
        - "Mar  1 12:13:22 rhel7 sshd[70149]: Failed password for invalid user goro from 192.168.133.128 port 55662 ssh2"
        - "Jan 14 11:29:17 ras sshd[18163]: Failed publickey for invalid user fred from fec0:0:201::3 port 62788 ssh2"
```

At this stage, all extracted fields are available within the log and can be found in the "ARCHIVE" section of the web interface.

To generate an alert from this parsed data, create a corresponding file (e.g., `<my_file>.yml`) in the `logstash/to_idmef/` directory.

The file format is similar:
```
ruleset:
  name: <ruleset_name>
  rules:
    - id: <rule_id>
      <translate if needed>
      fields:
        <list_of fields to fill based on IDMEFv2 format>
```

Remember that IDMEFv2 RFC is available here: https://datatracker.ietf.org/doc/draft-lehmann-idmefv2

The `<translate>` directive allows conditional field population based on other available fields. For example, to set the `Priority` field to "Low" by default, but to "Medium" if the user (`[Attachment][RawLog][Content][destination][user][name]`) is `root`, use the following syntax:

```
translate:
  - source: "[Attachment][RawLog][Content][destination][user][name]"
    target: "[Priority]"
    dictionary:
      "root": "Medium"
    fallback: "Low"
```

For our SSH example, the corresponding `logstash/to_idmef/ssh.yml` rule would be:
```yaml
ruleset:
  name: ssh
  rules:
    - id: 1912 # Must match the ID in the parsing ruleset
      translate:
        - source: "[Attachment][RawLog][Content][destination][user][name]"
          target: "[Priority]"
          dictionary:
            "root": "Medium"
          fallback: "Low"
      fields:
        "[@metadata][IDMEFv2][source]": "source" # Predefined value for log source
        "[@metadata][IDMEFv2][target]": "host"   # Predefined value for log target
        "[Category][0]": "Attempt.Login"
        "[Analyzer][Data]":
          - "Log"
          - "Auth"
        "[Analyzer][Type]": "Cyber"
        "[Source][0][Protocol]":
          - "tcp"
          - "ssh"
        "[Target][0][Service]": "%{[Attachment][RawLog][Content][process][name]}" # Dynamic field from parsed log
        "[Target][0][User]": "%{[Attachment][RawLog][Content][destination][user][name]}" # Dynamic field
        "[Description]": "Someone tried to log in as '%{[Attachment][RawLog][Content][destination][user][name]}' from %{[Attachment][RawLog][Content][source][address]} port %{[Attachment][RawLog][Content][source][port]} using the %{[Attachment][RawLog][Content][SSH][auth_method]} method"
```
