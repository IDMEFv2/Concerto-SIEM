# encoding: utf-8
# vim: set ts=2 sw=2 et:

require 'yaml'
require 'logstash/filters/translate'
require 'logstash/filters/mutate'

def register(params)
  @rulesets = {}
  Dir.glob(params['rules']) do |filename|
    YAML.load_stream(File.read(filename)) do |doc|
      name = doc['ruleset']['name']
      doc['ruleset'].fetch('rules', []).each do |rule|
        r = []
        rule.fetch('translate', []).each do |trans|
          d = {
            "field" => trans['source'],
            "destination" => trans['target'],
            "dictionary" => trans['dictionary']
          }
          if trans.key?('fallback')
            d['fallback'] = trans['fallback']
          end
          f = LogStash::Filters::Translate.new(d)
          f.register
          r.push(f)
        end
        f = LogStash::Filters::Mutate.new({
            "add_field" => rule['fields'],
            "add_tag" => ['alert']
        })
        f.register
        r.push(f)
        ruleid = rule['id'].to_s.strip
        if ruleid.empty?
          logger.error("IDMEFv2 matching plugin: Can't read configuration for rule ID #{rule['id']}")
        else
          @rulesets[ruleid] = r
        end
      end
    end
  end
end

def filter(event)
  ruleid = event.get('[Attachment][RawLog][Content][rule][id]').to_s.strip
  if ruleid.empty?
    return [event]
  end

  # Keep compatibility with legacy numeric ids that were not quoted in YAML.
  filters = @rulesets[ruleid]
  if filters.nil?
    begin
      filters = @rulesets[Integer(ruleid)]
    rescue
      filters = nil
    end
  end

  Array(filters).each do |filter|
    filter.filter(event)
  end
  return [event]
end
