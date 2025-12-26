# encoding: utf-8
# vim: set ts=2 sw=2 et:

require 'yaml'
require 'logstash/filters/grok'

def register(params)
  @rulesets = []
  @groks = {}
  @dummy = {nil => nil}
  @fields = ['author', 'category', 'description', 'license', 'version']

  Dir.glob(params['rules']) do |filename|
    logger.debug("match.rb : Loading " + filename)
    YAML.load_stream(File.read(filename)) do |doc|
      patterns = []
      rules = {}
      name = doc['ruleset']['name']

      doc['ruleset'].fetch('rules', []).each do |rule|
        patterns.push("%{RULEID:[@metadata][ruleid][#{rule['id']}]}#{rule['pattern']}")
        rules[rule['id']] = rule
      end
      next unless patterns # Ignore empty rulesets

      @rulesets.push({'name' => name, 'predicate' => doc['ruleset']['predicate'], 'rules' => rules})
      filter = LogStash::Filters::Grok.new({
        'match'               => {doc['ruleset']['field'] => patterns},
        'keep_empty_captures' => true,
        'break_on_match'      => true,
        'ecs_compatibility'   => "disabled",
        'add_tag'             => ["last"],
        'tag_on_timeout'      => 'last',
        'tag_on_failure'      => [],
        'pattern_definitions' => {'RULEID' => '(?<!>)'}
      })
      @groks[name] = filter
      filter.register
    end
  end
end

def eval_predicate(predicate, event)
  arities = {
    'not'           => 1,
    'variable'      => -1, # Accepts a string directly as its sole operand (not an array)
    'constant'      => -1, # "operands" contains the constant's value and can be anything
    'equal'         => 2,
    'not_equal'     => 2,
    'less_than'     => 2,
    'less_equal'    => 2,
    'greater_than'  => 2,
    'greater_equal' => 2,
    'match'         => 2,
    'not_match'     => 2,
    'in'            => 2,
    'not_in'        => 2,
    'and'           => 2,
    'or'            => 2,
    'nand'          => 2,
    'xor'           => 2,
  }
  operations = {
    'equal'         => ['==', false],
    'not_equal'     => ['==', true],
    'less_than'     => ['<', false],
    'less_equal'    => ['<=', false],
    'greater_than'  => ['>', false],
    'greater_equal' => ['>=', false],
    'in'            => ['include?', false],
    'not_in'        => ['include?', true],
    'xor'           => ['^', false],
  }

  op = predicate['operator']
  arity = arities[op]
  raise "Invalid operator: #{op}" if arity.nil?
  raise "Invalid number of argument for #{op} operator (expected #{arity}, got #{predicate['operands'].length}" unless arity == -1 or arity == predicate['operands'].length

  case op
  when 'not'
    return !event.get(predicate['operands'][0])
  when 'variable'
    raise "Invalid reference: #{predicate['operands']}" unless predicate['operands'].is_a?(String)
    return event.get(predicate['operands'])
  when 'constant'
    return predicate['operands']
  end

  opd1 = eval_predicate(predicate['operands'][0], event)
  case op
  when 'and'
    return false if !opd1 # Make the evaluation lazy
    return !!eval_predicate(predicate['operands'][1], event)
  when 'nand'
    return false if opd1 # Make the evaluation lazy
    return !eval_predicate(predicate['operands'][1], event)
  when 'or'
    return true if opd1 # Make the evaluation lazy
    return !!eval_predicate(predicate['operands'][1], event)
  when 'xor'
    # Convert both operands to boolean values before the actual test
    opd1 = !!opd1
    opd2 = !!eval_predicate(predicate['operands'][1], event)
  when 'match', 'not_match'
    begin
      opd2 = opd1
      opd1 = Regex.new(eval_predicate(predicate['operands'][1], event)).match(opd1)
    rescue
      # @FIXME Log a warning/error
      return false
    end
  else
    opd2 = eval_predicate(predicate['operands'][1], event)
  end

  op, negate = operations[op]
  begin
    res = opd1.public_send(op, opd2)
    return negate ? !res : !!res
  rescue
    return false
  end
end

def filter(event)
  @rulesets.each do |ruleset|
    logger.debug("match.rb : filter : " + ruleset['name'])
    predicate = ruleset['predicate']
    next unless predicate.nil? or eval_predicate(predicate, event)

    name = ruleset['name']
    filter = @groks[name]
    filter.filter(event)
    if (event.get('tags') || @dummy).include?('last')
      event.set('[Attachment][RawLog][Content][rule][ruleset]', name)

      ruleid = (event.get('[@metadata][ruleid]') || @dummy).first[0]
      if ruleid
        event.set('[Attachment][RawLog][Content][rule][id]', ruleid)

        ruleid = Integer(ruleid) rescue ruleid
        rule = ruleset['rules'][ruleid]
        @fields.each do |field|
          v = rule[field]
          event.set("[Attachment][RawLog][Content][rule][#{field}]", v) if v
        end

        refs = Array(event.get('Ref'))
        refs.push("urn:rule:#{ruleid}")
        v = rule['outcome']
        if v
          event.set("[Attachment][RawLog][Content][event][outcome]", v)
          refs.push("urn:outcome:#{v}")
        end
        event.set('Ref', refs)

        rule.fetch('copy', {}).each do |dst, src|
          v = event.get(src)
          event.set(dst, v) if v
        end
      end

      break
    end
  end

  return [event]
end
