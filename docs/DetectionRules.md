# Detection rules

Alerts can be created by Probes (IDS, AV, FW, CCTVs, etc) and sent to IDMEFv2. Concerto SIEM can also analyse syslog messages and identify potential incidents based on preconfigured "Detection rules". Those rules are composed of two part (in two separate files) a parsing rule detecting "incident" logs and parsing the content and an idmefv2 rule creation an IDMEFv2 message with the data previously parsed. Those two rules are identfied by the same ID.

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

## Writing IDMEFv2 Rules

To generate an alert from this parsed data, create a corresponding file (e.g., `<my_file>.yml`) in the `logstash/idmef/` directory.

This rule will use the parsed data to create an IDMEFv2 alert.

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
