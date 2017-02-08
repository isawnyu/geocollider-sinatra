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

$(document).ready ->
  console.log('ready')
  console.log($('#csv_preview').text())
  detect_delimiter($('#csv_preview').text())
