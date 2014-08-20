require 'rubygems'
require 'mechanize'
require 'json'
require 'json/add/core'

require_relative 'cricos_scrape/railtie' if defined?(Rails)

require_relative 'cricos_scrape/json_struct'
require_relative 'cricos_scrape/json_file_store'
require_relative 'cricos_scrape/address'
require_relative 'cricos_scrape/institution'
require_relative 'cricos_scrape/location'
require_relative 'cricos_scrape/course'
require_relative 'cricos_scrape/contact'
require_relative 'cricos_scrape/contact_officer'

require_relative 'cricos_scrape/course_importer'
require_relative 'cricos_scrape/institution_importer'
require_relative 'cricos_scrape/contact_importer'

require_relative 'cricos_scrape/bulk_import_institutions'
require_relative 'cricos_scrape/bulk_import_courses'
require_relative 'cricos_scrape/bulk_import_contacts'