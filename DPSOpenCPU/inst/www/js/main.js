var baseDataSessionID;
var dispatchSessionID;
var dispatchSummariesID;
var dispatchMetricsID;

RDataModel = Backbone.Model.extend({
        defaults:{
          baseDataSessionID: null,
          dispatchSessionID: null,
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

$(document).ready(function() {
    
    User = new UserModel();  // when there's an actual user, we'll pull their details out of the node.js server
    RDatas = new RDataModel({userModel: User}); //when there's an actual user, we'll pass the user into the RDatas model and instead of pseudo data we'll get real dispatch data back.
    
    $('#dispatchQueueDiv').hide();
    
} );
getDemoData = function(RDatasModel){
  var req = ocpu.call("baseData", {pickups: 100}, function(session){
            console.log('getting demo Data');
            RDatasModel.setBaseDataSessionID(session);
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
              
            });
            
          });
  
}
//do the dispatch and fill in the table for the dispatch Queue
dispatchQueue = function(baseDataSession, RDatasModel){
  console.log('dispatching queue...')
          $('#dispatchQueueDiv').hide(800);
          $('#waitingDispatchQueue').show(800);
          var req = ocpu.call('dispatchQueue', 
                              {data: baseDataSession, windowsAhead: 12}, 
                              function(session){
                                  //dispatchSessionID=session;
                                  RDatasModel.setDispatchSessionID(session);
                                  
                                  session.getObject(function(data){
                                    console.log(data);
                                    makeTables($('#dispatchQueue tbody'), 
                                      ["truckAssigned","WELL_NAME", "COMPANY_NA", "pickupdate","ETAPickup","type"], 
                                      data.dispatch);
                                      tableFy($('#dispatchQueue'));
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

tableFy = function(table){
  //tableify the dispatch queue and all the other tables
    table.DataTable();
  
}