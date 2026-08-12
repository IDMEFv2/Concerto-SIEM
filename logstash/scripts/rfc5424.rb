# encoding: utf-8
# vim: set ts=2 sw=2 et:
# Extract STRUCTURED-DATA from logs using the format defined in RFC 5424.

def register(params, logobj=nil)
  @message = params['message'] || '[Attachment][RawLog][Content][message]'
  @source = params['source'] || '[SD]'
  @target = params['target'] || '[Attachment][RawLog][Content][log][syslog]'
  @prefix = params['prefix'] || 'SD_'
  @escapable = '"\\]'
  @logger = logobj || logger
end

def parse_sd(event, raw_sd)
  in_brackets = false
  in_quotes = false
  tmp = ""
  pname = nil
  escaped = false
  got_sd_id = false

  raw_sd.each_char { |c|
    if escaped
      unless @escapable.contains?(c)
        tmp << '\\'
      end

      tmp << c
      escaped = false
      next
    end

    unless in_brackets
      if c != '['
        raise "An opening square bracket was expected at start of SD-ELEMENT"
      else
        in_brackets = true
        next
      end
    end

    if c == ' ' and !tmp.empty? and !got_sd_id
      event.set("#{@target}[#{prefix}#{tmp}]", nil)
      tmp = ""
      got_sd_id = true
      next
    end

    case c
    when '\\'
      escaped = true

    when ']'
      unless in_brackets
        raise "Unexpected end of SD-ELEMENT"
      end
      in_brackets = false

      if in_quotes
        raise "Unterminated quoted string"
      end

      unless tmp.empty?
        event.set("#{@target}[#{prefix}#{tmp}]", nil)
        tmp = ""
        got_sd_id = true
      end

      unless got_sd_id
        raise "Missing SD-ID field"
      end
      got_sd_id = false

    when '"'
      if pname.nil?
        raise "Missing parameter name before parameter value"
      end

      if in_quotes
        event.set("#{@target}[#{prefix}#{pname}]", tmp)
        tmp = ""
        pname = nil
      end
      in_quotes = !in_quotes

    else
      if c == ' '
        unless !in_quotes or (pname.nil? and tmp.empty?)
          raise "Unexpected whitespace"
        else
          next
        end
      end

      if c == '='
        if !pname.nil?
          raise "Unexpected parameter name"
        elsif tmp.empty?
          raise "Empty parameter name"
        else
          pname = tmp
          tmp = ""
          next
        end
      end

      tmp << c
    end
  }

  if pname or !tmp.empty?
    raise "Unterminated SD-ELEMENT"
  end
end

def filter(event)
  # Remove the UTF-8 BOM if necessary.
  message = event.get(@message)

  if message
    event.set(@message, message.delete_prefix("\xEF\xBB\xBF"))
  end

  raw_sd = event.remove(@source)
  if raw_sd.nil?
    return [event]
  end

  begin
    parse_sd(event, raw_sd)
  rescue RuntimeError => e
    logger.warn("#{e.message}: #{raw_sd.dump}")
  ensure
    return [event]
  end
end

if __FILE__ == $0
  register({}, Logger.new(STDOUT))
  e = LogStash::Event.new()
  parse_sd(e, "[timeQuality tzKnown=\"1\" isSynced=\"1\" syncAccuracy=\"59991\"][toto@1234 foo=\"bar\"][tata@42 baz=\"qux\"]")
end
