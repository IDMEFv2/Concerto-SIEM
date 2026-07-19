require 'net/http'
require 'json'
require 'uri'

def register(params)
  @es_url   = params["es_url"]
  @username = params["username"]
  @password = params["password"]
end

def filter(event)

  predids = event.get("PredID")

  return [event] unless predids

  predids = [predids] unless predids.is_a?(Array)

  predids.each do |predid|

    next if predid.nil? || predid.to_s.empty?

    uri = URI(@es_url)

    body = {
      query: {
        match: {
          ID: predid
        }
      },
      script: {
        source: "ctx._source.Status = 'Obsolete'",
        lang: "painless"
      }
    }

    request = Net::HTTP::Post.new(uri)
    request.basic_auth(@username, @password)
    request["Content-Type"] = "application/json"
    request.body = body.to_json

    Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end
  end

  [event]
end
