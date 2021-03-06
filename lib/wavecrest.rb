require 'rest_client'
require 'net/http'
require 'json'
require "wavecrest/version"
require "wavecrest/configuration"
require "wavecrest/exception"

module Wavecrest
  # autoload :Wavecrest, 'wavecrest'
  class << self
    attr_accessor :configuration
  end


  def self.configure
    self.configuration ||= Wavecrest::Configuration.new
    yield(configuration)
  end

  def self.countries
    %w(
    AX AL AD AI AG AR AM AW AU AT AZ BS BH BB BY BE BZ BM BT BQ BA BR BN BG
    CA KY CL CN CO

    CR HR CY CZ DK DM DO EC SV EE FK FO FI FR GF GE DE GI GR
    GL GD GP GT GG GY HK HU IS ID IE IM IL IT JM JP JE JO KZ KR QZ KW LV LI LT

    LU MK MY MV MT MQ MU MX MD MC MN ME MA NP NL NZ NI NO OM PA PG PY PE PH
    PL PT QA RO RU BL KN LC MF VC SM SA RS SC SG SX SK SI SB ZA

    ES SR SE CH TW TH TT TR TC UA AE GB UY VG
    )
  end

  def self.card_status
    [
        "READY_TO_ACTIVE",
        "READY_FOR_AE",
        "Intermediate_Assignment",
        "ACTIVE",
        "EXPIRED",
        "LOST",
        "STOLEN",
        "DESTROYED",
        "DAMAGED",
        "DORMANT",
        "CLOSED",
        "REPLACED",
        "SUSPENDED",
        "SACTIVE",
        "REVOKED",
        "CCLOSED",
        "MBCLOSED",
        "FRAUD",
        "PFRAUD",
        "CHARGEOFF",
        "DECEASED",
        "WARNING",
        "MUCLOSED",
        "VOID",
        "NONRENEWAL",
        "LAST_STMT",
        "INACTIVE",
        "BLOCKED",
        "DEACTIVATE",
        "ENABLE",
        "UNSUSPEND"
    ]
  end

  def self.auth_token
    ENV['_WAVECREST_AUTH_TOKEN']
  end

  def self.auth_need?
    auth_token_issied_at = Time.at ENV['_WAVECREST_AUTH_TOKEN_ISSUED'].to_i
    # puts "WC current auth token: #{auth_token}, issued: #{auth_token_issied_at}"
    return true unless auth_token
    return true if auth_token_issied_at.kind_of?(Time) and auth_token_issied_at + 1.hour < Time.now
  end

  def self.auth
    url = URI("#{configuration.endpoint}/v3/services/authenticator")

    if configuration.proxy
      proxy_uri = URI.parse(configuration.proxy)
      http = Net::HTTP.new(url.host, url.port, proxy_uri.host, proxy_uri.port, proxy_uri.user, proxy_uri.password)
    else
      http = Net::HTTP.new(url.host, url.port)
    end

    if url.scheme == 'https'
      http.use_ssl = true
    end

    request = Net::HTTP::Post.new(url.request_uri)
    request.add_field('Content-Type', 'application/json')
    request.add_field('Accept', 'application/json')
    request.add_field('DeveloperId', configuration.user)
    request.add_field('DeveloperPassword', configuration.password)
    request.add_field('X-Method-Override', 'login')

    response = http.request(request)
    data = JSON.parse response.body
    ENV['_WAVECREST_AUTH_TOKEN'] = data["token"]
    ENV['_WAVECREST_AUTH_TOKEN_ISSUED'] = Time.now.to_i.to_s
  end


  def self.send_request method, path, params={}
    auth if auth_need?

    # path must begin with slash
    url = URI(configuration.endpoint + "/v3/services" + path)

    # Build the connection
    if configuration.proxy
      proxy_uri = URI.parse(configuration.proxy)
      http = Net::HTTP.new(url.host, url.port, proxy_uri.host, proxy_uri.port, proxy_uri.user, proxy_uri.password)
    else
      http = Net::HTTP.new(url.host, url.port)
    end

    if url.scheme == 'https'
      http.use_ssl = true
    end

    if method == :get
      request = Net::HTTP::Get.new(url.request_uri)
    elsif method == :post
      request = Net::HTTP::Post.new(url.request_uri)
    elsif method == :delete
      request = Net::HTTP::Delete.new(url.request_uri)
    elsif method == :put
      request = Net::HTTP::Put.new(url.request_uri)
    else
      raise 'Unsupported request method'
    end

    unless method == :get
      request.body = params.to_json
    end

    request.add_field('Content-Type', 'application/json')
    request.add_field('Accept', 'application/json')
    request.add_field('DeveloperId', configuration.user)
    request.add_field('DeveloperPassword', configuration.password)
    request.add_field('AuthenticationToken', auth_token)

    begin
      response = http.request(request)
      JSON.parse response.body
    rescue => e
      # puts e.message, e.response
      return JSON.parse e.response
    end
  end



  def self.request_card(params)
    default_params = {
        "cardProgramId" => "0",
        "Businesspartnerid" => configuration.partner_id,
        "channelType" => "1",
        "localeTime" => Time.now
    }
    payload = default_params.merge params
    send_request :post, "/cards", payload
  end

  def self.load_money(user_id, proxy, params= {})
    default_params = {
        "channelType" => "1",
        "agentId" => configuration.partner_id
    }
    payload = default_params.merge params
    send_request :post, "/users/#{user_id}/cards/#{proxy}/load", payload
  end

  def self.balance user_id, proxy
    resp = send_request :get, "/users/#{user_id}/cards/#{proxy}/balance"
    resp['avlBal'].to_i
  end


  def self.details user_id, proxy
    send_request :get, "/users/#{user_id}/cards/#{proxy}/carddetails"
  end

  def self.transactions user_id, proxy, count: 100, offset: 0
    payload = {txnCount: count, offset: offset}
    send_request :post, "/users/#{user_id}/cards/#{proxy}/transactions", payload
  end

  def self.prefunding_account(currency='EUR')
    send_request :post, "/businesspartners/#{configuration.partner_id}/balance", currency: currency
  end

  def self.prefunding_accounts
    resp = send_request :get, "/businesspartners/#{configuration.partner_id}/txnaccounts"
    resp['txnAccountList']
  end

  def self.prefunding_transactions(account_id)
    send_request :get, "/businesspartners/#{configuration.partner_id}/transactionaccounts/#{account_id}/transfers"
  end

  def self.activate user_id, proxy, payload
    send_request :post, "/users/#{user_id}/cards/#{proxy}/activate", payload
  end

  def self.cardholder user_id, proxy
    send_request :get, "/users/#{user_id}/cards/#{proxy}/cardholderinfo"
  end

  def self.upload_docs user_id, payload
    send_request :post, "/users/#{user_id}/kyc", payload
  end

  def self.update_status user_id, proxy, payload
    send_request :post, "/users/#{user_id}/cards/#{proxy}/status", payload
  end

  def self.user_details user_id
    send_request :get, "/users/#{user_id}"
  end

  def self.replace user_id, proxy, payload
    send_request :post, "/users/#{user_id}/cards/#{proxy}/replace", payload
  end

  def self.transfer user_id, proxy, payload
    send_request :post, "/cards/#{proxy}/transfers", payload
  end

  def self.change_user_password user_id, payload
    send_request :post, "/users/#{user_id}/createPassword", payload
  end

  def self.update_card user_id, proxy, payload
    send_request :post, "/users/#{user_id}/cards/#{proxy}/", payload
  end

  def self.card_unload user_id, proxy, payload
    send_request :post, "/users/#{user_id}/cards/#{proxy}/purchase", payload
  end
end
