function showToField() {
  $('span.how').hide();
  $('span.'+$('#how').val()).show();
}
google.load("jquery", "1.3.2");
google.setOnLoadCallback(function() { // instead of $(document).ready()
  showToField();
  $('#how').change(showToField);
});
