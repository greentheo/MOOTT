## Display Data, functions which take some of the data and turn it into GeoJSON and such.

#'  This function takes a list (like baseData) and a table name and returns just that table
#'  @export
returnTable = function(data, table){
  returnList = list()
  returnList[["aaData"]] = data[[table]]
  return(returnList)
}