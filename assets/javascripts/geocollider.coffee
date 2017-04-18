pretty_csv = (parsed_data) ->
  container = d3.select('#pretty_print')
    .append('table')
      .attr('class','table table-bordered')
    .append('tbody')
      .selectAll('tr')
        .data(parsed_data).enter()
        .append('tr')
      .selectAll('td')
        .data((d) -> d).enter()
        .append('td')
        .text((d) -> d)
  add_column_numbers()

add_column_numbers = ->
  num_columns = $('#pretty_print tr:first-child td').length
  console.log('columns: ' + num_columns)
  tr = $('<tr>')
  for column in [0...num_columns]
    tr.append($('<th>').text(column))
  thead = $('<thead>').append(tr)
  $('#pretty_print table').prepend(thead)

detect_delimiter = (data) ->
  results = Papa.parse(data)
  console.log(results.meta)
  switch results.meta.delimiter
    when ','
      $('#radio_csv').prop('checked',true)
      pretty_csv(d3.csvParseRows(data))
    when "\t"
      $('#radio_tsv').prop('checked',true)
      pretty_csv(d3.tsvParseRows(data))

detect_column_header = ->
  non_digit = /\D/
  has_header = false
  $('#column_specifiers input').each ->
    if $(@).val().match non_digit
      has_header = true
  if ($('#column_headers').prop('checked') == false) && has_header
    $('#column_headers').prop('checked',true)
  else if ($('#column_headers').prop('checked') == true) && not has_header
    $('#column_headers').prop('checked',false)

$(document).ready ->
  console.log('ready')
  console.log($('#csv_preview').text())
  $('#column_specifiers input').change(detect_column_header)
  detect_delimiter($('#csv_preview').text())
