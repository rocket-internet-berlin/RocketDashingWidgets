require 'aws'

cloudwatch = nil

SCHEDULER.every '1m', first_in: 0 do |job|
  parameters = settings.use_cloudwatch_alarms
  return unless parameters

  cloudwatch ||= AWS::CloudWatch::Client.new(
      region: parameters.need(:region),
      access_key_id: parameters.need(:access_key_id),
      secret_access_key: parameters.need(:secret_access_key)
  )

  ok_alarm_count = 0
  total_alarms_count = 0
  triggered_alarms = []

  response = cloudwatch.describe_alarms

  has_alarms = false

  response.metric_alarms.each do |alarm|
    total_alarms_count += 1

    truncator = RocketDashing::Truncator.new

    has_alarms = true if !has_alarms && alarm[:state_value] == 'ALARM'

    alarm[:state_value] == 'OK' ?
        ok_alarm_count += 1 :
        triggered_alarms << {cols: [
            {value: truncator.truncate(alarm[:alarm_name], 27)},
            {value: truncator.truncate(alarm[:state_value], 5)}
        ]}
  end

  color = 'green'
  if has_alarms
    color = 'red'
  elsif !triggered_alarms.empty?
    color = 'yellow'
  end

  send_event 'cloudwatch-alarms-ok', {
                                       value: "#{ok_alarm_count}/#{total_alarms_count}",
                                       color: color
                                   }
  send_event 'cloudwatch-alarms-failed', {
                                           rows: triggered_alarms,
                                           moreinfo: "#{triggered_alarms.count} problems",
                                           color: color
                                       }
end