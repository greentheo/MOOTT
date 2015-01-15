RDataModel = Backbone.Model.extend({
        defaults:{
          baseDataSessionID: null,
          dispatchSessionID: null,
          optBaseStationID: null,
          dispatchSummariesID: null,
          dispatchMetricsID: null,
          vAltID: null,
          vAltLoad: null,
          vAltTime: null,
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
        setVAltID: function(session){
          this.set({vAltID: session});
        },
        setVAltLoad: function(load){
          this.set({vAltLoad: load});        
        },
        setVAltTime: function(time){
          this.set({vAltTime: time});        
        },
        
        //other functions which can be triggered without any change triggers
        changeTruckLoad: function(newTruck){
          //hide subQueues
          $('#dispatchQueueSubDiv').hide(800);
          //reassign the current vAltLoad and Time ticket in the dispatch queue to the new truck
          
          //recalculate queue
        },
        rebalanceTrucksStations: function(){
          //change the truck to base station assignments
          
          //re dispatch
        },
        changeTruckStatus: function(truck){
          //change the truck's status
          
          //re dispatch
        }
    });

dataTablesBB = Backbone.Model.extend({
  defaults:{
    truckLoadDataTable: null,
    viableAltTable: null
  },
  initialize: function(){
    this.on('change:truckLoadDataTable', function(model){
      model.get('truckLoadDataTable').rows().draw();
    })
    
  },
  setTruckLoadTable: function(table){
    this.set({truckLoadDataTable: table})
  },
  setViableAltTable: function(table){
    this.set({viableAltTable: table})
  }

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
var Tables;
//var editor;

$(document).ready(function() {
    
    User = new UserModel();  // when there's an actual user, we'll pull their details out of the node.js server
    RDatas = new RDataModel({userModel: User}); //when there's an actual user, we'll pass the user into the RDatas model and instead of pseudo data we'll get real dispatch data back.
    Tables = new dataTablesBB();
    
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
                
                
                //tableFy the tables now that there's data for them
                /*tableFyEditable('#baseStationsTable', RDatasModel.get('baseDataSessionID'), 'baseStations', 
                  [{data: "station"}, {data:"lat"}, {data:"long"}],
                  [{label: "Station", name: "station"}, {label: "Lat", name: "lat"}, {label: "Long", name: "long"}]);
                  */
                tableFy($('#baseStationsTable'));  
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
                              {data: baseDataSession, windowsAhead: 3}, 
                              function(session){
                                  //dispatchSessionID=session;
                                  RDatasModel.setDispatchSessionID(session);
                                  
                                  session.getObject(function(data){
                                    console.log(data);
                                    makeTablesWLinks($('#dispatchQueue tbody'), 
                                      "dispatchQueueSubDiv",
                                      ["pickupdate", "truckAssigned","WELL_NAME", "COMPANY_NA","ETAPickup","assignedDropOff","type"],
                                      [null, "truck","pickup", "company", null, "dropOff",null],
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
                                    
                                    Tables.setTruckLoadTable(tableFy($('#truckLoadTable')));
                                    Tables.setViableAltTable(tableFy($('#viableAltTable')));
                                    
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

//basically this only applies to the main dispatchQueue table ... doesn't make sense for other tables
///probably should abstract it a bit more for other tasks.
makeTablesWLinks = function(tbody, anchor,props, linkColClass, data){
        tbody.find("tr").remove();
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
          setOnClicks(data);      
}

changeTables = function(table,  props, data, anchor,linkColClass){
  table.clear();                                
      $.each(data, function(i, row){
        newRow=[];
        $.each(props, function(j, prop){
          if(linkColClass[j]!=null){
               newRow.push('<a href="#'+anchor+'" class='+linkColClass[j]+'>'+row[prop]+'</a>');
          }else{
            newRow.push(row[prop]);
          }
        });
        table.row.add(newRow);
      });
  return(table);    
}
//this is janky javascript... should be abstracted more... but whatever 
//sets click handlers for a few different classes of links that come from the dispatch table
setOnClicks = function(data){
    //filter by truck
    $('.truck').click(function(event){
      var truck=$(this).text();
      //display a dataTable but with only the selected truck
      //filter the dispatch data from the selected truck
      filteredData = $.grep(data, function(d){
        return d.truckAssigned==truck;
      });
          
       changeTables(Tables.attributes.truckLoadDataTable, 
                    ["pickupdate", "truckAssigned","WELL_NAME", "COMPANY_NA","ETAPickup","assignedDropOff","type"],
                    filteredData,
                    "dispatchQueueSubDiv",
                    [null, "truck","pickup", "company", null, "dropOff",null]); 
      Tables.attributes.truckLoadDataTable.rows().draw();
      setOnClicks(data);
      $('#dispatchQueueSubDiv').show(800);
      
      
    });
    //filter by customer
    $('.company').click(function(event){
      var cust=$(this).text();
      //display a dataTable but with only the selected truck
      //filter the dispatch data from the selected truck
      filteredData = $.grep(data, function(d){
        return d.COMPANY_NA==cust;
      });
          
      changeTables(Tables.attributes.truckLoadDataTable, 
                    ["pickupdate", "truckAssigned","WELL_NAME", "COMPANY_NA","ETAPickup","assignedDropOff","type"],
                    filteredData,
                    "dispatchQueueSubDiv",
                    [null, "truck","pickup", "company", null, "dropOff",null]); 
      Tables.attributes.truckLoadDataTable.rows().draw();
      setOnClicks(data);
      $('#dispatchQueueSubDiv').show(800);
    
    });
    //filter by dropoff points
    $('.dropOff').click(function(event){
      var dropOff=$(this).text();
      //display a dataTable but with only the selected truck
      //filter the dispatch data from the selected truck
      filteredData = $.grep(data, function(d){
        return d.assignedDropOff==dropOff;
      });
          
      changeTables(Tables.attributes.truckLoadDataTable, 
                    ["pickupdate", "truckAssigned","WELL_NAME", "COMPANY_NA","ETAPickup","assignedDropOff","type"],
                    filteredData,
                    "dispatchQueueSubDiv",
                    [null, "truck","pickup", "company", null, "dropOff",null]); 
      Tables.attributes.truckLoadDataTable.rows().draw();
      setOnClicks(data);
      $('#dispatchQueueSubDiv').show(800);
    
    });
    
    //pickup is the class that is a link to the actual load to be reassigned
    $('.pickup').click( function(event){
      //show the processing div
      $('#waitingViableAlt').show(800);
      $('#viAltTableDiv').hide();
      
      // bring up the viable alternatives table
      var load=$(this).text();
      RDatas.setVAltLoad('load');
      RDatas.setVAltTime($(this).parent().parent().find('td:nth-child(1)').html());
      $('#loadNameH3').html('Load Name: '+load+'<br>Requested: '+RDatas.get('vAltTime'));
      
      //display a dataTable but with only the selected truck
      //filter the dispatch data from the selected truck
      filteredData = $.grep(data, function(d){
        return d.WELL_NAME==load;
      });
          
      changeTables(Tables.attributes.truckLoadDataTable, 
                    ["pickupdate", "truckAssigned","WELL_NAME", "COMPANY_NA","ETAPickup","assignedDropOff","type"],
                    filteredData,
                    "dispatchQueueSubDiv",
                    [null, "truck","pickup", "company", null, "dropOff",null]); 
      Tables.attributes.truckLoadDataTable.rows().draw();
      setOnClicks(data);
      
      //now make the call to R to find the viable alternatives for a certain lease (R goes through a mini routing demo)
      ocpu.call('viableAlternatives', {baseData: RDatas.get('baseDataSessionID'), dispatch: RDatas.get('dispatchSessionID') , loadName: load}, function(session){
        //store the session in the RData model
        RDatas.setVAltID(session);                                  
        session.getObject(function(sessionData){
          
          var newData = [];
          //add on a "change load to this truck button"
          $.each(sessionData.viableAlt, function(i, row){
            row["reassign"]='<button class="reassignBtn" truck="'+row["truckNumber"]+'">Assign Load</button>';
            newData.push(row);
          });
          changeTables(Tables.attributes.viableAltTable, 
                    ["rank","truckNumber","station", "distToPickup", "loadOnBooks","loadForecast","reassign"],
                    newData,
                    "dispatchQueueSubDiv",
                    [null, "truck", null, null, null, null, null]); 
          Tables.attributes.viableAltTable.rows().draw();
          
          setOnClicks(data);
          
          //hide the calculating div
          $('#waitingViableAlt').hide();
          $('#viAltTableDiv').show(800);
        });
      })
      
      
      
      $('#dispatchQueueSubDiv').show(800);
    
    });
    
    $('.reassignBtn').click(function(event){
        //trigger the change truck-load function in the backbone model
        RDatas.changeTruckLoad($(this)[0].attributes.truck);
        
        
      });   
    
}

tableFy = function(table){
  //tableify the dispatch queue and all the other tables
    return table.DataTable({
      "searching": true
    });
  
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

    