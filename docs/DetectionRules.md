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

## Writing IDMEFv2 Rules (mapping rules)

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

For our SSH example, the corresponding `logstash/idmef/ssh.yml` rule would be:
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
        "[Analyzer][Type]": "Cyber"
        "[Source][0][Protocol]":
          - "tcp"
          - "ssh"
        "[Target][0][Service]": "%{[Attachment][RawLog][Content][process][name]}" # Dynamic field from parsed log
        "[Target][0][User]": "%{[Attachment][RawLog][Content][destination][user][name]}" # Dynamic field
        "[Description]": "Someone tried to log in as '%{[Attachment][RawLog][Content][destination][user][name]}' from %{[Attachment][RawLog][Content][source][address]} port %{[Attachment][RawLog][Content][source][port]} using the %{[Attachment][RawLog][Content][SSH][auth_method]} method"
```
## YAML quoting rules for Grok patterns

Grok patterns contain regular-expression escapes such as `\s`, `\w`, `\d`, `\.`, `\+`, `\(`, `\)`, `\[`, `\]`, `\{`, `\}`.
In YAML, these escapes **must not** appear inside a double-quoted scalar, because YAML interprets `\` as its own escape character and only accepts a small fixed set (`\n`, `\t`, `\r`, `\"`, `\\`, `\uXXXX`, `\xXX`, `\UXXXXXXXX`).
Any other `\X` sequence inside `"..."` raises a `yaml.scanner.ScannerError` at load time.

**Rule**: as soon as a Grok pattern contains a backslash, put it between **single quotes** in the YAML file.

### Wrong — double quotes, contains `\s`

```yaml
    - id: 4800
      pattern: "bonding:\s%{WORD:[Attachment][RawLog][Content][bonding][belong]}:..."
```

Loading this file raises:

```
yaml.scanner.ScannerError: while scanning a double-quoted scalar
  found unknown escape character 's'
```

### Right — single quotes, backslashes preserved literally

```yaml
    - id: 4800
      pattern: 'bonding:\s%{WORD:[Attachment][RawLog][Content][bonding][belong]}:...'
```

Inside single-quoted YAML scalars, **no escape sequence is interpreted**. The only special rule is that a literal single quote must be doubled (`''`).

### Comparison table

| Value content | YAML quoting | Reason |
|---|---|---|
| `Access.Other` | `"..."` or `'...'` | No backslash, either is fine |
| `sudo_mapping` | `"..."` or `'...'` | No backslash |
| `Failed %{NOTSPACE:...} for user` | `"..."` | No backslash, double quotes are fine |
| `bonding:\s%{WORD:...}` | **`'...'`** | Contains `\s` — forbidden in `"..."` |
| `denied  \{ (?<desc>[\w ]+) \}` | **`'...'`** | Contains `\w` and `\{` — forbidden in `"..."` |
| `%{IP:...}\.%{INT:...}` | **`'...'`** | Contains `\.` — forbidden in `"..."` |
| A value that must contain a real newline | `"..."` with `\n` | Single quotes cannot express a real newline |

**Practical rule**: if the value contains a backslash followed by anything other than `n`, `t`, `r`, `"`, `\`, `u`, `x`, `U` → **use single quotes**.

### What about `samples:`?

Samples are raw log lines. They rarely contain backslashes, but if they do (e.g. Windows paths like `C:\Program Files\...`), the same rule applies: use single quotes.

```yaml
      samples:
        - '2009-02-23 15:55:01 slxp0060 Tripwire: Added C:\test\AutoRetrieve\bin\AutoRetrieve.ini on srvtest'
```

### What about `description:`?

Descriptions are human-readable text and almost never contain backslashes. Double quotes are fine and preferred for consistency with the rest of the document.

```yaml
  description: "APC Environmental Monitoring Unit (EMU) syslog messages"
```

### Quick self-check

Before committing a ruleset, run:

```bash
python3 -c "
import yaml
with open('my_ruleset.yml') as f:
    docs = [d for d in yaml.safe_load_all(f) if d]
print(len(docs), 'documents loaded')
"
```

If it raises a `ScannerError` mentioning an unknown escape character, the offending line is given with its line and column numbers. Replace the surrounding double quotes with single quotes on that line, and re-run until all documents load.

### Few tips for creating rules with AI

- Rules language is English

- All values must be quoted. Use **double quotes** for plain values (names, descriptions, categories, field names). Use **single quotes** for any value that contains a backslash (typically Grok patterns with `\s`, `\w`, `\d`, `\.`, etc.). See the "YAML quoting rules for Grok patterns" section above.

- IDMEFv2 Alert Description attributes should be as clear as possible for operator, if original message description is not clear, try make it clearer

- IDMEFv2 Alert Category should not be other.unclassified unless no other choice

- Do not use YML anchor

- Analyzer.data is ALWAYS Log and only Log (Detection rules are parsing Logs)

- do not use outcome fields

- Number of parsing rules (in rulesets)  must be exactly the same as number of mapping rules (in idmef)

- Rules names should be : ssh_parsing.yml in rulesets and ssh_mapping.yml in idmef

- Name of the rule set must be the prefix of the file name (ex: ssh_parsing.yml => ssh_parsing)  

- All parsing and mapping rules files should have a banner

```
# ============================================================
# File : ssh_parsing.yml
# Description : Concerto parsing rules for ssh syslog messages
# ssh parsing IDs: 1902, 1903, 1904
# Auteur      :  Concerto Security
# Licence     : MIT
# Version     :  0.2
# ============================================================ 

