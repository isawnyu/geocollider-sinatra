detect_delimiter = (data) ->
  results = Papa.parse(data)
  console.log(results.meta)
  switch results.meta.delimiter
    when ','
      $('#radio_csv').prop('checked',true)
    when "\t"
      $('#radio_tsv').prop('checked',true)

$(document).ready ->
  console.log('ready')
  console.log($('#csv_preview').text())
  detect_delimiter($('#csv_preview').text())
