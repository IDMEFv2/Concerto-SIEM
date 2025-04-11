Adding IDMEFv2 ouput through HTTPS
===================================

You will need to do the following things:
- Create a new pipeline in Logstash
- Connect your pipeline to the latest IDMEFv2 Kafka topic
- Configure the HTTP module

For more information on configuring Logstash, you can find the documentation here:
https://www.elastic.co/guide/en/logstash/current/

Create a new pipeline in logstash
---------------------------------

Open the file `logstash/pipelines.yml` and add the following lines at the end:

```
- pipeline.id: my_new_pipeline
  path.config: /usr/share/logstash/config/pipeline/my_new_pipeline.conf
```

Connect your pipeline to the latest IDMEFv2 kafka topic and configure http module
---------------------------------------------------------------------------------

To do this, you need to create the associated file at `logstash/pipeline/my_new_pipeline.conf` with the following content:

```
# Input is Kafka. Topic is ${TOPIC_PROCESSED}
input {
  kafka {
    bootstrap_servers => "${BOOTSTRAP_SERVER}"
    client_id         => "store"
    group_id          => "store"
    topics            => ["${TOPIC_PROCESSED}"]
    codec             => json
  }
}

# Add some filter to finalize the normalization of IDMEFv2
filter {

# Add an ID if it does exists
  if ![ID] {
    uuid {
      target => "ID"
    }
  }
  
# Add the IDMEFv2 version if it does exists
  if ![Version] {
    mutate {
      replace => {
        '[Version]' => '2.D.V05'
      }
    }
  }

# Force the location (it is for the prototype)
  if ![Target][0][Location] {
    mutate {
      add_field => {
        '[Target][0][Location]' => 'Data Center'
      }
    }
  }
  
# Clean everything and be sure the message respect the IDMEFv2 format
  prune {
    whitelist_names => [
      # Top-level IDMEF attributes
      'Version',
      'ID',
      'OrganisationName',
      'OrganisationId',
      'EntityName',
      'EntityId',
      'Category',
      'ext-Category',
      'Cause',
      'Description',
      'Status',
      'Priority',
      'Confidence',
      'Note',
      'CreateTime',
      'StartTime',
      'EndTime',
      'AltNames',
      'AltCategory',
      'Ref',
      'CorrelID',
      'AggrCondition',
      'PredID',
      'RelID',

      # IDMEF classes
      'Analyzer',
      'Sensor',
      'Source',
      'Target',
      'Vector',
      'Attachment'
    ]
  }

}

# Ouput with HTPT
output {
  http {
    url => "https://example.com/endpoint"
    http_method => "post"
    format => "json"
    content_type => "application/json"
    ssl_certificate_validation => true
    retry_failed => true
  }
}
```

Finally, you just need to restart Logstash to apply the new pipeline.
