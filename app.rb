#!/usr/bin/env ruby

require 'date'
require 'json'
require 'net/http'
require 'nokogiri'
require 'sinatra'
require 'uri'

URL = 'https://invoices.rae.gr/%ce%ba%ce%b1%cf%84%ce%b1%cf%87%cf%89%cf%81%ce%b7%ce%bc%ce%ad%ce%bd%ce%b1-%cf%84%ce%b9%ce%bc%ce%bf%ce%bb%cf%8c%ce%b3%ce%b9%ce%b1-%cf%80%cf%81%ce%bf%ce%bc%ce%ae%ce%b8%ce%b5%ce%b9%ce%b1%cf%82-%ce%b7-3/'.freeze

COLORS = {
  'blue' => 'μπλε',
  'green' => 'πράσινο',
  'yellow' => 'κίτρινο'
}.freeze

configure :development do
  set :cache_path, File.join('cache.json')
  set :logging, Logger::DEBUG
end

configure :production do
  set :cache_path, File.join('', 'data', 'cache.json')
  set :host_authorization, { permitted_hosts: ['.fly.dev'] }
  set :protection, except: [:json_csrf]
end

helpers do
  def mwh_to_kwh(mwh)
    (mwh / 1_000).round(8)
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

      result << {
        'Πάροχος' => tds[0].text.strip,
        'Έτος' => tds[1].text.to_i,
        'Μήνας' => tds[2].text.to_i,
        'Ονομασία Τιμολογίου' => tds[3].text.strip,
        'Τύπος Τιμολογίου' => tds[3]['data-filter-value'].downcase.sub(' τιμολόγιο', ''),
        'Χρώμα Τιμολογίου' => COLORS.fetch(tds[3]['class'].split(/\s+/).find { |c| c.start_with?('color_') }.delete_prefix('color_')),
        'Πάγιο με Έκπτωση με προϋπόθεση (€/μήνα)' => tds[6].text.to_f,
        'Προϋπόθεση Έκπτωσης Παγίου' => tds[7].text.strip,
        'Τελική Τιμή Προμήθειας με Έκπτωση με προϋπόθεση (€/kWh)' => mwh_to_kwh(tds[8].text.strip.to_f),
        'Τελική Τιμή Προμήθειας με Έκπτωση με προϋπόθεση (€/MWh)' => tds[8].text.strip.to_f,
        'Προϋπόθεση Έκπτωσης Βασικής Τιμής Προμήθειας' => tds[9].text.strip,
        'Διάρκεια Σύμβασης' => tds[10].text.strip,
        'Παρατηρήσεις' => tds[11].text.strip
      }
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

  if !File.exist?(settings.cache_path) || File.mtime(settings.cache_path) < Time.now - 24 * 60 * 60
    begin
      rows = generate_invoice_rows(fetch_invoice_html)

      if !rows.is_a?(Array) || rows.empty?
        raise 'Failed to fetch rows'
      end
    rescue
      halt 504, 'Bad Gateway'
    end

    File.open(settings.cache_path, 'w') do |f|
      f << rows.to_json
    end
  end

  content_type :json, charset: 'utf-8'

  rows ||= JSON.load(File.open(settings.cache_path))
  safe_params = params.slice(*rows.fetch(0).keys)

  filter_rows(rows, safe_params).to_json
end
