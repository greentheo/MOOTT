RDataModel = Backbone.Model.extend({
        defaults:{
          baseDataSessionID: null,
          dispatchSessionID: null,
          optBaseStationID: null,
          dispatchSummariesID: null,
          dispatchMetricsID: null,
          userModel: null
        },
        initialize: function(){
          
            //if the user model (and the data pulled back from the server) is null then generate data
            
            //else use the user data to generate the data
            getDemoData(this);
          
            this.on("change:baseDataSessionID", function(model){
                dispatchQueue(model.get('baseDataSessionID'), this);
                optBaseStations(model.get('baseDataSessionID'), this);
                
            });
            
            this.on('change:dispatchSessionID', function(model){
            
            });
        },
        setBaseDataSessionID: function(session){
          this.set({baseDataSessionID: session});
        },
        setDispatchSessionID: function(session){
          this.set({dispatchSessionID: session});
        },
        setoptBaseStationID: function(session){
          this.set({optBaseStationID: session});
        },
        setDispatchSummariesID: function(session){
          this.set({dispatchSummariesID: session});
        },
        setDispatchMetricsID: function(session){
          this.set({dispatchMetricsID: session});
        },
        setUserModel: function(userModel){
          this.set({userModel: userModel});
        },
        
    });

UserModel = Backbone.Model.extend({
        defaults:{
          userName: null,
          trucksInfo: null,
          baseStations: null,
          trucksStations: null,
          dropOffPoints: null,
          pickups: null,
          dispatchQueue: null
        },
        initialize: function(){
            
        }
        
    });

var User;
var RDatas;
//var editor;

$(document).ready(function() {
    
    User = new UserModel();  // when there's an actual user, we'll pull their details out of the node.js server
    RDatas = new RDataModel({userModel: User}); //when there's an actual user, we'll pass the user into the RDatas model and instead of pseudo data we'll get real dispatch data back.
    
    $('.dataDiv').hide();
    $('#dispatchQueueSubDiv').hide();
    $('#sysInfoDiv').hide();
    
    
    // This must be a hyperlink
    $(".export").on('click', function (event) {
        // CSV
        console.log(this);
        exportTableToCSV.apply(this, [$('#'+this.getAttribute('datatableid')), this.getAttribute('datatableid')+'_export.csv']);
        
        // IF CSV, don't do event.preventDefault() or return false
        // We actually need this to be a typical hyperlink
    });
    
    
    
} );
getDemoData = function(RDatasModel){
  var req = ocpu.call("baseData", {pickups:1000, numTrucks:10, numStations:3, numDropOffs:10}, function(session){
            $('#waitingSysInfo').show(800);
            $('#sysInfoDiv').hide(800);
            console.log('getting demo Data');
            RDatasModel.setBaseDataSessionID(session);
            console.log(session);
            
            //retrieve the returned object async
            session.getObject(function(data){
                
                //fill in the tables with the demoData (or in a production setting, the modified user data...we wont need R here)
                //makeTables($('#baseStationsTable tbody'), ["station", "lat", "long"], data.baseStations);
                makeTables($('#trucksStationsTable tbody'), ["truckNumber", "station"], data.trucksStations);
                makeTables($('#dropOffPointsTable tbody'), ["dropOff", "lat", "long"], data.dropOffPoints);
                makeTables($('#trucksInfoTable tbody'), ["truckNumber", "available", "avgSpeed"], data.trucksInfo);
                makeTables($('#pickupPointsTable tbody'), ["WELL_NAME", "COMPANY_NA", "SURF_LAT", "SURF_LONG"], data.pickups);
                
                
                //tableFy the tables now that there's data for them.
                tableFyEditable('#baseStationsTable', RDatasModel.get('baseDataSessionID'), 'baseStations', 
                  [{data: "station"}, {data:"lat"}, {data:"long"}],
                  [{label: "Station", name: "station"}, {label: "Lat", name: "lat"}, {label: "Long", name: "long"}]);
                  
                tableFy($('#trucksStationsTable'));
                tableFy($('#trucksInfoTable'));
                tableFy($('#dropOffPointsTable'));
                tableFy($('#pickupPointsTable'));
                
                $('#waitingSysInfo').hide(800);
                $('#sysInfoDiv').show(800);
            });
            
          });
  
}

