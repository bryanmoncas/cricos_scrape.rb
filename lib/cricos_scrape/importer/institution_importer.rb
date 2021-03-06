require 'cricos_scrape/entities/institution'
require 'cricos_scrape/entities/location'
require 'cricos_scrape/entities/contact_officer'

module CricosScrape
  class InstitutionImporter

    INSTITUTION_URL = 'http://cricos.education.gov.au/Institution/InstitutionDetailsOnePage.aspx'

    def initialize(agent, **params)
      @agent = agent
      @provider_id = params.fetch(:provider_id)
      @page = agent.get(url)
    end

    def run
      return if institution_not_found?

      institution                  = Institution.new
      institution.provider_id      = provider_id
      institution.provider_code    = find_provider_code
      institution.trading_name     = find_trading_name
      institution.name             = find_name
      institution.type             = find_type
      institution.total_capacity   = find_total_capacity
      institution.website          = find_website
      institution.postal_address   = find_postal_address
      institution.locations        = find_location if location_found?
      institution.contact_officers = find_contact_officers

      institution
    end

    private

    attr_reader :agent, :provider_id, :page

    def url
      "#{INSTITUTION_URL}?ProviderID=#{provider_id}"
    end

    def find_value_of_field(field)
      field.nil? ? nil : field.text.strip
    end

    def find_provider_code
      field = @page.at('#institutionDetails_lblProviderCode')
      find_value_of_field(field)
    end

    def find_trading_name
      field = @page.at('#institutionDetails_lblInstitutionTradingName')
      find_value_of_field(field)
    end

    def find_name
      field = @page.at('#institutionDetails_lblInstitutionName')
      find_value_of_field(field)
    end

    def find_type
      field = @page.at('#institutionDetails_lblInstitutionType')
      find_value_of_field(field)
    end

    def find_total_capacity
      field = @page.at('#institutionDetails_lblLocationCapacity')

      capacity = find_value_of_field(field)
      capacity = is_number?(capacity) ? capacity.to_i : nil
      capacity
    end

    def is_number?(text)
      text =~ /\d/
    end

    def find_website
      field = @page.at('#institutionDetails_hplInstitutionWebAddress')
      find_value_of_field(field)
    end

    def find_postal_address
      post_address_node = @page.at('#institutionDetails_lblInstitutionPostalAddress')

      if post_address_node
        address_lines = post_address_node.children.select { |node| node.is_a?(Nokogiri::XML::Text) }.map { |node| find_value_of_field(node) }
        address_lines.join("\n")
      end
    end

    # there is no record not found page
    # instead a search page is returned
    def institution_not_found?
      @page.body.include?('The Provider ID entered is invalid - please try another.')
    end

    def location_found?
      !@page.body.include?('No locations were found for the selected institution.')
    end

    def find_location
      locations = []

      if location_results_paginated?
        for page_number in 1..total_pages
          jump_to_page(page_number)
          locations += fetch_locations_from_current_page
        end
      else
        locations += fetch_locations_from_current_page
      end

      locations
    end

    def pagination
      @page.at('#locationList_gridSearchResults .gridPager')
    end

    def location_results_paginated?
      !!pagination
    end

    def total_pages
      pagination.children[1].text.strip[/^Page [0-9]+ of ([0-9]+).*/, 1].to_i
    end

    def current_pagination_page
      pagination.children[1].text.strip[/^Page ([0-9]+) of [0-9]+.*/, 1].to_i
    end

    def jump_to_page(page_number)
      return @page if page_number == current_pagination_page

      hidden_form = @page.form_with id: 'Form1'
      hidden_form['__EVENTTARGET'] = 'locationList$gridSearchResults'
      hidden_form['__EVENTARGUMENT'] = "Page$#{page_number}"
      begin
       @page = hidden_form.submit(nil, {'action' => 'change-location-page'})
      rescue Mechanize::ResponseCodeError
        sleep 5
        jump_to_page(page_number)
      end
    end

    def get_location_id(row_index)
      hidden_form = @page.form_with id: 'Form1'
      hidden_form['__EVENTTARGET'] = 'locationList$gridSearchResults'
      hidden_form['__EVENTARGUMENT'] = "click-#{row_index-3}"

      begin
       course_page = hidden_form.submit(nil, {'action' => 'get-location-id'})
      rescue Mechanize::ResponseCodeError
        sleep 5
        get_location_id(row_index)
      end

      course_page.uri.to_s[/LocationID=([0-9]+)/, 1]
    end

    def fetch_locations_from_current_page
      locations_of_page = []

      # location_list is table contains locations in current page
      if search_results_node = @page.at('#locationList_gridSearchResults')
        location_list = search_results_node.children

        excess_row_at_the_end_table = location_results_paginated? ? 3 : 2
        start_location_row = 3
        end_location_row = location_list.count - excess_row_at_the_end_table

        for i in start_location_row..end_location_row
          location_row = location_list[i].children

          location_obj                   = Location.new
          location_obj.location_id       = get_location_id(i)
          location_obj.name              = find_value_of_field(location_row[1])
          location_obj.state             = find_value_of_field(location_row[2])
          location_obj.number_of_courses = find_value_of_field(location_row[3])

          locations_of_page << location_obj
        end
      end

      locations_of_page
    end

    def find_contact_officers
      contact_officers = []

      contact_officers_list = @page.search('//div[starts-with(@id, "contactDetails_pnl")]')

      contact_officers_list.each do |contact_officer|
        @contact_officer_area = contact_officer
        @contact_officer_table = @contact_officer_area.at('table').children

        if contains_contact_details_grid?
          contact_officers += find_contact_officer_grid
        else
          contact_officers << find_contact_officer
        end
      end

      contact_officers
    end

    def find_contact_officer_grid
      contact_officers = []

      excess_row_at_the_end_table = 2
      data_row_start = 3
      data_row_end = @contact_officer_table.count - excess_row_at_the_end_table

      for i in data_row_start..data_row_end
        contact_row = @contact_officer_table[i].children

        contact       = ContactOfficer.new
        contact.role  = find_contact_officer_role
        contact.name  = find_value_of_field(contact_row[1])
        contact.phone = find_value_of_field(contact_row[2])
        contact.fax   = find_value_of_field(contact_row[3])
        contact.email = find_value_of_field(contact_row[4])

        contact_officers << contact
      end

      contact_officers
    end

    def find_contact_officer
      contact       = ContactOfficer.new
      contact.role  = find_contact_officer_role
      contact.name  = find_contact_officer_name
      contact.title = find_contact_officer_title
      contact.phone = find_contact_officer_phone
      contact.fax   = find_contact_officer_fax
      contact.email = find_contact_officer_email

      contact
    end

    def find_contact_officer_role
      row = @contact_officer_area.children
      find_value_of_field(row[1]).sub(':', '')
    end

    def find_contact_officer_name
      row = @contact_officer_table[1].children
      find_value_of_field(row[3])
    end

    def find_contact_officer_title
      row = @contact_officer_table[3].children
      find_value_of_field(row[3])
    end

    def find_contact_officer_phone
      row = @contact_officer_table[5].children
      find_value_of_field(row[3])
    end

    def find_contact_officer_fax
      row = @contact_officer_table[7].children
      find_value_of_field(row[3])
    end

    def find_contact_officer_email
      row = @contact_officer_table[9]
      find_value_of_field(row.children[3]) unless row.nil?
    end

    def contains_contact_details_grid?
      contact_officer_area_css_id = @contact_officer_area.attributes['id'].text
      @page.search("//*[@id='#{contact_officer_area_css_id}']/div/table[starts-with(@id, 'contactDetails_grid')]").any?
    end

  end
end
