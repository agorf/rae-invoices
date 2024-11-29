#!/usr/bin/env ruby

require 'date'
require 'json'
require 'net/http'
require 'nokogiri'
require 'uri'

URL = 'https://invoices.rae.gr/oikiako/'.freeze

COLORS = {
  'blue' => 'μπλε',
  'green' => 'πράσινο',
  'yellow' => 'κίτρινο'
}.freeze

def mwh_to_kwh(mwh)
  (mwh / 1_000).round(5)
end

uri = URI.parse(URL)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
request = Net::HTTP::Get.new(uri.request_uri)
response = http.request(request)
html = response.body
doc = Nokogiri(html)

rows = doc.css('#billing_table tbody tr').reduce([]) do |result, tr|
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
    'Παρατηρήσεις' => tds[10].text.strip
  }
end

print rows.to_json