optBaseStations = function(baseDataSession, RDatasModel){
  var req = ocpu.call('optimizeBaseStations', {baseData: baseDataSession}, function(session){
    RDatasModel.setoptBaseStationID(session);
    
    session.getObject(function(data){
      makeTables($('#baseStationOptTable'), 
        ["station", "lat", "long", "newLat", "newLong", "distanceAway", "improvement", "medOldDist", "medNewDist"],
        data.opt);
        
      tableFy($('#baseStationOptTable'));
      
    });
  });
}

//do the dispatch and fill in the table for the dispatch Queue
dispatchQueue = function(baseDataSession, RDatasModel){
  console.log('dispatching queue...')
          $('.dataDiv').hide(800);
          $('.waitingDispatch').show(800);
          
          var req = ocpu.call('dispatchQueue', 
                              {data: baseDataSession, windowsAhead: 12}, 
                              function(session){
                                  //dispatchSessionID=session;
                                  RDatasModel.setDispatchSessionID(session);
                                  
                                  session.getObject(function(data){
                                    console.log(data);
                                    makeTablesWLinks($('#dispatchQueue tbody'), 
                                      "dispatchQueueSubDiv",
                                      ["truckAssigned","WELL_NAME", "COMPANY_NA", "pickupdate","ETAPickup","assignedDropOff","type"],
                                      ["truck","pickup", "company", null, null, "dropOff",null],
                                      data.dispatch);
                                    makeTables($('#pickupDropOffsTable tbody'), 
                                      ["WELL_NAME","dropOff", "dropOffDist"], 
                                      data.pickupDropOffPairs); 
                                    makeTables($('#pickupBaseStationsTable tbody'), 
                                      ["WELL_NAME","station", "stationDist"], 
                                      data.pickupDropOffPairs);
                                    
                                    tableFy($('#dispatchQueue'));
                                    tableFy($('#pickupDropOffsTable'));
                                    tableFy($('#pickupBaseStationsTable'));
                                      
                                      $('#waitingDispatchQueue').hide(800);
                                      $('#dispatchQueueDiv').show(800);
                                      
                                      //now update the summary stats since the queue has been updated
                                      ocpu.call('dispatchSummaries', {dispatch: RDatasModel.get('dispatchSessionID'), baseData: RDatasModel.get('baseDataSessionID')}, function(session){
                                        console.log('creating dispatch summaries');
                                        
                                        RDatasModel.setDispatchSummariesID(session);
                                        session.getObject(function(data){
                                            console.log(data);
                                            //fill in the dispatch and system analysis tables
                                            makeTables($('#dispatchSummaryTable tbody'),
                                              ["profitPerHour", "profitPerMile", "milesPerTruck", "hoursPerTruck", "loadsPerTruck"],
                                              data.dispatch);
                                            tableFy($('#dispatchSummaryTable'));
                                            
                                            //dispatchByCustomer
                                            makeTables($('#dispatchByCompanyTable tbody'),
                                              ["COMPANY_NA","avgTimeToService", "profitPerHour", "profitPerLoad", "loads", "avgMilesPerLoad"],
                                              data.dispatchByCompany);
                                            tableFy($('#dispatchByCompanyTable'));
                                            
                                            
                                            //dispatchByCounty
                                            makeTables($('#dispatchByCountyTable tbody'),
                                              ["COUNTY","avgTimeToService", "profitPerHour", "profitPerLoad", "loads", "avgMilesPerLoad"],
                                              data.dispatchByCounty);
                                            tableFy($('#dispatchByCountyTable'));
                                            
                                            $('#waitingReports').hide(800);
                                            $('#reportsDiv').show(800);
                                            
                                            //all other dataDivs will be populated by now...show them
                                            $('.dataDiv').show(800);
                                            
                                          });
                                        
                                        //get the summary metrics for just the top of the page
                                        ocpu.call('dispatchBriefSummary', {dispatchSummary: RDatasModel.get('dispatchSummariesID'), baseData: RDatasModel.get('baseDataSessionID')}, function(session){
                                          
                                          RDatasModel.setDispatchMetricsID(session);
                                          
                                          session.getObject(function(data){
                                            console.log('creating dispatchQueueMetrics');
                                            
                                            $(".efficiencyMetric > .announcement-heading").html(data.efficiency);
                                            $(".serviceMetric > .announcement-heading").html(data.loadServiceTime);
                                            $(".loadMetric >  .announcement-heading").html(data.load);
                                          
                                            makeTables($('#overUnderLoadTable tbody'), 
                                              ["BaseStation", "loads", "trucks", "loadMilesPerTruck", "trucksNeeded", "trucksOverUnder"],
                                              data.utilizationData);
                                            tableFy($('#overUnderLoadTable'));
                                            
                                            $('#waitingResourceAllocation').hide(800);
                                            $('#resourceAllocationDiv').show(800);
                                          });
                                          
                                         
                                          
                                        });
                                      });
                                      
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

makeTablesWLinks = function(tbody, anchor,props, linkColClass, data){
          $.each(data, function(i, dataPoint) {
            var tr = $('<tr>');
            $.each(props, function(i, prop) {
              if(linkColClass[i]!=null){
                var td = $('<td>')
                $('<a href="#'+anchor+'" class='+linkColClass[i]+'>').html(dataPoint[prop]).appendTo(td);
                td.appendTo(tr);
              }else{
                $('<td>').html(dataPoint[prop]).appendTo(tr);
              }
                
            });
            tbody.append(tr);
          })
          setOnClicks();      
}

//this is janky javascript... should be abstracted more... but whatever 
setOnClicks = function(){
    $('.truck').click(function(event){
      
      console.log(this);
      $('#dispatchQueueSubDiv').show(800);
      
      //display a dataTable but with only the selected truck
      
      
      
      //display alternatives for that truck
      
    });
    $('.pickup').click( function(event){
      // do something like bring up a truck table
    
    });
}

tableFy = function(table){
  //tableify the dispatch queue and all the other tables
    table.DataTable();
  
}
tableFyEditable = function(table, dataSession, tableID, colnames, editable){
  
    ocpu.call('returnTable', {data: dataSession, table: tableID}, function(session){
      
        var editor = new $.fn.dataTable.Editor( {
          ajax: function(method, url, data, success, error ){console.log(method);},
          table: '#baseStationsTable',
          fields: editable
        });
        
        $(table).DataTable( {
          ajax: session.loc+'R/.val/json',
          dom: "Tfrtip",
          columns: colnames,
          tableTools: {
            sRowSelect: 'os',
            aButtons: [
                { sExtends: 'editor_create', editor: editor },
                { sExtends: 'editor_edit',   editor: editor },
                { sExtends: 'editor_remove', editor: editor }
            ]
          }
        });
        $(table).on( 'click', 'tbody td', function () {
          editor.inline( this );
        } );
      
    });
     
      
  
  /*
  var editor = new $.fn.dataTable.Editor( {
    ajax:  '../R/',
    table: table,
    fields: [
        { label: 'First name', name: 'first_name' },
        { label: 'Last name',  name: 'last_name'  },
        // etc
        ]
    } );*/
    
    


}

tableFyWCheckBox = function(table){
 // http://editor.datatables.net/examples/api/checkbox.html
}
exportTableToCSV = function(table, filename) {
        
        var $rows = table.find('tr:has(td)'),

            // Temporary delimiter characters unlikely to be typed by keyboard
            // This is to avoid accidentally splitting the actual contents
            tmpColDelim = String.fromCharCode(11), // vertical tab character
            tmpRowDelim = String.fromCharCode(0), // null character

            // actual delimiter characters for CSV format
            colDelim = '","',
            rowDelim = '"\r\n"',

            // Grab text from table into CSV formatted string
            csv = '"' + $rows.map(function (i, row) {
                var $row = $(row),
                    $cols = $row.find('td');

                return $cols.map(function (j, col) {
                    var $col = $(col),
                        text = $col.text();

                    return text.replace('"', '""'); // escape double quotes

                }).get().join(tmpColDelim);

            }).get().join(tmpRowDelim)
                .split(tmpRowDelim).join(rowDelim)
                .split(tmpColDelim).join(colDelim) + '"',

            // Data URI
            csvData = 'data:application/csv;charset=utf-8,' + encodeURIComponent(csv);

        $(this)
            .attr({
            'download': filename,
                'href': csvData,
                'target': '_blank'
        });
    }

    