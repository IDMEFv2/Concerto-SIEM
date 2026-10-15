========================================================================
 Logstash Scripts - Concerto-SIEM
========================================================================

This directory contains the Ruby scripts used by the Logstash pipelines
to parse, enrich, normalize, and validate security events as they flow
through the Concerto-SIEM prototype.

Each script is registered as a `ruby` filter inside one or more pipeline
configurations located in `logstash/pipeline/`.


------------------------------------------------------------------------
 SCRIPTS
------------------------------------------------------------------------

PARSING
-------
rfc5424.rb
    Parses STRUCTURED-DATA from RFC 5424 syslog messages and removes
    the UTF-8 BOM. Extracted fields are stored under
    [Attachment][RawLog][Content][log][syslog].
    Params: source, target, prefix

extraction.rb
    Scans a text field for IPs, emails, and URIs. Matches are stored
    under [Attachment][EXTDATA] for downstream CTI enrichment.
    Params: source

ENRICHMENT
----------
dns.rb
    Forward and reverse DNS lookups for Sensor, Analyzer, Source,
    Target, and ECS classes.
    Params: nameserver, timeout, max_retries, hostsfile,
            hit_cache_size, hit_cache_ttl,
            failed_cache_size, failed_cache_ttl

geoip.rb
    GeoIP and UN/LOCODE enrichment for IP fields.
    Params: geoip_database, unlocode_database,
            cache_size, cache_ttl, refresh_interval

geoloc.rb
    Reverse-geocodes coordinates into "City, Admin, Country" strings.
    Params: database, cache_size, cache_ttl, refresh_interval

cti.rb
    Threat Intelligence lookups against JSON feeds (IP, Email).
    Adds matches to [Source][*][TI] as "attribute:origin".
    Params: databases, cache_size, cache_ttl, refresh_interval

iana.rb
    Resolves IANA protocol numbers and port/service associations.
    Params: protocols, services

NORMALIZATION
-------------
analyzer.rb
    Populates the top-level Analyzer object from ANALYZER_* env vars.
    Params: none

normalize_array.rb
    Ensures a list of fields are always arrays.
    Params: fields

fill_alert.rb
    Fills in missing Source/Target fields (Hostname, Location, IP,
    Port, GeoLocation) from the RawLog content.
    Params: none

manage_predid.rb
    Marks alerts listed in PredID as "Obsolete" via the Elasticsearch
    _update_by_query API.
    Params: es_url, username, password

RULE MATCHING
-------------
rules.rb
    Loads IDMEFv2 rules from logstash/idmef/*.yml and maps RawLog
    fields into top-level IDMEFv2 attributes.
    Params: rules

match.rb
    Loads Sigma-style rulesets from logstash/rulesets/*.yml, evaluates
    each ruleset's predicate, and applies matching Grok patterns.
    Params: rules


------------------------------------------------------------------------
 CONVENTIONS
------------------------------------------------------------------------

- Every script defines register(params) and filter(event).
- filter(event) returns [event], or [] to drop the event.
- Missing fields are silently skipped.
- Enrichment scripts use an LRU TTL cache and a read/write lock for
  thread-safe database reloading.
- Rules files support hot-reloading via refresh_interval.


------------------------------------------------------------------------
 ADDING A NEW SCRIPT
------------------------------------------------------------------------

1. Create the Ruby file in this directory.
2. Implement register(params) and filter(event).
3. Reference it from a pipeline:

     ruby {
       path          => "/usr/share/logstash/config/scripts/my_script.rb"
       script_params => { "my_option" => "value" }
     }

4. Mount the file into the Logstash container
   (see pods/logstash.yml or docker-compose.yml).
5. Add an entry to this README.


------------------------------------------------------------------------
 RELATED DIRECTORIES
------------------------------------------------------------------------

../pipeline/     Logstash pipeline definitions
../idmef/        IDMEFv2 rule definitions (used by rules.rb)
../rulesets/     Sigma-style rulesets (used by match.rb)
../IDMEFv2.schema, ../IDMEFv2-light.schema   JSON validation schemas
../IDMEFv2.mapping                            Elasticsearch index template

========================================================================
