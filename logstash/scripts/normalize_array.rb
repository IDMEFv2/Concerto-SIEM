def register(params)
  @fields = params["fields"] || []
end

def filter(event)
  @fields.each do |field|
    value = event.get(field)

    next if value.nil?
    next if value.is_a?(Array)

    event.set(field, [value])
  end

  [event]
end
