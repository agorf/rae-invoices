#!/usr/bin/env ruby

require 'date'
require 'json'
require 'net/http'
require 'nokogiri'
require 'sinatra'
require 'uri'

URL = 'https://energycost.gr/%ce%ba%ce%b1%cf%84%ce%b1%cf%87%cf%89%cf%81%ce%b7%ce%bc%ce%ad%ce%bd%ce%b1-%cf%84%ce%b9%ce%bc%ce%bf%ce%bb%cf%8c%ce%b3%ce%b9%ce%b1-%cf%80%cf%81%ce%bf%ce%bc%ce%ae%ce%b8%ce%b5%ce%b9%ce%b1%cf%82-%ce%b7-3/'.freeze

COLORS = {
  'blue' => 'μπλε',
  'green' => 'πράσινο',
  'yellow' => 'κίτρινο'
}.freeze

CACHE_BASENAME = 'cache-%Y-%m-%d.json'.freeze

configure :development do
  set :cache_path_format, CACHE_BASENAME
  set :logging, Logger::DEBUG
end

configure :production do
  set :cache_path_format, File.join('', 'data', CACHE_BASENAME)
  set :host_authorization, { permitted_hosts: ['.fly.dev'] }
  set :protection, except: [:json_csrf]
end

helpers do
  def production?
    settings.environment == :production
  end

  def fetch_invoice_html
    uri = URI.parse(URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    response.body
  end

  def generate_invoice_rows(html)
    Nokogiri(html).css('#billing_table tbody tr').reduce([]) do |result, tr|
      tds = tr.css('td')

      data =
        tr.attributes.each_with_object({}) do |(name, attr), result|
          next unless name.start_with?('data-')

          result[name.delete_prefix('data-')] = attr.value
        end

      result << {
        'Πάροχος' => tds[0].text.strip,
        'Έτος' => tds[1].text.to_i,
        'Μήνας' => tds[2].text.to_i,
        'Ονομασία Τιμολογίου' => tds[3].text.strip,
        'Τύπος Τιμολογίου' => tds[3]['data-filter-value'].downcase.sub(' τιμολόγιο', ''),
        'Χρώμα Τιμολογίου' => COLORS.fetch(tds[3]['class'].split(/\s+/).find { |c| c.start_with?('color_') }.delete_prefix('color_')),
        'Πάγιο με Έκπτωση με προϋπόθεση (€/μήνα)' => tds[6].text.to_f,
        'Προϋπόθεση Έκπτωσης Παγίου' => tds[7].text.strip,
        'Τελική Τιμή Προμήθειας με Έκπτωση με προϋπόθεση (€/kWh)' => tds[8].text.strip,
        'Προϋπόθεση Έκπτωσης Βασικής Τιμής Προμήθειας' => tds[9].text.strip,
        'Διάρκεια Σύμβασης' => tds[10].text.strip,
        'Παρατηρήσεις' => tds[11].text.strip
      }.merge(data)
    end.sort_by do |entry|
      [
        entry.fetch('Πάροχος'),
        -entry.fetch('Έτος'), # Desc
        -entry.fetch('Μήνας'), # Desc
        entry.fetch('Τύπος Τιμολογίου'),
        entry.fetch('Τελική Τιμή Προμήθειας με Έκπτωση με προϋπόθεση (€/kWh)')
      ]
    end
  end

  def filter_rows(rows, params)
    rows.select do |row|
      select = true

      params.each do |name, value|
        select &= row[name].to_s.downcase.include?(value.downcase)
      end

      select
    end
  end
end

get '/' do
  rows = nil

  cache_path = Time.now.strftime(settings.cache_path_format)
  bust_cache = !production? || !File.exist?(cache_path)

  if bust_cache
    begin
      rows = generate_invoice_rows(fetch_invoice_html)

      if !rows.is_a?(Array) || rows.empty?
        raise 'Failed to fetch rows'
      end
    rescue StandardError
      if production?
        content_type :text, charset: 'utf-8'
        halt 504, 'Bad Gateway'
      else
        raise # Re-raise
      end
    end

    File.open(cache_path, 'w') do |f|
      f << rows.to_json
    end
  end

  content_type :json, charset: 'utf-8'

  rows ||= JSON.parse(File.read(cache_path))
  safe_params = params.slice(*rows.fetch(0).keys)

  filter_rows(rows, safe_params).to_json
end
