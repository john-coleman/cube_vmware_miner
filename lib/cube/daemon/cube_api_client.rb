require 'json'
require 'rest_client'

module Cube
  module Daemon
    class CubeApiClient
      def initialize(url, api_key, logger, timeout = 300)
        @resource = RestClient::Resource.new(url, timeout: timeout, headers: { :accept => :json, :content_type => :json, :'x-auth-token' => api_key })
        RestClient.log = logger
      end

      def send_post_request(url, params)
        @resource[url].post prepared_params(params)
      end

      def send_put_request(url, params)
        @resource[url].put prepared_params(params)
      end

      private

      def prepared_params(params)
        params.is_a?(Hash) ? params.to_json : params
      end
    end
  end
end
