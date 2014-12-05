var sessionID;

$(document).ready(function() {
    
    //sample the demo data and store the session for use later ... in production this is actually pulled from the user's
    //data
    var req = ocpu.call("baseData", {pickups: 100}, function(session){
    
      sessionID = session;
      console.log(session);
      
      //retrieve the returned object async
      session.getObject(function(data){
        
          //fill in the tables with the demoData (or in a production setting, the modified user data...we wont need R here)
          makeTables($('#baseStationsTable tbody'), ["station", "lat", "long"], data.baseStations);
          makeTables($('#trucksStationsTable tbody'), ["truckNumber", "station"], data.trucksStations);
          makeTables($('#dropOffPointsTable tbody'), ["dropOff", "lat", "long"], data.dropOffPoints);
          makeTables($('#trucksInfoTable tbody'), ["truckNumber", "available", "avgSpeed"], data.trucksInfo);
          
          //tableFy all of the data once it's been inserted into the tables
          tableFy();
      });
      
    })
    
    //TODO - include the plugins from https://code.google.com/p/jquery-datatables-editable/ to make these tables editable and push the changes back to a database
    
    
    
    
    //Now that the UI is loaded, do the dispatch, when it's done enable upload and modification buttons
    
    //var req = ocpu.call('dispatch', ....)
    
    //assign functionality to each of the buttons on the UI (like upload a spreadsheet, download a spreadsheet, calculate new dispatch... etc.)
    
    
} );

makeTables = function(tbody, props, data){
          $.each(data, function(i, dataPoint) {
            var tr = $('<tr>');
            $.each(props, function(i, prop) {
              $('<td>').html(dataPoint[prop]).appendTo(tr);  
            });
            tbody.append(tr);
          })
}

tableFy = function(){
  //tableify the dispatch queue and all the other tables
    $('#dispatchQueue').DataTable();
    
    //System Page
    $('#baseStationsTable').DataTable();
    $('#trucksStationsTable').DataTable();
    $('#trucksInfoTable').DataTable();
    $('#dropOffPointsTable').DataTable();
  
}