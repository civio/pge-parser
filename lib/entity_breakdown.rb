#!/usr/bin/env ruby

require 'nokogiri'
require 'open-uri'
require_relative 'base_breakdown'

# Parser for entity expense breakdowns (Serie Verde / Green books), i.e. pages like [1].
#
# About the entity type:
#   - State: ministries and their parts (departments, for example) are marked as type 1
#   - Non-state: autonomus bodies (type 2), dependent agencies (3) and other bodies (4)
#
# [1]: http://www.sepg.pap.minhap.gob.es/Presup/PGE2013Ley/MaestroDocumentos/PGE-ROM/doc/HTM/N_13_E_V_1_101_1_1_2_2_118_1_2.HTM
#
class EntityBreakdown < BaseBreakdown
  attr_reader :year, :section, :entity, :filename

  def initialize(filename)
    # The filename structure changed in 2012, so we need to start by finding out the year
    @year = EntityBreakdown.get_year(filename)
    
    # Once the year is known, we can extract additional details from the filename
    @filename = filename
    filename =~ EntityBreakdown.get_expense_breakdown_filename_regex(@year, is_state_entity?)
    @section = $3                           # Parent section
    @entity = $4 unless is_state_entity?    # Id of the non-state entity

    # Not used anymore, but since it was implemented already...
    # (Doesn't combine well with ProgrammeBreakdown, with different entities sitting
    # in the same page.)
    # @entity_type = $2                     # Always 1 for state entities, 2-4 for non-state
  end
  
  # We know whether an entity is state or not by trying to match the filename against
  # the regex for state entities. If it works, we were right.
  def is_state_entity?
    @filename =~ EntityBreakdown.get_expense_breakdown_filename_regex(@year, true)    
  end
  
  # This bit always breaks every year, so I'm using brute force...
  def name
    # Note: the name may include accented characters, so '\w' doesn't work in regex
    if is_state_entity?
      doc.css('td').each do |td|  # Brute force
        return $1 if td.text =~ /^Sección: \d\d (.+)$/
      end
    else
      doc.css('td').each do |td|  # Brute force
        return $1 if td.text =~ /^Organismo: \d\d\d (.+)$/
      end
    end
  end
  
  def children
    is_state_entity? ?
      expenses.map {|row| {:id=>row[:service], :name=>row[:description]} if row[:programme].empty? }.compact :
      [{:id => @entity, :name => name}]
  end
  
  # XXX: Refactor all this messy filename handling logic! :/
  def self.entity_breakdown? (filename)
    year = EntityBreakdown.get_year(filename)
    filename =~ get_expense_breakdown_filename_regex(year, true) || filename =~ get_expense_breakdown_filename_regex(year, false)
  end

  # Returns a list of budget items and subtotals. Because of the convoluted format of the 
  # input file, with subtotals being split across two lines, some massaging is needed.
  def expenses
    # The total amounts for service/programme/chapter headings is shown when the subtotal is closed,
    # not opened, so we need to keep track of the open ones, and print them when closed.
    # Note: there is an unmatched closing amount, without an opening subtotal header, at the end
    # of the page, containing the amount for the whole section/entity, so we don't start with
    # an empty vector here, we add the 'missing' opening line
    open_subtotals = [{
      year: year,
      section: section,
      service: is_state_entity? ? '' : entity,
      description: name
    }]

    merge_subtotals(data_grid, year, section, open_subtotals)
  end

  private  

  def get_data_rows
    rows = doc.css('table.S0ESTILO9 tr')[1..-1]               # 2008 (and earlier?)
    rows = doc.css('table.S0ESTILO8 tr')[1..-1] if rows.nil?  # 2009 onwards
    if rows.nil?
      # 2014 is the year of the autogenerated messy CSS: we look for a table header
      header = doc.css('table > thead')[0]
      rows = header.parent.css('tr')[1..-1]
    end
    rows
  end

  # Returns a list of column arrays containing all the information in the input data table,
  # basically unmodified, apart from two columns (service, programme) filled in, since
  # in the input grid they are only shown when they change
  def data_grid
    # Breakdowns for state entities contain many sub-entities, whose id is contained in the rows.
    # Breakdowns for non-state entities apply to only one child entity, which we know in advance.
    last_service = is_state_entity? ? '' : entity
    last_programme = ''
    
    # Iterate through HTML table, skipping header
    data_grid = []
    get_data_rows.each do |row|
      columns = row.css('td').map{|td| td.text.strip}
      columns.shift if ['2012', '2013', '2014', '2015', '2016', '2017'].include? year
      columns.insert(0,'') unless is_state_entity? # They lack the first column, 'service'

      # There's a typo in 2017P that threatens to screw up our unfolding of conflicting ids
      # later on, so we make sure the description is correct. If more typos were found in the
      # future, we'd need to have a more general typo-fixing mechanism, but for now will do.
      description = columns[3]
      if description == 'Inversión nueva en infraestruras y bienes destinados al uso general'
        description = 'Inversión nueva en infraestructuras y bienes destinados al uso general'
      end

      item = {
        :service => columns[0], 
        :programme => columns[1], 
        :expense_concept => columns[2], 
        :description => description,
        :amount => (columns[4] != '') ? columns[4] : columns[5] 
      }
      next if item[:description].empty?  # Skip empty lines (no description)

      # Fill blanks in row and save result
      if item[:service].empty?
        item[:service] = last_service
      else
        last_service = item[:service]
        last_programme = ''
      end
      
      if item[:programme].empty?
        item[:programme] = last_programme
      else
        last_programme = item[:programme] 
      end
      
      data_grid << item      
    end
    data_grid
  end

  def self.get_year(filename)
    filename =~ /N_(\d\d)_[ASE]/
    return '20'+$1
  end
  
  def self.get_expense_breakdown_filename_regex(year, is_state_entity)
    if year == '2017'
      # 2017P grouped the agencies and other bodies kind of a 'level down' in the hierarchy,
      # so the filenames are affected. Since the regex catches all those from 2012-2016
      # we could replace the old one, but didn't have to test the change when parsing
      # the new data, so this was safer.
      is_state_entity ?
        /N_(\d\d)_[AE]_V_1_10([1234])_1_1_2_2_[1234](\d\d)_1_2.HTM/ :
        /N_(\d\d)_[AE]_V_1_(?:2_)?10([1234])_2_1_[1234](\d\d)_1_1(\d\d\d)_2_2_1.HTM/;
    elsif ['2012', '2013', '2014', '2015', '2016'].include? year
      is_state_entity ? 
        /N_(\d\d)_[AE]_V_1_10([1234])_1_1_2_2_[1234](\d\d)_1_2.HTM/ :
        /N_(\d\d)_[AE]_V_1_10([1234])_2_1_[1234](\d\d)_1_1(\d\d\d)_2_2_1.HTM/;
    else
      is_state_entity ? 
        /N_(\d\d)_[ASE]_V_1_10([1234])_2_2_2_1(\d\d)_1_[12]_1.HTM/ :
        /N_(\d\d)_[ASE]_V_1_10([1234])_2_2_2_1(\d\d)_1_[12]_1(\d\d\d)_1.HTM/;
    end
  end

  def doc
    @doc = Nokogiri::HTML(open(@filename)) if @doc.nil?  # Lazy parsing of doc, only when needed
    @doc
  end
end