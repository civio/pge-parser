require 'nokogiri'
require 'open-uri'

# Basic parser for any sort of breakdowns that we don't need to parse fully, i.e. pages like [1].
# It supports getting a particular cell by position or text description.
#
# [1]: http://www.sepg.pap.minhap.gob.es/Presup/PGE2014proyecto/MaestroDocumentos/PGE-ROM/doc/HTM/N_14_A_R_6_2_801_1_3.HTM
#
class GenericBreakdown < BaseBreakdown
  def initialize(filename)
    @filename = filename
  end

  def year
    @filename =~ /N_(\d\d)_/
    $1
  end

  def is_final
    @filename =~ /N_(\d\d)_([AE])_/
    return $2 == 'E'
  end

  # Retrieve a cell given its row and column position (-1 means last, as in Ruby)
  def get_item_by_position(row_position, column_position)
    # Get rows in HTML table, skipping header
    rows = doc.css('table.S0ESTILO8 tr')[1..-1] # 2008 onwards (earlier?)

    # Get the row we want
    row = rows[row_position]

    # Return the column we want
    columns = row.css('td').map{|td| td.text.strip}
    columns[column_position]
  end

  # Retrieve the right-most column for the row with the given description
  def get_value_by_description(description, description_position=1)
    # Get rows in HTML table, skipping header
    rows = doc.css('table.S0ESTILO8 tr')[1..-1] # 2008 onwards (earlier?)
    rows.map do |row|
      columns = row.css('td').map{|td| td.text.strip}
      next if columns[description_position]!=description

      # We got to the right row, just return the rightmost column
      return columns[-1]  
    end
  end

  # Let's see how long this lasts :/
  def get_url()
    "http://www.sepg.pap.minhap.gob.es/Presup/PGE20#{year}#{is_final ? 'Ley' : 'Proyecto'}/MaestroDocumentos/PGE-ROM/doc/HTM/#{File.basename(@filename)}"
  end

  private

  def doc
    @doc = Nokogiri::HTML(open(@filename)) if @doc.nil?  # Lazy parsing of doc, only when needed
    @doc
  end
end