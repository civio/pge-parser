#!/usr/bin/env ruby

require 'nokogiri'
require 'open-uri'
require_relative 'base_breakdown'

# Parser for income breakdowns (Serie Roja / Red books), i.e. pages like [1], [2] or [3].
# Note: the Red and Green books contain, as far as I've seen, the same amount of detail;
# but the Red book includes Social Security data, so that's the one we're using.
#
# [1]: http://www.sepg.pap.minhap.gob.es/Presup/PGE2014Proyecto/MaestroDocumentos/PGE-ROM/doc/HTM/N_14_A_R_2_104_1_2_112_1_1301_1.HTM
# [2]: http://www.sepg.pap.minhap.gob.es/Presup/PGE2014Proyecto/MaestroDocumentos/PGE-ROM/doc/HTM/N_14_A_R_2_105_1_2_160_1_104_1.HTM
# [3]: http://www.sepg.pap.minhap.gob.es/Presup/PGE2014Ley/MaestroDocumentos/PGE-ROM/doc/HTM/N_14_E_R_2_101_1_2_198_1_101_1.HTM
#
class IncomeBreakdown < BaseBreakdown
  attr_reader :year, :entity_type, :section, :entity_id

  def initialize(filename)
    filename =~ INCOME_BKDOWN

    @year = '20'+$1
    @entity_type = $2       # 1 for state, 2-4 for non-state, 5 Social Security
    @section = $3           # Parent section
    @entity_id = $4         # Id of the service/department of the section
    @filename = filename
  end

  # This bit always breaks every year, so I'm using brute force...
  def section_name
    doc.css('td').each do |td|  # Brute force
      return $1 if td.text =~ /^Sección: \d\d (.+)$/
    end
  end

  def entity_name
    doc.css('td').each do |td|  # Brute force
      return $1 if td.text =~ /^(?:Servicio|Organismo|Entidad): \d+ (.+)$/
    end
  end

  # Returns a list of budget items and subtotals. Because of the convoluted format of the 
  # input file, with subtotals being split across two lines, some massaging is needed.
  def income
    merge_subtotals(data_grid, year, section)
  end

  def self.income_breakdown? (filename)
    filename =~ INCOME_BKDOWN
  end

  # Returns the list of institutions/departments described in this breakdown
  def institutions
    [
      { section: section, service: nil, description: section_name },
      { section: section, service: entity_id, description: entity_name },
    ]
  end

  private

  def get_data_rows
    rows = doc.css('table.S0ESTILO8 tr')[1..-1] # 2008 onwards (earlier?)
    if rows.nil?
      # 2014 is the year of the autogenerated messy CSS: we look for a table header
      header = doc.css('table > thead')[0]
      rows = header.parent.css('tr')[1..-1]
    end
    rows
  end

  # Returns a list of column arrays containing all the information in the input data table,
  # basically unmodified (income breakdowns are simpler than expense ones)
  def data_grid
    data_grid = []

    # Iterate through HTML table, skipping header
    get_data_rows.map do |row|
      columns = row.css('td').map{|td| td.text.strip}
      item = {
        :expense_concept => columns[0],
        :description => columns[1],
        :service => entity_id,
        :amount => (columns[2] != '') ? columns[2] : columns[3]
      }
      next if item[:description].empty? # Skip empty lines (no description)
      data_grid << item      
    end
    data_grid
  end

  INCOME_BKDOWN = /N_(\d\d)_[ASE]_R_2_10(\d)_1_2_1(\d\d)_1_1(\d\d+)_1.HTM/  
  
  def doc
    @doc = Nokogiri::HTML(open(@filename)) if @doc.nil?  # Lazy parsing of doc, only when needed
    @doc
  end
end