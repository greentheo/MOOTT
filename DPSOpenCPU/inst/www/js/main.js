var baseDataSessionID;
var dispatchSessionID;

$(document).ready(function() {
    
    
    //hide some divs
    $('#dispatchQueueDiv').hide();
    
    //sample the demo data and store the session for use later ... in production this is actually pulled from the user's
    //data
    var req = ocpu.call("baseData", {pickups: 100}, function(session){
    
      baseDataSessionID = session;
      console.log(session);
      
      //retrieve the returned object async
      session.getObject(function(data){
          
          //fill in the tables with the demoData (or in a production setting, the modified user data...we wont need R here)
          makeTables($('#baseStationsTable tbody'), ["station", "lat", "long"], data.baseStations);
          makeTables($('#trucksStationsTable tbody'), ["truckNumber", "station"], data.trucksStations);
          makeTables($('#dropOffPointsTable tbody'), ["dropOff", "lat", "long"], data.dropOffPoints);
          makeTables($('#trucksInfoTable tbody'), ["truckNumber", "available", "avgSpeed"], data.trucksInfo);
          
          //tableFy the tables now that there's data for them.
          tableFy($('#baseStationsTable'));
          tableFy($('#trucksStationsTable'));
          tableFy($('#trucksInfoTable'));
          tableFy($('#dropOffPointsTable'));
          
          dispatchQueue(baseDataSessionID);
          
          ///do a promise fulfilled here and tablefy the data (so that you only do it once)
          
          
      });
      
    })
  
    
} );

//do the dispatch and fill in the table for the dispatch Queue
dispatchQueue = function(baseDataSession){
  
          var req = ocpu.call('dispatchQueue', 
                              {data: baseDataSession, windowsAhead: 12}, 
                              function(session){
                                  dispatchSessionID=session;
                                  session.getObject(function(data){
                                    console.log(data);
                                    makeTables($('#dispatchQueue tbody'), 
                                      ["truckAssigned","WELL_NAME", "COMPANY_NA", "pickupdate","ETAPickup","type"], 
                                      data.dispatch);
                                      tableFy($('#dispatchQueue'));
                                      $('#waitingDispatchQueue').hide(800);
                                      $('#dispatchQueueDiv').show(800);
                                  });
                              });         
}
makeTables = function(tbody, props, data){
          $.each(data, function(i, dataPoint) {
            var tr = $('<tr>');
            $.each(props, function(i, prop) {
              $('<td>').html(dataPoint[prop]).appendTo(tr);  
            });
            tbody.append(tr);
          })
}

tableFy = function(table){
  //tableify the dispatch queue and all the other tables
    table.DataTable();
  
}