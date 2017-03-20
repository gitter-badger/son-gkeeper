## SONATA - Gatekeeper
##
## Copyright (c) 2015 SONATA-NFV [, ANY ADDITIONAL AFFILIATION]
## ALL RIGHTS RESERVED.
## 
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
## 
##     http://www.apache.org/licenses/LICENSE-2.0
## 
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
## 
## Neither the name of the SONATA-NFV [, ANY ADDITIONAL AFFILIATION]
## nor the names of its contributors may be used to endorse or promote 
## products derived from this software without specific prior written 
## permission.
## 
## This work has been performed in the framework of the SONATA project,
## funded by the European Commission under Grant number 671517 through 
## the Horizon 2020 and 5G-PPP programmes. The authors would like to 
## acknowledge the contributions of their colleagues of the SONATA 
## partner consortium (www.sonata-nfv.eu).
# encoding: utf-8

# require 'json' 
# require 'pp'
# require 'addressable/uri'
# require 'yaml'
# require 'bunny'
require 'prometheus/client'
require 'prometheus/client/push'
# require 'net/http'
require 'json'

class GtkKpi < Sinatra::Base  
  
  # default registry
  registry = Prometheus::Client.registry 

  def self.counter(params, pushgateway, registry)

    begin
      if (params[:base_labels] == nil) 
        base_labels = {}
      else
        base_labels = params[:base_labels]                
      end    

      if (params[:value] == nil)
        factor = 1
      else
        factor = params[:value]
      end

      # if counter exists, it will be increased
      if registry.exist?(params[:name].to_sym)
        counter = registry.get(params[:name])
        counter.increment(base_labels, factor)
        Prometheus::Client::Push.new(params[:job], params[:instance], pushgateway).replace(registry)
      else
        # creates a metric type counter
        counter = Prometheus::Client::Counter.new(params[:name].to_sym, params[:docstring], base_labels)
        counter.increment(base_labels, factor)
        # registers counter
        registry.register(counter)
        
        # push the registry to the gateway
        Prometheus::Client::Push.new(params[:job], params[:instance], pushgateway).add(registry) 
      end
    rescue Exception => e
      raise e
    end
  end

  def self.gauge(params, pushgateway, registry)
    
    begin
      if (params[:base_labels] == nil) 
        base_labels = {}
      else
        base_labels = params[:base_labels]                
      end

      if (params[:value] == nil)
        factor = 1
      else
        factor = params[:value]
      end

      # if gauge exists, it will be updated
      if registry.exist?(params[:name].to_sym)
        gauge = registry.get(params[:name])

        logger.debug "Getting gauge value"
        value = gauge.get(base_labels)
        
        if params[:operation]=='inc'
          value = value.to_i + factor
        else
          value = value.to_i - factor
        end

        logger.debug "Setting gauge value"
        gauge.set(base_labels,value)

        Prometheus::Client::Push.new(params[:job], params[:instance], pushgateway).replace(registry)

      else
        # creates a metric type gauge
        gauge = Prometheus::Client::Gauge.new(params[:name].to_sym, params[:docstring], base_labels)
        gauge.set(base_labels, factor)
        # registers gauge
        registry.register(gauge)
        
        # push the registry to the gateway
        Prometheus::Client::Push.new(params[:job], params[:instance], pushgateway).add(registry) 
      end
    rescue Exception => e
      raise e
    end
  end
  
  put '/kpis/?' do
    original_body = request.body.read
    logger.info "GtkKpi: entered PUT /kpis with original_body=#{original_body}"
    params = JSON.parse(original_body, :symbolize_names => true)
    logger.info "GtkKpi: PUT /kpis with params=#{params}"    
    pushgateway = 'http://'+settings.pushgateway_host+':'+settings.pushgateway_port.to_s

    begin

      if params[:metric_type]=='counter' 
        GtkKpi.counter(params, pushgateway, registry)
      else
        GtkKpi.gauge(params, pushgateway, registry)
      end

      logger.info 'GtkKpi: '+params[:metric_type]+' '+params[:name].to_s+' updated/created'
      halt 201
      
    rescue Exception => e
      logger.debug(e.message)
      logger.debug(e.backtrace.inspect)
      halt 400
    end           
  end

  get '/kpis/?' do
    pushgateway_query = 'http://'+settings.pushgateway_host+':'+settings.pushgateway_port.to_s    
    begin
      if params.empty?
        cmd = 'prom2json '+pushgateway_query+'/metrics | jq -c .'
        res = %x( #{cmd} )

        halt 200, res
        logger.info 'GtkKpi: sonata metrics list retrieved'
      else        
        logger.info "GtkKpi: entered GET /kpis with params=#{params}"        
        pushgateway_query = pushgateway_query + '/metrics | jq -c \'.[]|select(.name=="'+params[:name]+'")\''

        cmd = 'prom2json '+pushgateway_query
        res = %x( #{cmd} )

        logger.info 'GtkKpi: '+params[:name].to_s+' retrieved: '+res.to_json
        halt 200, res.to_json
      end
    rescue Exception => e
      logger.debug(e.message)
      logger.debug(e.backtrace.inspect)
      halt 400
    end
  end
end