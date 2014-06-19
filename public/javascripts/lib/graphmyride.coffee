window.loadRideCSV = ( file, callback ) ->
  JSZipUtils.getBinaryContent file, ( err, data ) ->
    throw err if err
    zip = new JSZip( data )
    #csvContent = zip.file('2014-06-14-0801_Biking_WF.csv').asText()
    csvContent = zip.file( /.*\.csv/ )[0].asText()

    lines = csvContent.split '\n'

    ride = new Ride
    parseCSVHeaders ride, lines[0..1]
    parseCSVSensors ride, lines[6..12]
    parseCSVWorkoutInfo ride, lines[13..14]

    intervalLines = lines[16...findEndOfBlock( lines, 16 )]
    parseCSVInterval ride, intervalLines

    rideLines = lines[16 + intervalLines.length + 1..]
    parseCSVRideData ride, rideLines

    console.log ride

# Device,fisica,model,key,version,1,AppVersion,4.2.2
# Year,2014,Month,6,Day,14,Hour,8,Minute,1,Second,27,BatteryUsage (%),0.000000
parseCSVHeaders = ( ride, headers ) ->
  headerInfos = {}
  for header in headers
    headerInfo = header.split( ',' )
    for name, index in headerInfo by 2
      headerInfos[name] = headerInfo[index + 1]

  # FIXME Add a 'date' attribute usingfields Year,Month,Day,Hour,Minute,Second
  headerInfos.date = new Date
  ride.headerInfos = headerInfos;

# sensor,present,smrec,zeroavg,model
# pwr,no,no,no,n/a
# spd,yes,no,no,n/a
# cad,yes,no,no,n/a
# hr,yes,no,no,n/a
# footpod,no,no,no,n/a
# gps,yes,no,no,n/a
parseCSVSensors = ( ride, sensorLines ) ->
  sensorInfos = []
  sensorHeaderLine = sensorLines[0]
  sensorHeaders = sensorHeaderLine.split( ',' )

  for sensorLine, index in sensorLines[1..]
    data = parseCSVWithHeader sensorHeaders, sensorLine
    sensorInfos[data.sensor]?={}
    sensorInfos[data.sensor].present = data.present

  ride.setSensorPresence new SensorPresence sensorInfos['spd']?.present == 'yes', sensorInfos['cad']?.present == 'yes', sensorInfos['hr']?.present == 'yes', sensorInfos['gps']?.present == 'yes'

# workout,starttime,runningtime,pausedtime,wheeldist,cadavg,spdavg,pwravg,pwrPedalContribution,hravg,striderateavg,stridedist,gpsdist,smoothnessavg
# ,0,16676.505102,1006.103770,132781.593750,78.011276,7.890861,0.000000,0.000000,143.000000,0.000000,0.000000,133391.609375,0.000000
parseCSVWorkoutInfo = ( ride, workoutLines ) ->
  workout = parseCSVWithHeader workoutLines[0].split( ',' ), workoutLines[1]
  ride.setGlobalStats new StatsSummary workout.runningtime, workout.pausedtime, workout.wheeldist, workout.cadavg, workout.spdavg, workout.hravg

parseCSVInterval = ( ride, intervalLines ) ->
  interval = {}

  headers = intervalLines[0].split( ',' )
  intervalData = parseCSVWithHeader headers, intervalLines[1]
  intervalStats = new StatsSummary intervalData.runningtime, intervalData.pausedtime, intervalData.wheeldist, intervalData.cadavg, intervalData.spdavg, intervalData.hravg

  intervalPauses = []
  for line, index in intervalLines[2..]
    activityData = parseCSVWithHeader headers, line
    if parseFloat( activityData.pausedtime ) != 0
      intervalPauses.push new SegmentPause parseFloat( activityData.starttime ), parseFloat( activityData.starttime ) + parseFloat( activityData.pausedtime )

  ride.setInterval new Interval( intervalStats, intervalPauses )

parseCSVRideData = ( ride, lines ) ->
  headers = lines[0].split( ',' )
  points = []
  for line, index in lines[1..]
    data = parseCSVWithHeader headers, line
    points.push new StatPoint data.interval
    , data.time
    , data.spd_accdist
    , data.spd_instspeed
    , data.cad_cadence
    , data.hr_heartrate
    , data.gps_altitude
    , data.gps_lat
    , data.gps_lon
    , data.gps_dist # In meter
    , data.gps_speed
    , data.paused == '1'
  ride.setStatPoints points
    
class Ride

  constructor: ( @data ) ->
    @headerInfos = {}

  setSensorPresence: ( sensorPresence ) ->
    @sensorPresence = sensorPresence

  setGlobalStats: ( globalStats ) ->
    @globalStats = globalStats

  setInterval: ( interval ) ->
    @interval = interval
    
  setStatPoints: ( statPoints ) ->
    @statPoints = statPoints

class SensorPresence
  constructor: ( @speed, @cadence, @heartrate, @gps ) ->

class Interval
  # @stats is SegmentStats
  # @pauses is SegmentPause[] in start time ascending order
  constructor: ( @stats, @pauses ) ->

class StatsSummary
  constructor: ( @active_duration_in_second, @paused_duration_in_second, @distance_in_meter, @cadence_average_in_RPM, @speed_average_in_meter_sec, @heartrate_average_in_BPM ) ->

  getSpeedAverageInKmPerHour: () ->
    return @speed_average_in_meter_sec / 1000 * 60 * 60

class SegmentPause
  constructor: ( @pause_start, @pause_end ) ->
    @pause_duration_in_second = @pause_end - @pause_start

class StatPoint
  constructor: ( @interval,@time_in_sec, @distance_in_meter_from_speed_sensor, @speed_in_meter_per_second, @cadence, @heartrate, @altitude, @latitude, @longitude, @gps_distance_in_meter_from_GPS,
    @gps_speed_in_meter_per_second, @paused ) ->

#
# CSV Parsing utils
#

# headers is an array of field name, csv is a csv line that should match the header fields
parseCSVWithHeader = ( headers, csv ) ->
  data = {}
  for value, index in csv.split( ',' )
    data[headers[index]] = value
  return data

# Find the first empty line after offset
findEndOfBlock = ( lines, offset ) ->
  for line, index in lines[offset..]
    return offset + index if line == ''
  return lines.length 