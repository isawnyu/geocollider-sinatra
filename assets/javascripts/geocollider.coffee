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

validate_text_input = (name) ->
  if $("input:text[name = '#{name}']").val()?.length
    $("input:text[name = '#{name}']").parent().addClass('has-success')
    return true
  else
    $("input:text[name = '#{name}']").parent().addClass('has-error')
    $("input:text[name = '#{name}']").prop('placeholder','You must specify a value for this column in order to use the selected matching algorithm.')
    return false

validate_identifier = ->
  return validate_text_input('id')

validate_place = ->
  valid = true
  for place_column in ['lat','lon']
    if !validate_text_input(place_column)
      valid = false
  return valid

validate_name = ->
  return validate_text_input('names')

validate_process_form = ->
  $("input:text").parent().removeClass('has-error')
  $("input:text").parent().removeClass('has-success')
  $("input:text").prop('placeholder','')
  $("input:text").removeProp('placeholder')
  is_valid = validate_identifier()
  switch $("input:radio[name ='algorithm']:checked").val()
    when 'place_name'
      # we need to run both functions to toggle the error state, even if one is false
      is_valid = validate_place() && is_valid
      is_valid = validate_name() && is_valid
      return is_valid
    when 'place'
      return validate_place() && is_valid
    when 'name'
      return validate_name() && is_valid

$(document).ready ->
  console.log('ready')
  $('[data-toggle="tooltip"]').tooltip()
  # enable form submit once input file selected
  $('input:file').change ->
    $('input:submit').prop('disabled', !$(this).val())
  # disable form submit once submit has been pressed
  $('form').submit ->
    if $('#process').length && !validate_process_form()
      return false
    console.log 'disabling submit'
    $('input[type="submit"]').prop('disabled',true)
  if $('#csv_preview').length
    console.log($('#csv_preview').text())
    $('#column_specifiers input').change(detect_column_header)
    $('#column_headers').click ->
      $('#column_specifiers input').unbind('change')
    detect_delimiter($('#csv_preview').text())
